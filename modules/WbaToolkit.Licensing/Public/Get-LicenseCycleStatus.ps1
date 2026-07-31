function Get-LicenseCycleStatus {
    <#
    .SYNOPSIS
        Analisa o ciclo de licenciamento do Windows e retorna estado, dias
        restantes e recomendacoes.

    .DESCRIPTION
        Combina dados WMI (SoftwareLicensingProduct, SoftwareLicensingService)
        com slmgr.vbs para determinar o estado atual do ciclo de licenciamento:
        - Licensed: ativacao completa
        - GracePeriod: periodo de graça ativo (dias restantes)
        - GraceExpired: periodo de graça expirado
        - Notification: notificacoes de licenciamento ativas
        - NonGenuine: sistema marcado como nao genuino
        - Unknown: estado nao identificado

        Retorna dias restantes quando aplicavel e recomendacoes de acao.

    .OUTPUTS
        PSCustomObject com propriedades: State, StateCode, DaysRemaining,
        ExpirationDate, Channel, Recommendations[], Details.
    #>
    [CmdletBinding()]
    param()

    $product = Get-SoftwareLicensingProduct | Where-Object {
        $_.LicenseStatus -ne $null -and $_.LicenseStatus -gt 0
    } | Select-Object -First 1

    if (-not $product) {
        [pscustomobject]@{
            State           = 'NoProduct'
            StateCode      = -1
            DaysRemaining  = $null
            ExpirationDate = $null
            Channel        = 'Unknown'
            Recommendations = @('Nenhum produto de licenciamento encontrado no sistema.')
            Details         = 'Consulta SoftwareLicensingProduct nao retornou dados.'
        }
        return
    }

    $service = Get-SoftwareLicensingService | Select-Object -First 1
    $rawDli = Invoke-Slmgr -ArgumentList '/dli'
    $rawDlv = Invoke-Slmgr -ArgumentList '/dlv'
    $rawXpr = Invoke-Slmgr -ArgumentList '/xpr'

    $licenseInfo = ConvertTo-LicenseInfoObject `
        -Product $product `
        -Service $service `
        -SlmgrDli $rawDli `
        -SlmgrDlv $rawDlv `
        -SlmgrXpr $rawXpr

    $statusCode = [int]$product.LicenseStatus
    $rearmCount = if ($service) { [int]$service.RemainingWindowsReArmCount } else { -1 }

    $state = switch ($statusCode) {
        1 { 'Licensed' }
        2 { 'GracePeriod' }
        3 { 'GraceExpired' }
        4 { 'NonGenuine' }
        5 { 'Notification' }
        6 { 'ExtendedGrace' }
        default { 'Unknown' }
    }

    $daysRemaining = $null
    $expirationDate = $null
    $recommendations = [System.Collections.Generic.List[string]]::new()

    $xprOutput = if ($rawXpr -and $rawXpr.Lines) { $rawXpr.Lines -join ' ' } else { '' }

    if ($xprOutput -match '(\d{1,2})/(\d{1,2})/(\d{4})') {
        try {
            $expirationDate = [datetime]::ParseExact(
                $Matches[0], 'M/d/yyyy',
                [System.Globalization.CultureInfo]::InvariantCulture)
            $daysRemaining = ($expirationDate - (Get-Date)).Days
        }
        catch { Write-Verbose "Falha ao parsear data de expiracao: $($_.Exception.Message)" }
    }
    elseif ($xprOutput -match '(\d+)\s+dias?\s+restante') {
        $daysRemaining = [int]$Matches[1]
        if ($daysRemaining -gt 0) {
            $expirationDate = (Get-Date).AddDays($daysRemaining)
        }
    }

    switch ($state) {
        'Licensed' {
            $recommendations.Add('Sistema ativado e licenciado. Nenhuma acao necessaria.')
            if ($channel -eq 'KMS') {
                $recommendations.Add('Ativacao KMS requer renovacao a cada 180 dias. Verifique conectividade com o servidor KMS periodicamente.')
            }
        }
        'GracePeriod' {
            if ($null -ne $daysRemaining -and $daysRemaining -le 3) {
                $recommendations.Add("URGENTE: $daysRemaining dia(s) restante(s) no periodo de grace. Ative o sistema imediatamente.")
            }
            elseif ($null -ne $daysRemaining -and $daysRemaining -le 7) {
                $recommendations.Add("ALERTA: $daysRemaining dias restantes no periodo de grace. Programe a ativacao.")
            }
            else {
                $recommendations.Add("Periodo de grace ativo. $daysRemaining dia(s) restante(s).")
            }
            $recommendations.Add('Use: -Ativar para ativacao online ou -InstalarChave <chave> para definir product key.')
            if ($rearmCount -gt 0) {
                $recommendations.Add("Rearm disponivel ($rearmCount vez(es) restante(s)) como ultimo recurso.")
            }
        }
        'GraceExpired' {
            $recommendations.Add('Periodo de grace expirado. O sistema exibira notificacoes e funcionalidade pode ser reduzida.')
            $recommendations.Add('Ative o sistema com -Ativar ou instale uma chave valida com -InstalarChave.')
            if ($rearmCount -gt 0) {
                $recommendations.Add("Rearm disponivel ($rearmCount vez(es)) para estender o grace period.")
            }
        }
        'Notification' {
            $recommendations.Add('Sistema com notificacoes de licenciamento ativas.')
            $recommendations.Add('Verifique se a licenca e genuina. Re-ativacao pode resolver.')
        }
        'NonGenuine' {
            $recommendations.Add('Sistema marcado como nao genuino. Licenciamento invalido detectado.')
            $recommendations.Add('Considere adquirir uma licenca valida e re-ativar o sistema.')
        }
    }

    [pscustomobject]@{
        State           = $state
        StateCode      = $statusCode
        DaysRemaining  = $daysRemaining
        ExpirationDate = $expirationDate
        Channel        = $licenseInfo.Licenca.Canal
        RearmCount     = $rearmCount
        Recommendations = $recommendations.ToArray()
        Details         = $licenseInfo
    }
}
