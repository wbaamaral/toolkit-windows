function Invoke-Slmgr {
    <#
    .SYNOPSIS
        Encapsula todas as chamadas oficiais a slmgr.vbs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 600)]
        [int]$TimeoutSeconds = 60
    )

    $slmgrPath = if ([string]::IsNullOrWhiteSpace($env:windir)) {
        'C:\Windows\System32\slmgr.vbs'
    }
    else {
        Join-Path $env:windir 'System32\slmgr.vbs'
    }
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'cscript.exe'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $quotedArgs = @('//nologo', $slmgrPath) + $ArgumentList |
        ForEach-Object { '"{0}"' -f ([string]$_ -replace '"', '\"') }
    $startInfo.Arguments = $quotedArgs -join ' '

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stdout = ''
    $stderr = ''
    try {
        if (-not $process.Start()) {
            throw 'Não foi possível iniciar cscript.exe.'
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            return [pscustomobject]@{
                ExitCode = 1460
                StdOut   = ''
                StdErr   = 'Timeout ao executar slmgr.vbs.'
                Lines    = @()
                TimedOut = $true
            }
        }
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $global:LASTEXITCODE = $process.ExitCode
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout.Trim()
            StdErr   = $stderr.Trim()
            Lines    = @($stdout -split "`r?`n" | Where-Object { $_ -ne '' })
            TimedOut = $false
        }
    }
    catch {
        $global:LASTEXITCODE = 127
        return [pscustomobject]@{
            ExitCode = 127
            StdOut   = $stdout.Trim()
            StdErr   = $_.Exception.Message
            Lines    = @($stdout -split "`r?`n" | Where-Object { $_ -ne '' })
            TimedOut = $false
        }
    }
    finally {
        $process.Dispose()
    }
}
