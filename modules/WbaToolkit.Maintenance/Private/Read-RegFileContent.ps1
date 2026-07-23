function Read-RegFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $conteudo = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $conteudo = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $conteudo = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    else {
        $utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)
        try {
            $conteudo = $utf8Strict.GetString($bytes)
        }
        catch {
            $conteudo = [System.Text.Encoding]::Default.GetString($bytes)
        }
    }

    if ([string]::IsNullOrWhiteSpace($conteudo)) {
        throw "Arquivo .reg vazio ou sem conteudo textual valido: $Path"
    }

    return $conteudo
}
