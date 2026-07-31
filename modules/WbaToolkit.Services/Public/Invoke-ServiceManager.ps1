function Invoke-ServiceManager {
    <#
    .SYNOPSIS
        Wizard interativo para gerenciamento de servicos Windows.

    .DESCRIPTION
        Oferece um menu interativo para diagnosticar, listar, iniciar, parar,
        reiniciar e configurar servicos. Suporta busca por nome.

    .PARAMETER Acao
        Acao pre-definida: Diagnostico, Listar, Parar, Iniciar, Reiniciar,
        ConfigurarInicializacao, ConfigurarConta.

    .PARAMETER ServiceName
        Nome do servico para acoes diretas.

    .PARAMETER StartupType
        Novo tipo de inicializacao (para ConfigurarInicializacao).

    .PARAMETER Account
        Conta de logon (para ConfigurarConta).

    .PARAMETER Credential
        Credencial segura da conta (para ConfigurarConta).

    .OUTPUTS
        PSCustomObject com: Success, Message, ServiceName, Changes.

    .EXAMPLE
        Invoke-ServiceManager -Acao Diagnostico

    .EXAMPLE
        Invoke-ServiceManager -Acao Parar -ServiceName 'Spooler'
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Diagnostico', 'Listar', 'Parar', 'Iniciar', 'Reiniciar',
                     'ConfigurarInicializacao', 'ConfigurarConta')]
        [string]$Acao = 'Diagnostico',

        [string]$ServiceName,

        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType,

        [string]$Account,

        [pscredential]$Credential
    )

    switch ($Acao) {
        'Diagnostico' {
            $running = @(Get-WindowsServiceStatus -Status Running)
            $stopped = @(Get-WindowsServiceStatus -Status Stopped -StartType Automatic)
            $disabled = @(Get-WindowsServiceStatus -StartType Disabled)

            Write-Host ''
            Write-Host "Total de servicos em execucao: $($running.Count)" -ForegroundColor Green
            Write-Host "Servicos automaticos parados:  $($stopped.Count)" -ForegroundColor $(if ($stopped.Count -gt 0) { 'Yellow' } else { 'Green' })
            Write-Host "Servicos desabilitados:        $($disabled.Count)" -ForegroundColor DarkGray

            if ($stopped.Count -gt 0) {
                Write-Host ''
                Write-Host 'Servicos automaticos parados (candidatos a inicio):' -ForegroundColor Yellow
                foreach ($s in $stopped) {
                    Write-Host "  - $($s.Name) ($($s.DisplayName))" -ForegroundColor Yellow
                }
            }

            return [pscustomobject]@{
                Success         = $true
                Message         = "Diagnostico: $($running.Count) em execucao, $($stopped.Count) automaticos parados, $($disabled.Count) desabilitados."
                RunningCount    = $running.Count
                StoppedAuto     = @($stopped)
                DisabledCount   = $disabled.Count
            }
        }

        'Listar' {
            $all = @(Get-WindowsServiceStatus)
            return $all
        }

        'Parar' {
            if ([string]::IsNullOrWhiteSpace($ServiceName)) {
                return Format-ServiceResult -Success $false -Message 'Acao Parar requer -ServiceName.'
            }
            return Stop-WindowsService -Name $ServiceName
        }

        'Iniciar' {
            if ([string]::IsNullOrWhiteSpace($ServiceName)) {
                return Format-ServiceResult -Success $false -Message 'Acao Iniciar requer -ServiceName.'
            }
            return Start-WindowsService -Name $ServiceName
        }

        'Reiniciar' {
            if ([string]::IsNullOrWhiteSpace($ServiceName)) {
                return Format-ServiceResult -Success $false -Message 'Acao Reiniciar requer -ServiceName.'
            }
            return Restart-WindowsService -Name $ServiceName
        }

        'ConfigurarInicializacao' {
            if ([string]::IsNullOrWhiteSpace($ServiceName)) {
                return Format-ServiceResult -Success $false -Message 'Acao ConfigurarInicializacao requer -ServiceName.'
            }
            if ([string]::IsNullOrWhiteSpace($StartupType)) {
                return Format-ServiceResult -Success $false -Message 'Acao ConfigurarInicializacao requer -StartupType.'
            }
            return Set-WindowsServiceStartup -Name $ServiceName -StartupType $StartupType
        }

        'ConfigurarConta' {
            if ([string]::IsNullOrWhiteSpace($ServiceName)) {
                return Format-ServiceResult -Success $false -Message 'Acao ConfigurarConta requer -ServiceName.'
            }
            if ([string]::IsNullOrWhiteSpace($Account)) {
                return Format-ServiceResult -Success $false -Message 'Acao ConfigurarConta requer -Account.'
            }
            $params = @{ Name = $ServiceName; Account = $Account }
            if ($Credential) { $params['Credential'] = $Credential }
            return Set-WindowsServiceAccount @params
        }
    }
}
