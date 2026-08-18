#Requires -Version 5.1
<#
.SYNOPSIS
    Gera um nome de arquivo seguro removendo caracteres inválidos.

.DESCRIPTION
    Remove caracteres inválidos para nomes de arquivo no Windows
    (<>:"/\|?*) e trunc nomes muito longos, adicionando um hash
    SHA-256 curto para garantir unicidade.

.PARAMETER Name
    Nome original do arquivo.

.PARAMETER MaxLength
    Comprimento máximo permitido para o nome. Padrão: 259 (limite do Windows).

.EXAMPLE
    Get-SafeFileName -Name 'arquivo<inválido>.txt'
    # Retorna: 'arquivoinv_lido.txt'

.EXAMPLE
    Get-SafeFileName -Name 'documento_com_nome_muito_longo_....txt' -MaxLength 50
    # Retorna: 'documento_com_nome_muito_longo_....txt' truncado com hash

.OUTPUTS
    System.String
    Nome seguro para o arquivo, sem caracteres inválidos e dentro do limite.
#>
function Get-SafeFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [int]$MaxLength = 259
    )

    # Remove caracteres inválidos
    $validChars = $Name -replace '[<>:"/\\|?*]', ''

    # Se o nome for vazio ou apenas espaços, dar um nome padrão
    if ([string]::IsNullOrWhiteSpace($validChars)) {
        $validChars = "arquivo_sem_nome"
    }

    # Remover espaços no final
    $validChars = $validChars.TrimEnd()

    # Manter os primeiros (MaxLength - 10) caracteres e anexar hash curto do nome.
    # Get-FileHash exige caminho de arquivo existente; aqui o hash é calculado
    # diretamente sobre a string do nome via SHA256 (sem depender de arquivo).
    if ($validChars.Length -gt ($MaxLength - 10)) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name))
        $hashShort = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').Substring(0, 8)
        $base = $validChars.Substring(0, ($MaxLength - 10))
        $validChars = "$base-$hashShort"
    }

    return $validChars
}
