function Test-SysprepEnvironment {
    <#
    .SYNOPSIS
        Verifica os pre-requisitos para executar a preparacao de imagem.

    .DESCRIPTION
        Realiza verificacoes de pre-voo para garantir que o sistema esta em estado
        adequado para a preparacao de imagem:

          - Sessao elevada com privilegios de Administrador
          - Windows 10 Pro (build 10240+) ou Windows 11 (build 22000+)
          - Executavel sysprep.exe presente no sistema
          - Sem BitLocker no volume do sistema, sem upgrade de versao e sem reinicio
            pendente (condicoes que o proprio sysprep recusa)

        Retorna objeto com IsValid = $false e lista de Errors quando alguma
        condicao obrigatoria nao e atendida. Warnings sao informativos e nao
        impedem a execucao.

    .PARAMETER AppxPolicy
        Block (padrao): pacote Appx bloqueador vira erro. Warn: vira aviso. Skip: nao verifica.

    .PARAMETER SystemStatePolicy
        Block (padrao): BitLocker, upgrade e reinicio pendente viram erro. Warn: viram aviso,
        para quando o sysprep nao sera executado nesta sessao.

    .EXAMPLE
        $resultado = Test-SysprepEnvironment
        if (-not $resultado.IsValid) {
            $resultado.Errors | ForEach-Object { Write-Fail $_ }
        }

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com as propriedades: IsValid, OsVersion, Edition, BuildNumber, Errors, Warnings, SysprepBlockers, AppxIssues, AutoLogonDetectado, GpoDetectado, SystemStateIssues.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Block', 'Warn', 'Skip')]
        [string]$AppxPolicy = 'Block',

        [ValidateSet('Block', 'Warn')]
        [string]$SystemStatePolicy = 'Block'
    )

    $erros     = New-Object 'System.Collections.Generic.List[string]'
    $avisos    = New-Object 'System.Collections.Generic.List[string]'
    $bloqueios = New-Object 'System.Collections.Generic.List[object]'
    $appxIssues = New-Object 'System.Collections.Generic.List[object]'
    $buildNum = 0
    $versaoSO = ''
    $edicao   = ''

    if (-not (Test-IsAdministrator)) {
        $erros.Add('Este script requer execucao como Administrador.')
    }

    # Falha em obter a versao via CIM e impeditiva (nao apenas informativa): sem ela
    # nao ha como validar build/edicao com seguranca antes de um sysprep irreversivel.
    try {
        $so = Get-CimInstanceSafe -ClassName 'Win32_OperatingSystem'
        if ($so) {
            $buildNum = [int]$so.BuildNumber
            $versaoSO = $so.Caption
        }
        else {
            $erros.Add('Nao foi possivel obter informacoes do sistema operacional via CIM (verificacao obrigatoria).')
        }
    }
    catch {
        $erros.Add("Verificacao de versao do SO via CIM falhou: $($_.Exception.Message)")
    }

    if ($buildNum -gt 0 -and $buildNum -lt 10240) {
        $erros.Add("Sistema operacional nao suportado (build $buildNum). Requer Windows 10 Pro (build 10240+) ou Windows 11.")
    }

    # Edicao via EditionID (independente de idioma; Caption seria localizado). Sysprep
    # so e suportado em Pro/Enterprise/Education — Home (Core) deve invalidar.
    try {
        $edicao = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
            -Name 'EditionID' -ErrorAction Stop).EditionID
    }
    catch {
        $erros.Add("Nao foi possivel determinar a edicao do Windows (EditionID): $($_.Exception.Message)")
    }
    if ($edicao -and $edicao -notmatch 'Professional|Enterprise|Education') {
        $erros.Add("Edicao do Windows nao suportada para sysprep: '$edicao'. Requer Pro, Enterprise ou Education.")
    }

    $sysprepExe = [System.IO.Path]::Combine(
        [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System),
        'Sysprep',
        'sysprep.exe'
    )
    if (-not (Test-Path -LiteralPath $sysprepExe)) {
        $erros.Add("sysprep.exe nao encontrado em: $sysprepExe")
    }

    # Condicoes que o proprio sysprep recusa (BitLocker, upgrade, reinicio pendente) e
    # estado de generalizacao anterior incompleto. Generalizar de novo uma maquina clonada
    # de imagem ja generalizada e suportado e nao e mais bloqueado (BCK-072).
    $estadoSistema = @(Get-SysprepSystemStateIssue)
    foreach ($issue in $estadoSistema) {
        if ($issue.Severity -eq 'Error' -and $SystemStatePolicy -eq 'Block') {
            $erros.Add($issue.Message)
        }
        else {
            $avisos.Add($issue.Message)
        }
    }

    # AutoLogon configurado antes do Sysprep pode travar o pos-generalizacao OOBE quando
    # as credenciais salvas nao existem na nova implantacao da imagem.
    $autoLogonDetectado = $false
    try {
        $autoLogonProp = Get-ItemProperty `
            -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' `
            -Name 'AutoAdminLogon' `
            -ErrorAction SilentlyContinue
        if ($autoLogonProp -and ($autoLogonProp.AutoAdminLogon -eq '1' -or $autoLogonProp.AutoAdminLogon -eq 1)) {
            $autoLogonDetectado = $true
            $avisos.Add('AutoLogon configurado (AutoAdminLogon=1). Sera desativado antes do Sysprep para evitar trava no pos-generalizacao OOBE.')
        }
    }
    catch {
        $avisos.Add("Nao foi possivel verificar configuracao de AutoLogon: $($_.Exception.Message)")
    }

    # Diretivas de grupo aplicadas ficam gravadas no registro e podem conflitar com a
    # generalizacao do Sysprep e com a nova implantacao da imagem.
    # A existencia das chaves de Policies nao basta: elas existem em toda instalacao.
    # So ha GPO quando existe evidencia concreta (GPO de dominio ou Registry.pol local).
    $gpoEvidencias = @(Get-SysprepGroupPolicyEvidence)
    $gpoDetectado  = $gpoEvidencias.Count -gt 0
    if ($gpoDetectado) {
        $avisos.Add("Diretivas de grupo aplicadas ($($gpoEvidencias -join '; ')). HKLM:\SOFTWARE\Policies\Microsoft sera exportada e removida antes do Sysprep para evitar conflitos na nova implantacao.")
    }

    if ($AppxPolicy -ne 'Skip') {
        try {
            $appxDetectados = @(Get-SysprepAppxProvisioningIssue -IncludeWarnings)
            foreach ($b in $appxDetectados) {
                $appxIssues.Add($b)
                $mensagem = "Pacote Appx pode bloquear Sysprep: $($b.PackageFullName) instalado para usuario, mas nao provisionado para todos os usuarios. Severidade: $($b.Severity). Motivo: $($b.Reason)."

                if ($b.Severity -eq 'Blocker') {
                    $bloqueios.Add($b)

                    if ($AppxPolicy -eq 'Block') {
                        $erros.Add($mensagem)
                    }
                    else {
                        $avisos.Add($mensagem)
                    }
                }
                else {
                    $avisos.Add($mensagem)
                }
            }
        }
        catch {
            if ($AppxPolicy -eq 'Block') {
                $erros.Add($_.Exception.Message)
            }
            else {
                $avisos.Add($_.Exception.Message)
            }
        }
    }

    return [pscustomobject]@{
        IsValid            = ($erros.Count -eq 0)
        OsVersion          = $versaoSO
        Edition            = $edicao
        BuildNumber        = $buildNum
        Errors             = $erros.ToArray()
        Warnings           = $avisos.ToArray()
        SysprepBlockers    = $bloqueios.ToArray()
        AppxIssues         = $appxIssues.ToArray()
        AutoLogonDetectado = $autoLogonDetectado
        GpoDetectado       = $gpoDetectado
        SystemStateIssues  = $estadoSistema
    }
}
