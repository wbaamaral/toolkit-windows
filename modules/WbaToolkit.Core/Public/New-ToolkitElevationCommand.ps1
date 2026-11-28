function New-ToolkitElevationCommand {
    <#
    .SYNOPSIS
        Monta a linha de comando PowerShell para relancar um script com elevacao.

    .DESCRIPTION
        Converte $PSBoundParameters do script chamador em uma string de comando
        segura para uso com 'powershell.exe -Command', preservando parametros
        com espacos, aspas e arrays (ex.: [string[]]$Drive) intactos no processo
        elevado. Usa -Command (nao -File) porque somente o parser da linguagem
        PowerShell reconstroi um array a partir de 'valor1','valor2' — passar
        array via -File colapsa os valores em um unico argumento.

    .PARAMETER ScriptPath
        Caminho do script a relancar (normalmente $PSCommandPath).

    .PARAMETER BoundParameters
        Dicionario de parametros do script chamador (normalmente $PSBoundParameters).

    .EXAMPLE
        $cmd = New-ToolkitElevationCommand -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command', $cmd) -Verb RunAs
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$BoundParameters
    )

    # WBA-DOCS: Category=Core; Related=Test-IsAdministrator; Manual=Relancamento elevado seguro para arrays/espacos

    # Os chamadores passam o comando por Start-Process, que junta -ArgumentList sem aspas. O powershell.exe
    # remonta o -Command a partir dos argumentos: tira aspas duplas, e tabulacoes, quebras de linha e espacos
    # repetidos viram um espaco so. Valores com esses caracteres vao em base64 e sao decodificados no processo
    # elevado; os demais seguem como literal entre aspas simples, legivel no log.
    $toLiteral = {
        param($Value)
        $text = [string]$Value
        if ($text -match '"|\s{2,}|[^\S ]') {
            $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($text))
            return "([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64')))"
        }
        return "'{0}'" -f [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($text)
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('& {0}' -f (& $toLiteral $ScriptPath))

    foreach ($kv in $BoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $parts.Add("-$($kv.Key)") }
        }
        elseif ($kv.Value -is [System.Collections.IEnumerable] -and $kv.Value -isnot [string]) {
            $values = @($kv.Value | ForEach-Object { & $toLiteral $_ }) -join ','
            if ($values) { $parts.Add("-$($kv.Key) $values") }
        }
        else {
            $parts.Add("-$($kv.Key) {0}" -f (& $toLiteral $kv.Value))
        }
    }

    return ($parts -join ' ')
}
