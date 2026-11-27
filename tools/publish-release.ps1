#requires -version 5.1
<#
.SYNOPSIS
    Publica releases sincronizadas no GitHub e no Codeberg (codebase) e no Gitea local (especificações).

.DESCRIPTION
    Versão Windows (PowerShell 5.1+) de tools/publish-release.sh, publicando o codebase
    em dois espelhos públicos: GitHub e Codeberg.

    Fluxo:
      1. Valida tokens, dependências e diretórios.
      2. Executa o pré-voo anti-LFS (equivalente a tools/release-check.sh).
      3. Cria as tags anotadas (ou reaproveita a tag se ela já aponta para o HEAD).
      4. Envia main + tag do codebase para cada espelho e do spec para o Gitea.
      5. Cria as releases via API (GitHub, Codeberg e Gitea).
      6. Opcionalmente atualiza a descrição do repositório em cada espelho.

    A identidade git do repositório NÃO é alterada: as tags usam o user.name /
    user.email já configurados localmente.

.PARAMETER CodeVersion
    Tag do codebase. Padrão: versão do primeiro título do RELEASE-NOTES.md.

.PARAMETER SpecVersion
    Tag do repositório de especificações. Obrigatória, a menos que -SkipSpec.

.PARAMETER Target
    Espelhos do codebase: GitHub, Codeberg ou ambos (padrão).

.PARAMETER SpecNotesPath
    Arquivo Markdown com o corpo da release do spec.
    Padrão: <SpecDir>\RELEASE-NOTES.md; se ausente, gera um corpo mínimo.

.PARAMETER Description
    Nova descrição do repositório nos espelhos. Se omitida, a descrição não é alterada.

.PARAMETER SkipSpec
    Publica somente o codebase.

.PARAMETER DryRun
    Mostra o que seria feito, sem criar tags, enviar commits ou chamar APIs.

.PARAMETER Force
    Não pede confirmação interativa.

.EXAMPLE
    .\tools\publish-release.ps1 -CodeVersion v2.0.4 -SkipSpec -DryRun

.EXAMPLE
    .\tools\publish-release.ps1 -CodeVersion v2.0.4 -SpecVersion v1.3.0 -Target Codeberg

.NOTES
    Variáveis de ambiente:
      GITHUB_TOKEN    — token GitHub (fine-grained: Contents read/write; Administration
                        read/write só se usar -Description). Se ausente, usa `gh auth token`.
      CODEBERG_TOKEN  — token Codeberg com escopo write:repository.
      GITEA_TOKEN     — token Gitea com escopo write:repository (dispensado com -SkipSpec).
      GITEA_BASE_URL  — padrão http://192.168.5.235:3000
#>
[CmdletBinding()]
param(
    [string]$CodeVersion,
    [string]$SpecVersion,
    [ValidateSet('GitHub', 'Codeberg')]
    [string[]]$Target = @('GitHub', 'Codeberg'),
    [string]$CodeDir,
    [string]$SpecDir,
    [string]$SpecNotesPath,
    [string]$Description,
    [string]$GitHubRepository = 'wbaamaral/toolkit-windows',
    [string]$GitHubRemote = 'github',
    [string]$CodebergRepository = 'wbaamaral/wba-windows-toolkit',
    [string]$CodebergRemote = 'codeberg',
    [string]$GiteaRepository = 'wbaamaral/spec-win-toolkit',
    [string]$GiteaRemote = 'origin',
    [string]$GiteaBaseUrl,
    [switch]$SkipSpec,
    [switch]$DryRun,
    [switch]$Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Padrões
# ---------------------------------------------------------------------------
if (-not $CodeDir) { $CodeDir = Split-Path -Parent $PSScriptRoot }
if (-not $SpecDir) { $SpecDir = Join-Path $CodeDir 'spec' }
if (-not $GiteaBaseUrl) {
    $GiteaBaseUrl = if ($env:GITEA_BASE_URL) { $env:GITEA_BASE_URL } else { 'http://192.168.5.235:3000' }
}
$GiteaBaseUrl = $GiteaBaseUrl.TrimEnd('/')
$Target = @($Target | Select-Object -Unique)

# PS 5.1 não habilita TLS 1.2 por padrão.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------
function Write-Step([string]$Message) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Message) }
function Write-Info([string]$Message) { Write-Host "  -> $Message" }
function Write-Warn([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }
function Stop-Release([string]$Message) { Write-Host "Erro: $Message" -ForegroundColor Red; exit 1 }

function Invoke-Git {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Arguments)
    # No PS 5.1, stderr de executável nativo vira erro fatal sob 'Stop' (o git push escreve progresso em stderr).
    $ErrorActionPreference = 'Continue'
    $output = & git -C $Repo @Arguments 2>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0) {
        Stop-Release ("git {0} falhou em {1}:`n{2}" -f ($Arguments -join ' '), $Repo, ($output | Out-String).Trim())
    }
    return $output
}

# Executa uma alteração (git) respeitando -DryRun.
function Invoke-Change {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory, ValueFromRemainingArguments)][string[]]$Arguments)
    if ($DryRun) { Write-Host "  [dry-run] git -C $Repo $($Arguments -join ' ')"; return }
    Invoke-Git -Repo $Repo @Arguments | Out-Null
}

# Chamada HTTP compatível com PS 5.1 e 7.x; devolve status e corpo sem lançar exceção.
function Invoke-ForgeApi {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][hashtable]$Body
    )
    # Bytes UTF-8 explícitos: o PS 5.1 codifica corpo string em ISO-8859-1.
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 5 -Compress))
    try {
        $resp = Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers -Body $bytes `
            -ContentType 'application/json; charset=utf-8' -UseBasicParsing
        return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $resp.Content }
    } catch {
        $status = 0
        $content = $_.Exception.Message
        $response = $_.Exception.Response
        if ($null -ne $response) {
            $status = [int]$response.StatusCode
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $content = $_.ErrorDetails.Message
            } elseif ($response -is [Net.HttpWebResponse]) {
                $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
                $content = $reader.ReadToEnd()
                $reader.Dispose()
            }
        }
        return [pscustomobject]@{ Status = $status; Body = $content }
    }
}

function Get-HtmlUrl([string]$Json) {
    try { return ($Json | ConvertFrom-Json).html_url } catch { return '' }
}

# ---------------------------------------------------------------------------
# Destinos
# ---------------------------------------------------------------------------
function Resolve-GitHubToken {
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    $ErrorActionPreference = 'Continue'
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $token = & gh auth token 2>$null
        if ($LASTEXITCODE -eq 0 -and $token) { return ($token | Out-String).Trim() }
    }
    return $null
}

# Cada espelho do codebase. Codeberg usa a API do Forgejo (compatível com Gitea).
function Get-MirrorDefinition([string]$Name) {
    switch ($Name) {
        'GitHub' {
            $token = Resolve-GitHubToken
            [pscustomobject]@{
                Name        = 'GitHub'
                Remote      = $GitHubRemote
                RemoteUrl   = "git@github.com:$GitHubRepository.git"
                Api         = "https://api.github.com/repos/$GitHubRepository"
                WebUrl      = "https://github.com/$GitHubRepository"
                TokenName   = 'GITHUB_TOKEN'
                Token       = $token
                Headers     = @{
                    Authorization          = "Bearer $token"
                    Accept                 = 'application/vnd.github+json'
                    'X-GitHub-Api-Version' = '2022-11-28'
                    'User-Agent'           = 'wba-toolkit-release'
                }
                TokenHelp   = 'GitHub -> Settings -> Developer settings -> Personal access tokens (Contents: read/write), ou: gh auth login'
            }
        }
        'Codeberg' {
            [pscustomobject]@{
                Name        = 'Codeberg'
                Remote      = $CodebergRemote
                RemoteUrl   = "git@codeberg.org:$CodebergRepository.git"
                Api         = "https://codeberg.org/api/v1/repos/$CodebergRepository"
                WebUrl      = "https://codeberg.org/$CodebergRepository"
                TokenName   = 'CODEBERG_TOKEN'
                Token       = $env:CODEBERG_TOKEN
                Headers     = @{ Authorization = "token $env:CODEBERG_TOKEN"; Accept = 'application/json' }
                TokenHelp   = 'Codeberg -> Settings -> Applications -> Generate Token (escopo: write:repository)'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Validações
# ---------------------------------------------------------------------------
function Test-Environment {
    foreach ($dep in 'git', 'git-lfs') {
        if (-not (Get-Command $dep -ErrorAction SilentlyContinue)) { Stop-Release "dependência ausente: $dep" }
    }

    $missing = @()
    $help = @()
    foreach ($mirror in $script:Mirrors) {
        if (-not $mirror.Token) { $missing += $mirror.TokenName; $help += "  $($mirror.TokenHelp)" }
    }
    if (-not $SkipSpec -and -not $env:GITEA_TOKEN) {
        $missing += 'GITEA_TOKEN'
        $help += '  Gitea -> Settings -> Applications -> Manage Access Tokens (escopo: write:repository)'
    }
    if ($missing.Count -gt 0 -and -not $DryRun) {
        Write-Host "Erro crítico: variáveis de ambiente não definidas: $($missing -join ', ')" -ForegroundColor Red
        Write-Host ''
        Write-Host 'Definir antes de executar:'
        foreach ($v in $missing) { Write-Host "  `$env:$v = '<seu-token>'" }
        Write-Host ''
        Write-Host 'Gerar tokens em:'
        $help | ForEach-Object { Write-Host $_ }
        exit 1
    }
    foreach ($v in $missing) { Write-Warn "$v ausente (tolerado em -DryRun)" }
}

function Test-Directory {
    if (-not (Test-Path -LiteralPath (Join-Path $CodeDir '.git'))) { Stop-Release "CodeDir não é um repositório git: $CodeDir" }
    if (-not (Test-Path -LiteralPath (Join-Path $CodeDir 'RELEASE-NOTES.md') -PathType Leaf)) { Stop-Release "RELEASE-NOTES.md não encontrado em $CodeDir" }
    if (-not $SkipSpec -and -not (Test-Path -LiteralPath (Join-Path $SpecDir '.git'))) { Stop-Release "SpecDir não é um repositório git: $SpecDir" }
}

function Resolve-Version {
    if (-not $script:CodeVersion) {
        $firstHeading = Get-Content -LiteralPath (Join-Path $CodeDir 'RELEASE-NOTES.md') -Encoding UTF8 |
            Where-Object { $_ -match '^#\s' } | Select-Object -First 1
        if ($firstHeading -match '(v\d+\.\d+\.\d+)') { $script:CodeVersion = $Matches[1] }
        else { Stop-Release 'não foi possível deduzir a versão do RELEASE-NOTES.md; informe -CodeVersion' }
    }
    if (-not $SkipSpec -and -not $script:SpecVersion) { Stop-Release 'informe -SpecVersion (ou use -SkipSpec)' }
}

# Equivalente PowerShell de tools/release-check.sh (pré-voo anti-LFS).
function Test-NoLfsPointer {
    Write-Step "Executando validação anti-LFS em $CodeDir"
    $ErrorActionPreference = 'Continue'
    $files = @(& git -C $CodeDir lfs ls-files --name-only 2>$null | Where-Object { $_ } | Sort-Object -Unique)
    if ($LASTEXITCODE -ne 0) { Stop-Release 'git lfs ls-files falhou' }
    if ($files.Count -eq 0) { Write-Info 'nenhum arquivo rastreado por Git LFS encontrado'; return }

    foreach ($relative in $files) {
        $path = Join-Path $CodeDir $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-Release "arquivo LFS ausente no working tree: $relative" }

        $stream = [IO.File]::OpenRead($path)
        try {
            $head = New-Object byte[] 64
            $read = $stream.Read($head, 0, $head.Length)
        } finally { $stream.Dispose() }
        $text = [Text.Encoding]::ASCII.GetString($head, 0, $read)

        if ($text.StartsWith('version https://git-lfs.github.com/spec/v1')) { Stop-Release "arquivo ainda é um ponteiro Git LFS: $relative" }
        if ($relative -like '*.pdf' -and -not $text.StartsWith('%PDF')) { Stop-Release "arquivo PDF inválido ou não resolvido como PDF real: $relative" }
    }
    Write-Info "arquivos LFS resolvidos e validados: $($files.Count)"
    Write-Host ''
}

# Garante o remoto de cada espelho no repositório do codebase.
function Confirm-MirrorRemote($Mirror) {
    $ErrorActionPreference = 'Continue'
    $current = & git -C $CodeDir remote get-url $Mirror.Remote 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Step "Remoto '$($Mirror.Remote)' ausente; adicionando $($Mirror.RemoteUrl)"
        Invoke-Change $CodeDir remote add $Mirror.Remote $Mirror.RemoteUrl
    } elseif ($current -ne $Mirror.RemoteUrl) {
        Stop-Release "remoto '$($Mirror.Remote)' aponta para $current (esperado $($Mirror.RemoteUrl))."
    }
}

# Retorna $true se a tag deve ser criada, $false se já existe no HEAD (reaproveitada).
function Test-TagState([string]$Repo, [string]$Tag, [string]$Label) {
    $existing = & git -C $Repo tag --list $Tag
    if (-not $existing) { return $true }
    $tagCommit = (Invoke-Git $Repo rev-parse "$Tag^{commit}" | Out-String).Trim()
    $headCommit = (Invoke-Git $Repo rev-parse HEAD | Out-String).Trim()
    if ($tagCommit -ne $headCommit) {
        Stop-Release "tag $Tag já existe no $Label e não aponta para o HEAD. Use outra versão ou ajuste a tag localmente."
    }
    Write-Info "tag $Tag já existe no HEAD do $Label; será reaproveitada"
    return $false
}

# ---------------------------------------------------------------------------
# Operações git
# ---------------------------------------------------------------------------
function New-ReleaseTag([string]$Repo, [string]$Tag, [string]$Summary) {
    $commit = (Invoke-Git $Repo rev-parse --short HEAD | Out-String).Trim()
    Write-Step "Criando tag anotada $Tag em $commit ($Repo)"
    # Opções longas: "-a"/"-m" seriam interpretados como parâmetros do PowerShell.
    Invoke-Change $Repo tag --annotate $Tag "--message=Release $Tag — $Summary ($commit)"
}

function Push-Release([string]$Repo, [string]$Remote, [string]$Tag, [string]$Label) {
    Write-Step "Enviando main e $Tag do $Label para '$Remote'..."
    Invoke-Change $Repo push $Remote main
    Invoke-Change $Repo push $Remote "refs/tags/$Tag"
    Write-Info "$Label sincronizado com '$Remote'."
}

# ---------------------------------------------------------------------------
# APIs
# ---------------------------------------------------------------------------
# Cria uma release; GitHub responde 422 e Gitea/Forgejo 409 quando ela já existe.
function New-ForgeRelease {
    param([string]$Name, [string]$Api, [hashtable]$Headers, [string]$Tag, [string]$Title, [string]$Body)
    Write-Step "Criando release $Tag no $Name..."
    $uri = "$Api/releases"
    $payload = @{ tag_name = $Tag; target_commitish = 'main'; name = $Title; body = $Body; draft = $false; prerelease = $false }
    if ($DryRun) { Write-Host "  [dry-run] POST $uri | $Tag | $Title"; return }

    $r = Invoke-ForgeApi -Method Post -Uri $uri -Headers $Headers -Body $payload
    if ($r.Status -eq 201) {
        Write-Info "Release $Name criada."
        $url = Get-HtmlUrl $r.Body; if ($url) { Write-Info "URL: $url" }
    } elseif ($r.Status -eq 409 -or ($r.Status -eq 422 -and $r.Body -match 'already_exists')) {
        Write-Warn "release $Tag já existe no $Name — ignorada"
    } else {
        Stop-Release "HTTP $($r.Status) ao criar release no ${Name}:`n$($r.Body)"
    }
}

function Update-MirrorDescription($Mirror) {
    if (-not $Description) { return }
    Write-Step "Atualizando descrição do repositório no $($Mirror.Name)..."
    if ($DryRun) { Write-Host "  [dry-run] PATCH $($Mirror.Api) | description: $Description"; return }

    $r = Invoke-ForgeApi -Method Patch -Uri $Mirror.Api -Headers $Mirror.Headers -Body @{ description = $Description }
    if ($r.Status -eq 200) { Write-Info "Descrição do $($Mirror.Name) atualizada." }
    else { Write-Warn "não foi possível atualizar a descrição no $($Mirror.Name) (HTTP $($r.Status)). Verificar permissões do token." }
}

function Get-SpecReleaseBody {
    $notes = if ($SpecNotesPath) { $SpecNotesPath } else { Join-Path $SpecDir 'RELEASE-NOTES.md' }
    if (Test-Path -LiteralPath $notes -PathType Leaf) {
        return Get-Content -LiteralPath $notes -Raw -Encoding UTF8
    }
    if ($SpecNotesPath) { Stop-Release "SpecNotesPath não encontrado: $SpecNotesPath" }

    Write-Warn 'sem RELEASE-NOTES.md no spec; usando corpo mínimo'
    $commit = (Invoke-Git $SpecDir rev-parse --short HEAD | Out-String).Trim()
    return @"
# WBA Windows Toolkit — Especificações $SpecVersion

> **$SpecVersion** · Repositório de governança e especificações formais do wba-windows-toolkit
>
> Codebase correspondente: **$CodeVersion**

---

_$(Get-Date -Format 'yyyy-MM-dd') · ``$commit`` · Especificações do wba-windows-toolkit_
"@
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$script:Mirrors = @($Target | ForEach-Object { Get-MirrorDefinition $_ })

Test-Environment
Test-Directory
Resolve-Version
Test-NoLfsPointer
foreach ($mirror in $script:Mirrors) { Confirm-MirrorRemote $mirror }

$createCodeTag = Test-TagState $CodeDir $CodeVersion 'codebase'
$createSpecTag = if ($SkipSpec) { $false } else { Test-TagState $SpecDir $SpecVersion 'spec' }

Write-Host ''
Write-Host '┌─────────────────────────────────────────────────────────'
Write-Host '│  WBA Windows Toolkit — Release Sincronizada'
Write-Host '├─────────────────────────────────────────────────────────'
Write-Host ('│  {0,-24} {1}' -f 'Codebase:', $CodeVersion)
foreach ($mirror in $script:Mirrors) {
    Write-Host ('│  {0,-24} {1}' -f "  $($mirror.Name):", "$($mirror.Remote) ($($mirror.RemoteUrl))")
}
if (-not $SkipSpec) {
    Write-Host ('│  {0,-24} {1}' -f 'Spec (Gitea local):', $SpecVersion)
    Write-Host ('│  {0,-24} {1}' -f 'Gitea endpoint:', $GiteaBaseUrl)
    Write-Host ('│  {0,-24} {1}' -f 'Spec dir:', $SpecDir)
}
Write-Host ('│  {0,-24} {1}' -f 'Code dir:', $CodeDir)
if ($DryRun) { Write-Host ('│  {0,-24} {1}' -f 'Modo:', 'DRY-RUN (nenhuma alteração será feita)') }
Write-Host '└─────────────────────────────────────────────────────────'
Write-Host ''

if (-not $DryRun -and -not $Force) {
    $confirm = Read-Host 'Confirmar publicação? [s/N]'
    if ($confirm -notmatch '^[sS]$') { Write-Host 'Cancelado.'; exit 0 }
    Write-Host ''
}

Write-Step 'Iniciando processo de release...'
Write-Host ''

if ($createCodeTag) { New-ReleaseTag $CodeDir $CodeVersion "publicação em $($Target -join ' e ')" }
if ($createSpecTag) { New-ReleaseTag $SpecDir $SpecVersion 'especificações sincronizadas' }
Write-Host ''

foreach ($mirror in $script:Mirrors) { Push-Release $CodeDir $mirror.Remote $CodeVersion 'codebase' }
if (-not $SkipSpec) { Push-Release $SpecDir $GiteaRemote $SpecVersion 'spec' }
Write-Host ''

$codeNotes = Get-Content -LiteralPath (Join-Path $CodeDir 'RELEASE-NOTES.md') -Raw -Encoding UTF8
foreach ($mirror in $script:Mirrors) {
    New-ForgeRelease -Name $mirror.Name -Api $mirror.Api -Headers $mirror.Headers `
        -Tag $CodeVersion -Title "WBA Windows Toolkit $CodeVersion" -Body $codeNotes
}
if (-not $SkipSpec) {
    New-ForgeRelease -Name 'Gitea' -Api "$GiteaBaseUrl/api/v1/repos/$GiteaRepository" `
        -Headers @{ Authorization = "token $env:GITEA_TOKEN"; Accept = 'application/json' } `
        -Tag $SpecVersion -Title "WBA Windows Toolkit — Especificações $SpecVersion" -Body (Get-SpecReleaseBody)
}
foreach ($mirror in $script:Mirrors) { Update-MirrorDescription $mirror }
Write-Host ''

Write-Step 'Processo concluído.'
Write-Host ''
foreach ($mirror in $script:Mirrors) { Write-Host ("  {0,-9} {1}/releases/tag/{2}" -f "$($mirror.Name):", $mirror.WebUrl, $CodeVersion) }
if (-not $SkipSpec) { Write-Host "  Spec:     $GiteaBaseUrl/$GiteaRepository/releases/tag/$SpecVersion" }
Write-Host ''
