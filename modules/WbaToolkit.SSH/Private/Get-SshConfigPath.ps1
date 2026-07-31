function Get-SshConfigPath {
    <#
    .SYNOPSIS
        Retorna os caminhos padrao dos arquivos de configuracao SSH no Windows.
    #>
    [CmdletBinding()]
    param()

    $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $userProfile = if ($env:USERPROFILE) { $env:USERPROFILE } else { "C:\Users\$env:USERNAME" }

    [pscustomobject]@{
        SshdConfig             = Join-Path $programData 'ssh\sshd_config'
        SshdConfigBackupDir    = Join-Path $programData 'ssh\backups'
        HostKeysDir            = Join-Path $programData 'ssh'
        AdminAuthorizedKeys    = Join-Path $programData 'ssh\administrators_authorized_keys'
        UserSshDir             = Join-Path $userProfile '.ssh'
        UserAuthorizedKeys     = Join-Path $userProfile '.ssh\authorized_keys'
        UserConfig             = Join-Path $userProfile '.ssh\config'
        UserKnownHosts         = Join-Path $userProfile '.ssh\known_hosts'
        SshLogsDir             = Join-Path $programData 'ssh\logs'
    }
}
