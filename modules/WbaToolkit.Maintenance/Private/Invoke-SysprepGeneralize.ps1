function Invoke-SysprepGeneralize {
    <#
    .SYNOPSIS
        Executa sysprep.exe /oobe /generalize /shutdown /quiet e devolve o codigo de saida.

    .DESCRIPTION
        O /quiet e obrigatorio: sem ele, uma falha do sysprep abre uma janela de erro e o
        processo fica parado esperando clique, travando execucoes sem operador (BCK-072).
        Os detalhes da falha ficam em %WINDIR%\System32\Sysprep\Panther\setuperr.log.

    .PARAMETER SysprepPath
        Caminho do sysprep.exe. Padrao: %WINDIR%\System32\Sysprep\sysprep.exe.

    .OUTPUTS
        System.Int32. Codigo de saida do sysprep.exe.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([int])]
    param(
        [string]$SysprepPath = ([System.IO.Path]::Combine(
                [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::System),
                'Sysprep', 'sysprep.exe'))
    )

    $argumentos = '/oobe /generalize /shutdown /quiet'
    if (-not $PSCmdlet.ShouldProcess($SysprepPath, "Executar sysprep $argumentos")) {
        return 0
    }

    $processo = Start-Process -FilePath $SysprepPath -ArgumentList $argumentos -Wait -PassThru -ErrorAction Stop
    return [int]$processo.ExitCode
}
