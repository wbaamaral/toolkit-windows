function Invoke-SysprepPreparation {
    <#
    .SYNOPSIS
        Aplica o conjunto de tweaks de perfil ao Default user do Windows.

    .DESCRIPTION
        Localiza todos os arquivos .reg no diretorio especificado e aplica-os
        ao perfil Default do Windows via manipulacao offline do hive de registro
        NTUSER.DAT. O hive e montado uma unica vez, todos os tweaks sao importados
        em sequencia e o hive e desmontado ao final.

        Antes de qualquer modificacao, cria automaticamente um backup do arquivo
        NTUSER.DAT no diretorio de backups da sessao.

        Em modo DryRun, os tweaks sao apenas enumerados sem qualquer modificacao
        no sistema.

    .PARAMETER RegFilesDirectory
        Caminho para o diretorio contendo os arquivos .reg de tweak.
        Os arquivos sao processados em ordem alfabetica de nome.

    .PARAMETER BackupsPath
        Diretorio onde o backup do NTUSER.DAT sera armazenado.
        Obrigatorio quando DryRun nao esta ativo.

    .PARAMETER DryRun
        Simula a operacao sem efetuar alteracoes no registro ou no sistema de arquivos.

    .EXAMPLE
        $resultados = Invoke-SysprepPreparation `
            -RegFilesDirectory '.\regfiles\sysprep' `
            -BackupsPath $session.BackupsPath
        $resultados | Format-Table Tweak, Success, Message -AutoSize

    .EXAMPLE
        Invoke-SysprepPreparation -RegFilesDirectory '.\regfiles\sysprep' -DryRun

    .OUTPUTS
        System.Management.Automation.PSCustomObject[]
        Array de objetos com as propriedades: Tweak, Success, Message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
        [string]$RegFilesDirectory,

        [Parameter(Mandatory = $false)]
        [string]$BackupsPath,

        [Parameter(Mandatory = $false)]
        [switch]$DryRun
    )

    $arquivos = @(Get-ChildItem -LiteralPath $RegFilesDirectory -Filter '*.reg' | Sort-Object Name)

    if ($arquivos.Count -eq 0) {
        Write-Warn "Nenhum arquivo .reg encontrado em: $RegFilesDirectory"
        return @()
    }

    if ($DryRun) {
        $resultados = foreach ($arquivo in $arquivos) {
            $nome = [System.IO.Path]::GetFileNameWithoutExtension($arquivo.Name)
            Write-Verbose "DRY-RUN: aplicaria tweak '$nome'."
            [pscustomobject]@{ Tweak = $nome; Success = $true; Message = 'DryRun.' }
        }
        return @($resultados)
    }

    if (-not $BackupsPath) {
        throw 'O parametro BackupsPath e obrigatorio quando DryRun nao esta ativo.'
    }

    $destBackup = Backup-DefaultUserHive -BackupsPath $BackupsPath
    Write-Info "Backup do perfil Default criado: $destBackup"

    $resultados = [System.Collections.ArrayList]::new()

    Invoke-WithDefaultUserHive -ScriptBlock {
        param($mountPoint)

        foreach ($arquivo in $arquivos) {
            $nome = [System.IO.Path]::GetFileNameWithoutExtension($arquivo.Name)
            try {
                Invoke-RegFileImport -RegFilePath $arquivo.FullName -MountPoint $mountPoint
                Write-Ok "Tweak aplicado: $nome"
                $null = $resultados.Add([pscustomobject]@{ Tweak = $nome; Success = $true; Message = 'OK.' })
            }
            catch {
                Write-Warn "Falha no tweak '$nome': $($_.Exception.Message)"
                $null = $resultados.Add([pscustomobject]@{ Tweak = $nome; Success = $false; Message = $_.Exception.Message })
            }
        }
    }

    return @($resultados)
}
