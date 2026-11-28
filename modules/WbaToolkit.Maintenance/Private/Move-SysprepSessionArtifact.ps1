function Move-SysprepSessionArtifact {
    <#
    .SYNOPSIS
        Tira da imagem os artefatos da sessao de preparacao antes do sysprep.

    .DESCRIPTION
        Tudo o que fica no disco no momento do sysprep vai para todos os clones da imagem.
        A sessao de preparacao grava relatorio, log e backups (NTUSER.DAT do perfil Default
        e as diretivas exportadas). Esta funcao (BCK-072):

        - com -CopyTo: copia a pasta da sessao para <CopyTo>\<computador>_<sessao> e confere
          a copia; sem -KeepInImage, remove a pasta local e devolve a sessao apontando para a
          copia, para os registros seguintes nao recriarem a pasta na imagem;
        - sem -CopyTo e sem -KeepInImage: remove so a pasta de backups da sessao;
        - com -KeepInImage: nao remove nada.

        Falha na copia lanca excecao antes de qualquer remocao.

    .OUTPUTS
        PSCustomObject com Session (sessao a usar dali em diante), CopiedTo e RemovedPaths.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]$Session,
        [string]$CopyTo,
        [switch]$KeepInImage
    )

    $sessaoAtual = $Session
    $copiadoPara = $null
    $removidos   = New-Object 'System.Collections.Generic.List[string]'
    $origem      = [string]$Session.Path

    if (-not [string]::IsNullOrWhiteSpace($CopyTo)) {
        $destino = Join-Path $CopyTo ("{0}_{1}" -f $env:COMPUTERNAME, (Split-Path -Leaf $origem))
        if ($PSCmdlet.ShouldProcess($destino, 'Copiar sessao de preparacao para fora da imagem')) {
            New-Item -ItemType Directory -Path $destino -Force -ErrorAction Stop | Out-Null
            Get-ChildItem -LiteralPath $origem -Force -ErrorAction Stop |
                Copy-Item -Destination $destino -Recurse -Force -ErrorAction Stop

            $arquivosOrigem  = @(Get-ChildItem -LiteralPath $origem -Recurse -File -Force -ErrorAction Stop).Count
            $arquivosDestino = @(Get-ChildItem -LiteralPath $destino -Recurse -File -Force -ErrorAction Stop).Count
            if ($arquivosDestino -lt $arquivosOrigem) {
                throw "Copia incompleta da sessao para '$destino' ($arquivosDestino de $arquivosOrigem arquivos)."
            }
            $copiadoPara = $destino
        }
    }

    if (-not $KeepInImage) {
        if ($copiadoPara) {
            if ($PSCmdlet.ShouldProcess($origem, 'Remover pasta local da sessao (copiada para fora da imagem)')) {
                Remove-Item -LiteralPath $origem -Recurse -Force -ErrorAction Stop
                $removidos.Add($origem)

                $redirecionar = {
                    param([string]$Caminho)
                    if ([string]::IsNullOrWhiteSpace($Caminho)) { return $Caminho }
                    if ($Caminho.StartsWith($origem, [System.StringComparison]::OrdinalIgnoreCase)) {
                        return ($copiadoPara + $Caminho.Substring($origem.Length))
                    }
                    return $Caminho
                }
                $sessaoAtual = $Session.PSObject.Copy()
                $sessaoAtual.Path        = $copiadoPara
                $sessaoAtual.LogsPath    = & $redirecionar ([string]$Session.LogsPath)
                $sessaoAtual.BackupsPath = & $redirecionar ([string]$Session.BackupsPath)
            }
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$Session.BackupsPath) -and
            (Test-Path -LiteralPath $Session.BackupsPath -PathType Container)) {
            if ($PSCmdlet.ShouldProcess($Session.BackupsPath, 'Remover backups da sessao da imagem')) {
                Remove-Item -LiteralPath $Session.BackupsPath -Recurse -Force -ErrorAction Stop
                $removidos.Add([string]$Session.BackupsPath)
            }
        }
    }

    [pscustomobject]@{
        Session      = $sessaoAtual
        CopiedTo     = $copiadoPara
        RemovedPaths = $removidos.ToArray()
    }
}
