function Get-ReportLogoBase64 {
    <#
    .SYNOPSIS
        Retorna o logo do toolkit como data URI base64 para embutir em HTML.

    .DESCRIPTION
        Le o arquivo de logo do diretorio assets/images/ e converte para base64
        data URI, pronto para uso em atributo src de tag <img>.

        Quando nenhum logo e encontrado, retorna $null — o chamador deve exibir
        um placeholder ou omitir a imagem.

    .PARAMETER Size
        Tamanho do logo: 'header' (padrao, 40px), 'footer' (24px) ou 'icon' (32px).

    .PARAMETER LogoPath
        Caminho personalizado para o arquivo de logo. Quando nao informado,
        procura automaticamente em assets/images/logo.svg relativo a raiz do toolkit.

    .EXAMPLE
        $logo = Get-ReportLogoBase64
        if ($logo) { "<img src='$logo' class='report-logo'>" }

    .EXAMPLE
        $logo = Get-ReportLogoBase64 -Size 'footer' -LogoPath 'C:\custom\logo.svg'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('header', 'footer', 'icon')]
        [string]$Size = 'header',

        [Parameter(Mandatory = $false)]
        [string]$LogoPath
    )

    # Resolver caminho do logo
    if (-not $LogoPath) {
        # Procurar na estrutura padrao: assets/images/logo.svg
        $toolkitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $LogoPath = Join-Path $toolkitRoot 'assets\images\logo.svg'
    }

    if (-not (Test-Path -LiteralPath $LogoPath -PathType Leaf)) {
        Write-Debug "Logo nao encontrado: $LogoPath"
        return $null
    }

    # Validar extensao
    $ext = [System.IO.Path]::GetExtension($LogoPath).ToLower()
    if ($ext -notin @('.svg', '.png', '.jpg', '.jpeg')) {
        Write-Warning "Formato de logo nao suportado: $ext. Use SVG, PNG ou JPG."
        return $null
    }

    # Ler e converter para base64
    try {
        $bytes = [System.IO.File]::ReadAllBytes($LogoPath)
        $base64 = [Convert]::ToBase64String($bytes)

        # Mapear tipo MIME
        $mimeType = switch ($ext) {
            '.svg'  { 'image/svg+xml' }
            '.png'  { 'image/png' }
            '.jpg'  { 'image/jpeg' }
            '.jpeg' { 'image/jpeg' }
        }

        $dataUri = "data:$mimeType;base64,$base64"

        # Validar tamanho (max 50KB para SVG, 20KB para PNG/JPG)
        $maxBytes = if ($ext -eq '.svg') { 50 * 1024 } else { 20 * 1024 }
        if ($bytes.Length -gt $maxBytes) {
            Write-Warning "Logo excede o tamanho maximo ($([int]($maxBytes/1024))KB): $([int]($bytes.Length/1024))KB"
        }

        Write-Debug "Logo carregado: $LogoPath ($([int]($bytes.Length/1024))KB)"
        return $dataUri
    }
    catch {
        Write-Warning "Erro ao ler logo: $($_.Exception.Message)"
        return $null
    }
}
