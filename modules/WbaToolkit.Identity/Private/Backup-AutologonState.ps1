function Backup-AutologonState {
    <#
    .SYNOPSIS
        Salva os valores atuais do autologon (Winlogon) para permitir reversao.

    .DESCRIPTION
        Antes de qualquer alteracao, grava os valores atuais de AutoAdminLogon,
        DefaultUserName, DefaultDomainName, AutoLogonCount e ForceAutoLogon em
        HKLM:\SOFTWARE\WBA\WindowsToolkit\Autologon\Backup\{timestamp}.
        A senha NUNCA e copiada (esta protegida na LSA, fora do escopo do backup).

    .OUTPUTS
        System.String - caminho da chave de backup criada.
    #>
    [CmdletBinding()]
    param()

    $storePath = Get-AutologonStorePath
    if (-not (Test-Path -LiteralPath $storePath)) {
        New-Item -Path $storePath -Force -ErrorAction Stop | Out-Null
    }

    $stamp     = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
    $itemPath  = Join-Path $storePath $stamp
    New-Item -Path $itemPath -Force -ErrorAction Stop | Out-Null

    $winlogon = Get-WinlogonRegPath
    $values   = @('AutoAdminLogon', 'DefaultUserName', 'DefaultDomainName', 'AutoLogonCount', 'ForceAutoLogon')

    foreach ($name in $values) {
        $prop = Get-ItemProperty -LiteralPath $winlogon -Name $name -ErrorAction SilentlyContinue
        $raw  = if ($null -ne $prop) { $prop.$name } else { '' }
        New-ItemProperty -Path $itemPath -Name $name -Value ([string]$raw) -PropertyType String -Force -ErrorAction Stop | Out-Null
    }

    New-ItemProperty -Path $itemPath -Name 'BackedUpAt' -Value ((Get-Date).ToString('o')) -PropertyType String -Force -ErrorAction Stop | Out-Null

    return $itemPath
}
