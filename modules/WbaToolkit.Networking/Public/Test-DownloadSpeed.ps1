function Test-DownloadSpeed {
    <#
    .SYNOPSIS
        Testa velocidade de download da internet.

    .DESCRIPTION
        Baixa um arquivo de teste e mede a velocidade de download em Mbps.

    .PARAMETER Url
        URL do arquivo de teste.

    .PARAMETER TimeoutSeconds
        Tempo limite para o download. Padrão: 15.

    .OUTPUTS
        PSCustomObject com SpeedMbps, TotalMB, DurationSeconds e Status.

    .EXAMPLE
        $result = Test-DownloadSpeed
    #>
    [CmdletBinding()]
    param(
        [string]$Url = 'https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb',
        [int]$TimeoutSeconds = 15
    )

    $result = [PSCustomObject]@{
        Url              = $Url
        SpeedMbps        = 0
        TotalMB          = 0
        DurationSeconds  = 0
        Status           = 'Erro'
        Message          = ''
    }

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Timeout = $TimeoutSeconds * 1000
        $request.ReadWriteTimeout = $TimeoutSeconds * 1000
        $request.UserAgent = 'WBA-Toolkit/1.0'

        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $buffer = New-Object byte[] 65536
        $bytesRead = 0
        $totalBytes = 0

        do {
            $bytesRead = $stream.Read($buffer, 0, $buffer.Length)
            $totalBytes += $bytesRead
        } while ($bytesRead -gt 0 -and $stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds)

        $stream.Close()
        $response.Close()
        $stopwatch.Stop()

        $totalMB = [math]::Round($totalBytes / 1MB, 2)
        $duration = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)

        if ($duration -gt 0) {
            $speedMbps = [math]::Round(($totalBytes * 8) / ($duration * 1000000), 2)
        }
        else {
            $speedMbps = 0
        }

        $result.SpeedMbps = $speedMbps
        $result.TotalMB = $totalMB
        $result.DurationSeconds = $duration
        $result.Status = 'OK'
        $result.Message = "Download: $totalMB MB em $duration s ($speedMbps Mbps)"
    }
    catch {
        $result.Status = 'Erro'
        $result.Message = "Falha no teste: $($_.Exception.Message)"
    }

    return $result
}
