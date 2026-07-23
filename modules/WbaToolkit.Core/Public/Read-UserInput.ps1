function Read-UserInput {
    <#
    .SYNOPSIS
        Solicita entrada do operador com suporte a valor padrao.

    .DESCRIPTION
        Exibe um prompt de leitura para o operador. Quando DefaultValue for
        informado, ele e exibido entre colchetes ao lado da pergunta e adotado
        caso o operador pressione ENTER sem digitar nada.

    .PARAMETER Question
        Texto do prompt exibido ao operador.

    .PARAMETER DefaultValue
        Valor retornado quando o operador nao digitar nada. Quando omitido ou
        vazio, a entrada do operador e obrigatoria.

    .EXAMPLE
        $nome = Read-UserInput -Question 'Nome do servidor'

        Solicita o nome do servidor sem valor padrao.

    .EXAMPLE
        $dominio = Read-UserInput -Question 'FQDN do dominio AD' -DefaultValue $computerSystem.Domain

        Solicita o FQDN com o dominio detectado como padrao.

    .OUTPUTS
        System.String
        Texto digitado pelo operador (sem espacos nas extremidades) ou o
        DefaultValue quando o operador nao digitar nada.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Question,

        [Parameter(Mandatory = $false)]
        [string]$DefaultValue
    )

    if ([string]::IsNullOrWhiteSpace($DefaultValue)) {
        return (Read-Host $Question).Trim()
    }

    $value = Read-Host "$Question [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $DefaultValue
    }

    return $value.Trim()
}
