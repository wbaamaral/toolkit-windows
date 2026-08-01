function Get-LicenseHardwareContext {
    [CmdletBinding()]
    param(
        [string]$BaselinePath
    )

    $system = @()
    $board = @()
    $bios = @()
    try { $system = @(Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop | Select-Object -First 1) }
    catch { Write-Verbose "Nao foi possivel consultar o produto do sistema: $($_.Exception.Message)" }
    try { $board = @(Get-CimInstance -ClassName Win32_BaseBoard -ErrorAction Stop | Select-Object -First 1) }
    catch { Write-Verbose "Nao foi possivel consultar a placa mae: $($_.Exception.Message)" }
    try { $bios = @(Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop | Select-Object -First 1) }
    catch { Write-Verbose "Nao foi possivel consultar a BIOS: $($_.Exception.Message)" }
    $uuid = [string]$system.UUID
    $boardSerial = [string]$board.SerialNumber
    $biosSerial = [string]$bios.SerialNumber
    $material = "$uuid|$boardSerial|$biosSerial"
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($material)
        $hwid = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }

    $baseline = $null
    if ($BaselinePath -and (Test-Path -LiteralPath $BaselinePath -PathType Leaf)) {
        try { $baseline = (Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json).Hwid } catch { Write-Verbose "Baseline HWID inválido: $($_.Exception.Message)" }
    }
    [pscustomobject]@{
        HwidAtual = $hwid; HwidBaseline = $baseline; HardwareAlterado = $(if ($null -eq $baseline) { $null } else { $hwid -ne [string]$baseline })
        PlacaMae = [pscustomobject]@{ Fabricante = $board.Manufacturer; Produto = $board.Product; Serial = $board.SerialNumber }
        Bios = [pscustomobject]@{ Fabricante = $bios.Manufacturer; Versao = $bios.SMBIOSBIOSVersion; Serial = $bios.SerialNumber }
        Uuid = $uuid; Sistema = [pscustomobject]@{ Fabricante = $system.Manufacturer; Modelo = $system.Name }
    }
}
