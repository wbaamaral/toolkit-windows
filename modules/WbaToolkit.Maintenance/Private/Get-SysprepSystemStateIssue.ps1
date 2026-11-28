function Get-SysprepSystemStateIssue {
    <#
    .SYNOPSIS
        Lista condicoes do sistema que fazem o sysprep /generalize falhar.

    .DESCRIPTION
        Verifica, sem alterar nada:

        - BitLocker ou criptografia de dispositivo no volume do sistema. O sysprep recusa
          com 0x80310039; em VM com vTPM (Windows 11) a criptografia de dispositivo costuma
          vir ligada, inclusive "aguardando ativacao".
        - Instalacao atualizada a partir de outra versao (chave HKLM\SYSTEM\Setup\Upgrade),
          que o sysprep recusa.
        - Reinicio pendente do servicing (CBS) ou do Windows Update.
        - Estado de generalizacao anterior incompleto (SysprepStatus\GeneralizationState
          diferente de 7). Generalizar de novo uma maquina clonada de imagem ja generalizada
          e suportado; so o estado incompleto e sinalizado.

        Usa chaves de registro e CIM, nunca saida de comando localizada (ADR 0034).

    .OUTPUTS
        PSCustomObject com Check, Severity (Error ou Warning) e Message, um por condicao.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $issues = New-Object 'System.Collections.Generic.List[object]'

    function Add-Issue {
        param([string]$Check, [string]$Severity, [string]$Message)
        $issues.Add([pscustomobject]@{ Check = $Check; Severity = $Severity; Message = $Message })
    }

    # BitLocker / criptografia de dispositivo no volume do sistema.
    $systemDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
    try {
        $volume = Get-CimInstance -Namespace 'root/cimv2/Security/MicrosoftVolumeEncryption' `
            -ClassName 'Win32_EncryptableVolume' -Filter "DriveLetter='$systemDrive'" -ErrorAction Stop |
            Select-Object -First 1
        if ($volume) {
            $conversion = $volume.PSObject.Properties['ConversionStatus']
            $protection = $volume.PSObject.Properties['ProtectionStatus']
            $conversionValue = if ($conversion -and $null -ne $conversion.Value) { [int]$conversion.Value } else { 0 }
            $protectionValue = if ($protection -and $null -ne $protection.Value) { [int]$protection.Value } else { 0 }
            # ConversionStatus 0 = totalmente descriptografado; ProtectionStatus 0 = protecao desligada.
            if ($conversionValue -ne 0 -or $protectionValue -ne 0) {
                Add-Issue -Check 'BitLocker' -Severity 'Error' -Message ("BitLocker ou criptografia de dispositivo ativa no volume $systemDrive " +
                    "(ConversionStatus=$conversionValue, ProtectionStatus=$protectionValue). O sysprep recusa generalizar " +
                    "(0x80310039). Desative com 'manage-bde -off $systemDrive' e aguarde a descriptografia terminar.")
            }
        }
    }
    catch {
        Add-Issue -Check 'BitLocker' -Severity 'Warning' -Message ("Nao foi possivel verificar o BitLocker do volume ${systemDrive}: " +
            "$($_.Exception.Message). Confira com 'manage-bde -status $systemDrive' antes do sysprep.")
    }

    # Instalacao atualizada a partir de outra versao do Windows.
    if (Test-Path -LiteralPath 'HKLM:\SYSTEM\Setup\Upgrade') {
        Add-Issue -Check 'Upgrade' -Severity 'Error' -Message ('Instalacao atualizada a partir de outra versao do Windows ' +
            '(chave HKLM\SYSTEM\Setup\Upgrade presente). O sysprep recusa generalizar instalacoes atualizadas; use uma instalacao limpa.')
    }

    # Reinicio pendente.
    $rebootKeys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'; Origem = 'servicing (CBS)' },
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'; Origem = 'Windows Update' }
    )
    foreach ($rebootKey in $rebootKeys) {
        if (Test-Path -LiteralPath $rebootKey.Path) {
            Add-Issue -Check 'RebootPending' -Severity 'Error' -Message ("Reinicio pendente do $($rebootKey.Origem). " +
                'Reinicie a maquina e execute novamente antes do sysprep.')
        }
    }
    try {
        $sessionManager = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction Stop
        $pendingRename = $sessionManager.PSObject.Properties['PendingFileRenameOperations']
        if ($pendingRename -and @($pendingRename.Value | Where-Object { $_ }).Count -gt 0) {
            Add-Issue -Check 'RebootPending' -Severity 'Warning' -Message ('Ha renomeacoes de arquivo pendentes para o proximo reinicio ' +
                '(PendingFileRenameOperations). Reiniciar antes do sysprep e recomendado.')
        }
    }
    catch {
        Write-Verbose "Nao foi possivel ler PendingFileRenameOperations: $($_.Exception.Message)"
    }

    # Estado de generalizacao anterior.
    try {
        $status = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup\Status\SysprepStatus' -ErrorAction Stop
        $generalization = $status.PSObject.Properties['GeneralizationState']
        if ($generalization -and $null -ne $generalization.Value -and [int]$generalization.Value -ne 7) {
            Add-Issue -Check 'SysprepStatus' -Severity 'Warning' -Message ("Estado de generalizacao anterior incompleto " +
                "(GeneralizationState=$($generalization.Value); o normal e 7). Se o sysprep falhar, consulte " +
                'C:\Windows\System32\Sysprep\Panther\setuperr.log.')
        }
    }
    catch {
        Write-Verbose "SysprepStatus indisponivel: $($_.Exception.Message)"
    }

    $issues.ToArray()
}
