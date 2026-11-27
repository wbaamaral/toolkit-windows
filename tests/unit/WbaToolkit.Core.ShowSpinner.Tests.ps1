#requires -version 5.1

# BCK-067: Show-Spinner esperava $job.HasExited, propriedade que nao existe em jobs do
# PowerShell; o laco nunca terminava e travava o limpar-windows.ps1 apos o SFC/DISM.
# Cada caso roda o Show-Spinner dentro de um job com tempo limite, para que uma regressao
# falhe o teste em vez de travar a suite.

BeforeAll {
    $script:spinnerPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\modules\WbaToolkit.Core\Public\Show-Spinner.ps1')).Path

    function Invoke-SpinnerProbe {
        param(
            [Parameter(Mandatory)][string]$Body,
            [int]$TimeoutSeconds = 60
        )
        $probe = Start-Job -ArgumentList $script:spinnerPath, $Body -ScriptBlock {
            param($SpinnerPath, $Body)
            . $SpinnerPath
            Show-Spinner -Message 'teste' -ScriptBlock ([scriptblock]::Create($Body))
        }
        try {
            $finished = Wait-Job -Job $probe -Timeout $TimeoutSeconds
            [pscustomobject]@{
                Returned = [bool]$finished
                Output   = if ($finished) { @(Receive-Job -Job $probe -ErrorAction SilentlyContinue) } else { @() }
            }
        } finally {
            Stop-Job -Job $probe -ErrorAction SilentlyContinue
            Remove-Job -Job $probe -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Show-Spinner (BCK-067)' {
    It 'Retorna quando o bloco termina e devolve a saida dele' {
        $result = Invoke-SpinnerProbe -Body "Start-Sleep -Milliseconds 300; 'FEITO'"
        $result.Returned | Should -BeTrue -Because 'o spinner precisa sair do laco quando o job termina'
        $result.Output | Should -Contain 'FEITO'
    }

    It 'Retorna mesmo quando o bloco falha' {
        $result = Invoke-SpinnerProbe -Body "throw 'falha simulada'"
        $result.Returned | Should -BeTrue -Because 'um job em estado Failed tambem encerra a espera'
    }

    It 'Nao depende de HasExited, que nao existe em jobs' {
        $content = Get-Content -LiteralPath $script:spinnerPath -Raw
        $content | Should -Not -Match '\$job\.HasExited'
    }
}
