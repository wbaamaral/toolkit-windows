function Test-SshdConfigSyntax {
    <#
    .SYNOPSIS
        Valida um sshd_config com 'sshd -t -f <arquivo>'.

    .OUTPUTS
        PSCustomObject com Available (sshd.exe encontrado), Valid e Output.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $sshd = $null
    $candidate = if ($env:windir) { Join-Path $env:windir 'System32\OpenSSH\sshd.exe' } else { $null }
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        $sshd = $candidate
    }
    else {
        $command = Get-Command -Name 'sshd.exe' -CommandType Application -ErrorAction Ignore | Select-Object -First 1
        if ($command) { $sshd = $command.Source }
    }

    if (-not $sshd) {
        return [pscustomobject]@{ Available = $false; Valid = $false; Output = 'sshd.exe nao encontrado.' }
    }

    $output = & $sshd -t -f $Path 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        Available = $true
        Valid     = ($exitCode -eq 0)
        Output    = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}
