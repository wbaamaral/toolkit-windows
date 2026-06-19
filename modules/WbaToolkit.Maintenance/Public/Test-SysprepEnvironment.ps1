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
        Objeto com as propriedades: IsValid, OsVersion, BuildNumber, Errors, Warnings.
    #>
    [CmdletBinding()]
    param()

    $erros    = New-Object 'System.Collections.Generic.List[string]'
    $avisos   = New-Object 'System.Collections.Generic.List[string]'
    $buildNum = 0
    $versaoSO = ''

    if (-not (Test-IsAdministrator)) {
        $erros.Add('Este script requer execucao como Administrador.')
    }

    try {
        $so = Get-CimInstanceSafe -ClassName 'Win32_OperatingSystem'
        if ($so) {
            $buildNum = [int]$so.BuildNumber
            $versaoSO = $so.Caption
        }
        else {
            $avisos.Add('Nao foi possivel obter informacoes do sistema operacional via CIM.')
        }
    }
    catch {
        $avisos.Add("Verificacao de versao do SO falhou: $($_.Exception.Message)")
    }

    if ($buildNum -gt 0 -and $buildNum -lt 10240) {
        $erros.Add("Sistema operacional nao suportado (build $buildNum). Requer Windows 10 Pro (build 10240+) ou Windows 11.")
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

    return [pscustomobject]@{
        IsValid     = ($erros.Count -eq 0)
        OsVersion   = $versaoSO
        BuildNumber = $buildNum
        Errors      = $erros.ToArray()
        Warnings    = $avisos.ToArray()
    }
}
