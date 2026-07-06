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

    $escapeValue = { param($Value) [System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$Value) }

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("& '{0}'" -f (& $escapeValue $ScriptPath))

    foreach ($kv in $BoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value.IsPresent) { $parts.Add("-$($kv.Key)") }
        }
        elseif ($kv.Value -is [System.Collections.IEnumerable] -and $kv.Value -isnot [string]) {
            $values = @($kv.Value | ForEach-Object { "'{0}'" -f (& $escapeValue $_) }) -join ','
            if ($values) { $parts.Add("-$($kv.Key) $values") }
        }
        else {
            $parts.Add("-$($kv.Key) '{0}'" -f (& $escapeValue $kv.Value))
        }
    }

    return ($parts -join ' ')
}
