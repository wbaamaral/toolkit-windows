<#
.SYNOPSIS
    Launcher principal do WBA Windows Toolkit.

.DESCRIPTION
    Exibe o catalogo operacional do MVP, oferece atalhos rapidos e encaminha a
    execução para os scripts padronizados da pasta scripts/.

.EXAMPLE
    .\xtudo.ps1

.EXAMPLE
    .\xtudo.ps1 limpar

.EXAMPLE
    .\xtudo.ps1 diagnosticar memoria
#>
#!/usr/bin/env pwsh
#requires -version 5.1

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Query
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$PSDefaultParameterValues['Out-File:Encoding']    = 'utf8'
$PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'

try { chcp 65001 | Out-Null } catch { }

$ScriptName = if ($MyInvocation.MyCommand.Name) {
    $MyInvocation.MyCommand.Name
}
else {
    Split-Path -Leaf $PSCommandPath
}

$ScriptPath = $PSCommandPath
$ScriptDir  = $PSScriptRoot
$ToolkitRoot = $ScriptDir

function New-XtudoCatalog {
    @(
        [pscustomobject]@{
            Id       = 'limpar-windows'
            Label    = 'Limpar Windows'
            Category = 'Limpeza'
            Path     = 'scripts/limpar-windows.ps1'
            Keywords = @('limpar', 'limpeza', 'cleanup', 'temp', 'cache', 'windows')
            Quick    = $true
        }
        [pscustomobject]@{
            Id       = 'diagnosticar-disco-100'
            Label    = 'Diagnosticar disco 100%'
            Category = 'Diagnóstico'
            Path     = 'scripts/diagnosticar-disco-100.ps1'
            Keywords = @('disco', '100', 'hd100', 'io', 'lentidao')
            Quick    = $true
        }
        [pscustomobject]@{
            Id       = 'diagnosticar-memoria'
            Label    = 'Diagnosticar memória'
            Category = 'Diagnóstico'
            Path     = 'scripts/diagnosticar-memoria.ps1'
            Keywords = @('memoria', 'ram', 'processos')
            Quick    = $true
        }
        [pscustomobject]@{
            Id       = 'diagnosticar-grafico'
            Label    = 'Diagnosticar gráfico'
            Category = 'Diagnóstico'
            Path     = 'scripts/diagnosticar-grafico.ps1'
            Keywords = @('grafico', 'video', 'gpu', 'tela preta', 'dwm')
            Quick    = $true
        }
        [pscustomobject]@{
            Id       = 'preparar-imagem-windows'
            Label    = 'Preparar imagem'
            Category = 'Imagem'
            Path     = 'scripts/preparar-imagem-windows.ps1'
            Keywords = @('imagem', 'preparar', 'sysprep', 'golden image', 'default profile')
            Quick    = $true
        }
    )
}

function Get-XtudoEntry {
    param(
        [string[]]$Tokens
    )

    $catalog = New-XtudoCatalog

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        return $catalog
    }

    $needle = ($Tokens -join ' ').Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($needle)) {
        return $catalog
    }

    $scored = foreach ($item in $catalog) {
        $score = 0
        $fields = @(
            $item.Id,
            $item.Label,
            $item.Category,
            $item.Path
        ) + @($item.Keywords)

        foreach ($field in $fields) {
            if ([string]::IsNullOrWhiteSpace($field)) { continue }
            $value = $field.ToString().ToLowerInvariant()
            if ($value -eq $needle) { $score += 100 }
            elseif ($value.Contains($needle)) { $score += 50 }
            else {
                foreach ($token in $Tokens) {
                    $t = $token.ToLowerInvariant()
                    if ($value -eq $t) { $score += 25 }
                    elseif ($value.Contains($t)) { $score += 10 }
                }
            }
        }

        [pscustomobject]@{
            Item  = $item
            Score = $score
        }
    }

    $scored |
        Where-Object { $_.Score -gt 0 } |
        Sort-Object Score -Descending |
        ForEach-Object { $_.Item }
}

function Show-XtudoBanner {
    Write-Host ''
    Write-Host 'Xtudo - WBA Windows Toolkit' -ForegroundColor Cyan
    Write-Host '1-5 executa, 0 sai, Enter lista.' -ForegroundColor DarkGray
    Write-Host ''
}

function Show-XtudoQuickActions {
    param([object[]]$Entries)

    $quick = @($Entries | Where-Object { $_.Quick })

    Write-Host 'Atalhos:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $quick.Count; $i++) {
        $n = $i + 1
        Write-Host ("  {0}. {1}" -f $n, $quick[$i].Label)
    }
    Write-Host ''

    return $quick
}

function Show-XtudoCatalog {
    param([object[]]$Entries)

    Write-Host 'Catalogo completo:' -ForegroundColor Cyan
    $groups = $Entries | Group-Object Category | Sort-Object Name

    foreach ($group in $groups) {
        Write-Host ("[{0}]" -f $group.Name) -ForegroundColor Yellow
        foreach ($item in $group.Group) {
            Write-Host ("  - {0} ({1})" -f $item.Label, $item.Id)
        }
    }
    Write-Host ''
}

function Invoke-XtudoScript {
    param([Parameter(Mandatory = $true)]$Entry)

    $target = Join-Path $ToolkitRoot $Entry.Path
    if (-not (Test-Path -LiteralPath $target)) {
        throw "Script nao encontrado: $target"
    }

    Write-Host ''
    Write-Host ("Executando: {0}" -f $Entry.Label) -ForegroundColor Green
    Write-Host ("Caminho:    {0}" -f $Entry.Path) -ForegroundColor DarkGray
    Write-Host ''

    & $target
}

function Select-XtudoEntry {
    param(
        [object[]]$Entries,
        [string[]]$Tokens
    )

    if ($Tokens -and $Tokens.Count -gt 0) {
        $joined = ($Tokens -join ' ').Trim()

        if ($joined -match '^[1-9][0-9]*$') {
            $idx = [int]$joined - 1
            $quick = @($Entries | Where-Object { $_.Quick })
            if ($idx -ge 0 -and $idx -lt $quick.Count) {
                return $quick[$idx]
            }
        }

        $matches = @(Get-XtudoEntry -Tokens $Tokens)
        if ($matches.Count -eq 1) {
            return $matches[0]
        }
        elseif ($matches.Count -gt 1) {
            Write-Host ''
            Write-Host 'Resultados encontrados:' -ForegroundColor Cyan
            for ($i = 0; $i -lt $matches.Count; $i++) {
                Write-Host ("  {0}. {1} [{2}] -> {3}" -f ($i + 1), $matches[$i].Label, $matches[$i].Category, $matches[$i].Path)
            }
            Write-Host ''
            $choice = Read-Host 'Escolha um numero ou 0 para cancelar'
            if ($choice -match '^(0|q|quit|sair)$') {
                return $null
            }
            if ($choice -match '^[1-9][0-9]*$') {
                $picked = [int]$choice - 1
                if ($picked -ge 0 -and $picked -lt $matches.Count) {
                    return $matches[$picked]
                }
            }
            return $null
        }
    }

    return $null
}

$catalog = New-XtudoCatalog

if ($Query.Count -gt 0) {
    $entry = Select-XtudoEntry -Entries $catalog -Tokens $Query
    if ($null -eq $entry) {
        Write-Host 'Nenhum resultado exato.' -ForegroundColor Yellow
        Show-XtudoCatalog -Entries $catalog
        exit 1
    }

    Invoke-XtudoScript -Entry $entry
    exit $LASTEXITCODE
}

while ($true) {
    Show-XtudoBanner
    $quick = Show-XtudoQuickActions -Entries $catalog

    $input = Read-Host 'Opcao, palavra-chave ou Enter'

    if ([string]::IsNullOrWhiteSpace($input)) {
        Show-XtudoCatalog -Entries $catalog
        continue
    }

    if ($input -match '^(0|q|quit|sair)$') {
        break
    }

    if ($input -match '^[1-9][0-9]*$') {
        $idx = [int]$input - 1
        if ($idx -ge 0 -and $idx -lt $quick.Count) {
            Invoke-XtudoScript -Entry $quick[$idx]
            break
        }
    }

    $entry = Select-XtudoEntry -Entries $catalog -Tokens @($input)
    if ($null -ne $entry) {
        Invoke-XtudoScript -Entry $entry
        break
    }

    Write-Host 'Nao encontrei correspondencia.' -ForegroundColor Yellow
}
