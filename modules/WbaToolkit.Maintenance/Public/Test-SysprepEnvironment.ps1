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
          - Sistema nao passou por sysprep anteriormente nesta instalacao

        Retorna objeto com IsValid = $false e lista de Errors quando alguma
        condicao obrigatoria nao e atendida. Warnings sao informativos e nao
        impedem a execucao.

    .EXAMPLE
        $resultado = Test-SysprepEnvironment
        if (-not $resultado.IsValid) {
            $resultado.Errors | ForEach-Object { Write-Fail $_ }
        }

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com as propriedades: IsValid, OsVersion, Edition, BuildNumber, Errors, Warnings, SysprepBlockers.
    #>
    [CmdletBinding()]
    param()

    $erros     = New-Object 'System.Collections.Generic.List[string]'
    $avisos    = New-Object 'System.Collections.Generic.List[string]'
    $bloqueios = New-Object 'System.Collections.Generic.List[object]'
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

    $pantherLog = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'Sysprep', 'Panther', 'setupact.log')
    if (Test-Path -LiteralPath $pantherLog) {
        try {
            $logConteudo = [System.IO.File]::ReadAllText($pantherLog, [System.Text.Encoding]::UTF8)
            if ($logConteudo -match 'SYSPREP_GENERALIZE_COMPLETE') {
                $erros.Add('Este sistema ja passou por sysprep anteriormente. Executar novamente pode causar instabilidades.')
            }
        }
        catch {
            $avisos.Add("Nao foi possivel verificar historico de sysprep: $($_.Exception.Message)")
        }
    }

    try {
        $appxBloqueantes = @(Get-SysprepAppxProvisioningIssue)
        foreach ($b in $appxBloqueantes) {
            $bloqueios.Add($b)
            $erros.Add("Pacote Appx pode bloquear Sysprep: $($b.PackageFullName) instalado para usuario, mas nao provisionado para todos os usuarios.")
        }
    }
    catch {
        $erros.Add($_.Exception.Message)
    }

    return [pscustomobject]@{
        IsValid         = ($erros.Count -eq 0)
        OsVersion       = $versaoSO
        Edition         = $edicao
        BuildNumber     = $buildNum
        Errors          = $erros.ToArray()
        Warnings        = $avisos.ToArray()
        SysprepBlockers = $bloqueios.ToArray()
    }
}
