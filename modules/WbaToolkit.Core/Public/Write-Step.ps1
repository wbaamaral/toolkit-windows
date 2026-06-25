function Write-Step {
    <#
    .SYNOPSIS
        Emite um marcador de progresso textual no estilo [NN%] mensagem.

    .DESCRIPTION
        Exibe uma linha em branco seguida de "[Percent%] Message" em ciano.
        Nao usa Write-Progress para evitar que a barra de progresso cubra
        prompts interativos em scripts que intercalam etapas longas com
        perguntas ao operador (ADR 0021).

    .PARAMETER Message
        Descricao da etapa atual.

    .PARAMETER Percent
        Percentual de conclusao (0-100).

    .EXAMPLE
        Write-Step 'Limpando temporarios' 25

        Exibe: [25%] Limpando temporarios
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateRange(0, 100)]
        [int]$Percent
    )

    Write-Host ''
    Write-Host "[$Percent%] $Message" -ForegroundColor Cyan
}
