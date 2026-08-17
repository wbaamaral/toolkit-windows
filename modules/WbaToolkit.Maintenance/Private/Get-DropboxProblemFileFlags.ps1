# Projeto: wba-toolkit
# Autor: wbaamaral

function Get-DropboxProblemFileFlags {
    <#
    .SYNOPSIS
        Detecta problemas conhecidos de nome/caminho que impedem ou atrapalham a sincronizacao do Dropbox.

    .DESCRIPTION
        Logica nova (nao existe no script autonomo original). Verifica um item pelo
        nome e caminho completo em busca de padroes que o Windows ou o cliente
        Dropbox rejeitam ou tratam mal:

          - nome reservado do Windows (CON, PRN, AUX, NUL, COM1-9, LPT1-9);
          - caracteres invalidos no nome (< > : " | ? * e controle 0-31);
          - nome terminando em ponto ou espaco;
          - caminho completo com mais de 259 caracteres.

    .PARAMETER Name
        Nome do item (sem diretorio), por exemplo 'CON.txt' ou 'relatorio final .docx'.

    .PARAMETER FullPath
        Caminho completo do item, usado apenas para a checagem de comprimento.

    .EXAMPLE
        Get-DropboxProblemFileFlags -Name 'CON.txt' -FullPath 'C:\Dropbox\CON.txt'

    .OUTPUTS
        System.String[]
        Lista de problemas encontrados. Vazia quando nenhum problema e detectado.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FullPath
    )

    $problems = New-Object System.Collections.Generic.List[string]

    $reservedNames = @(
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
    )
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    if ($reservedNames -contains $baseName.ToUpperInvariant()) {
        $problems.Add("Nome reservado do Windows: '$Name'.")
    }

    $invalidChars = New-Object System.Collections.Generic.List[char]
    foreach ($ch in [char[]]'<>:"|?*') { $invalidChars.Add($ch) }
    for ($code = 0; $code -lt 32; $code++) { $invalidChars.Add([char]$code) }

    $foundInvalid = @($Name.ToCharArray() | Where-Object { $invalidChars.Contains($_) })
    if ($foundInvalid.Count -gt 0) {
        $problems.Add("Nome contem caractere invalido: '$Name'.")
    }

    if ($Name.EndsWith('.') -or $Name.EndsWith(' ')) {
        $problems.Add("Nome termina em ponto ou espaco: '$Name'.")
    }

    if ($FullPath.Length -gt 259) {
        $problems.Add("Caminho completo excede 259 caracteres ($($FullPath.Length)).")
    }

    return @($problems)
}
