function ConvertFrom-MarkdownSimple {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Markdown
    )

    function ConvertFrom-MarkdownInline {
        param([string]$Text)
        $t = $Text -replace '&', '&amp;'
        $t = $t  -replace '<', '&lt;'
        $t = $t  -replace '>', '&gt;'
        $t = $t  -replace '"', '&quot;'
        $t = [regex]::Replace($t, '`([^`]+)`', '<code>$1</code>')
        $t = [regex]::Replace($t, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
        $t = [regex]::Replace($t, '__([^_]+)__',    '<strong>$1</strong>')
        $t = [regex]::Replace($t, '\*([^*\n]+)\*',  '<em>$1</em>')
        $t = [regex]::Replace($t, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
        $t
    }

    $lines = $Markdown -split '\r?\n'
    $output = [System.Text.StringBuilder]::new()
    $state = 'Normal'
    $paragraphLines = New-Object 'System.Collections.Generic.List[string]'
    $tableHeaderEmitted = $false

    $flushParagraph = {
        if ($paragraphLines.Count -gt 0) {
            $text = ($paragraphLines -join ' ').Trim()
            if ($text) {
                $null = $output.AppendLine("<p>$text</p>")
            }
            $paragraphLines.Clear()
        }
    }

    foreach ($rawLine in $lines) {
        $line = $rawLine.TrimEnd()

        # ---- Estado FencedCode ----
        if ($state -eq 'FencedCode') {
            if ($line -match '^\s*```') {
                $null = $output.AppendLine('</code></pre>')
                $state = 'Normal'
            }
            else {
                $escaped = $line -replace '&', '&amp;'
                $escaped = $escaped -replace '<', '&lt;'
                $escaped = $escaped -replace '>', '&gt;'
                $null = $output.AppendLine($escaped)
            }
            continue
        }

        # ---- Fechar lista se a linha não é item ----
        if ($state -eq 'List' -and $line -notmatch '^\s*-\s') {
            $null = $output.AppendLine('</ul>')
            $state = 'Normal'
        }

        # ---- Fechar tabela se a linha não é linha de tabela ----
        if ($state -eq 'Table' -and $line -notmatch '^\|') {
            $null = $output.AppendLine('</tbody></table>')
            $state = 'Normal'
            $tableHeaderEmitted = $false
        }

        # ---- Linha em branco ----
        if ([string]::IsNullOrWhiteSpace($line)) {
            & $flushParagraph
            continue
        }

        # ---- Abertura de fenced code block ----
        if ($line -match '^\s*```') {
            & $flushParagraph
            $null = $output.AppendLine('<pre><code>')
            $state = 'FencedCode'
            continue
        }

        # ---- Headings ----
        if ($line -match '^(#{1,6})\s+(.+)$') {
            & $flushParagraph
            $level = $Matches[1].Length
            $text = ConvertFrom-MarkdownInline -Text $Matches[2].Trim()
            $null = $output.AppendLine("<h$level>$text</h$level>")
            continue
        }

        # ---- Separador de tabela |---|---| ----
        if ($line -match '^\|[-\|: ]+\|$') {
            # Descartado — header já foi emitido
            $tableHeaderEmitted = $true
            continue
        }

        # ---- Linha de tabela ----
        if ($line -match '^\|.+\|$') {
            & $flushParagraph
            $cells = @($line -split '\|' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() })

            if ($state -ne 'Table') {
                # Primeira linha com | → header
                $null = $output.AppendLine('<table>')
                $null = $output.AppendLine('<thead><tr>')
                foreach ($cell in $cells) {
                    $null = $output.AppendLine("<th>$(ConvertFrom-MarkdownInline -Text $cell)</th>")
                }
                $null = $output.AppendLine('</tr></thead>')
                $null = $output.AppendLine('<tbody>')
                $state = 'Table'
                $tableHeaderEmitted = $false
            }
            elseif ($tableHeaderEmitted) {
                # Linha de dados após o separador
                $null = $output.AppendLine('<tr>')
                foreach ($cell in $cells) {
                    $null = $output.AppendLine("<td>$(ConvertFrom-MarkdownInline -Text $cell)</td>")
                }
                $null = $output.AppendLine('</tr>')
            }
            continue
        }

        # ---- Lista não-ordenada ----
        if ($line -match '^\s*-\s+(.+)$') {
            & $flushParagraph
            if ($state -ne 'List') {
                $null = $output.AppendLine('<ul>')
                $state = 'List'
            }
            $item = ConvertFrom-MarkdownInline -Text $Matches[1].Trim()
            $null = $output.AppendLine("<li>$item</li>")
            continue
        }

        # ---- Parágrafo (texto comum) ----
        $paragraphLines.Add((ConvertFrom-MarkdownInline -Text $line))
    }

    # ---- Flush final ----
    & $flushParagraph
    if ($state -eq 'List') {
        $null = $output.AppendLine('</ul>')
    }
    if ($state -eq 'Table') {
        $null = $output.AppendLine('</tbody></table>')
    }
    if ($state -eq 'FencedCode') {
        $null = $output.AppendLine('</code></pre>')
    }

    $output.ToString()
}
