function Import-RegistryTweakToDefaultProfile {
    <#
    .SYNOPSIS
        Aplica um arquivo de tweak de registro ao perfil Default do Windows.

    .DESCRIPTION
        Monta temporariamente o hive NTUSER.DAT do perfil Default, substitui
        as referencias de caminho no arquivo .reg para apontar ao ponto de
        montagem correto e importa as entradas. O hive e desmontado ao final.

        Em modo DryRun, a operacao e simulada sem qualquer modificacao no registro.

        O arquivo .reg deve referenciar 'hkey_users\default' (insensivel a maiusculas)
        nos caminhos de chave.

    .PARAMETER RegFilePath
        Caminho para o arquivo .reg contendo o tweak a aplicar.

    .PARAMETER DryRun
        Simula a operacao sem efetuar alteracoes no registro.

    .EXAMPLE
        Import-RegistryTweakToDefaultProfile -RegFilePath '.\regfiles\sysprep\Desativar_IDPublicitario.reg'

    .EXAMPLE
        Import-RegistryTweakToDefaultProfile -RegFilePath '.\regfiles\sysprep\Desativar_IDPublicitario.reg' -DryRun

    .OUTPUTS
        System.Management.Automation.PSCustomObject
        Objeto com as propriedades: Tweak, Success, Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$RegFilePath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $nomeTweak = [System.IO.Path]::GetFileNameWithoutExtension($RegFilePath)

    if ($DryRun) {
        Write-Verbose "DRY-RUN: aplicaria tweak '$nomeTweak' ao perfil Default."
        return [pscustomobject]@{ Tweak = $nomeTweak; Success = $true; Message = 'DryRun.' }
    }

    $regFile = $RegFilePath

    try {
        Invoke-WithDefaultUserHive -ScriptBlock {
            param($mountPoint)
            Invoke-RegFileImport -RegFilePath $regFile -MountPoint $mountPoint
        }
        return [pscustomobject]@{ Tweak = $nomeTweak; Success = $true; Message = 'OK.' }
    }
    catch {
        return [pscustomobject]@{ Tweak = $nomeTweak; Success = $false; Message = $_.Exception.Message }
    }
}
