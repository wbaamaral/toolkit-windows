function Get-DefaultUserHivePath {
    <#
    .SYNOPSIS
        Retorna o caminho do arquivo de hive do perfil padrao do Windows.

    .DESCRIPTION
        Localiza o arquivo NTUSER.DAT do perfil Default do Windows, que serve
        como template para todas as novas contas de usuario criadas no sistema.
        O diretorio de perfis e obtido do registro do sistema, garantindo
        compatibilidade com instalacoes nao-padrao.

    .EXAMPLE
        $caminho = Get-DefaultUserHivePath

    .OUTPUTS
        System.String
        Caminho completo para o arquivo NTUSER.DAT do perfil Default.
    #>
    [CmdletBinding()]
    param()

    $chavePerfilList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $dirPerfis = (Get-ItemProperty -LiteralPath $chavePerfilList -Name 'ProfilesDirectory' -ErrorAction Stop).ProfilesDirectory

    $hivePath = Join-Path $dirPerfis 'Default\NTUSER.DAT'

    if (-not (Test-Path -LiteralPath $hivePath)) {
        throw "Hive do perfil Default nao encontrado em: $hivePath"
    }

    return $hivePath
}
