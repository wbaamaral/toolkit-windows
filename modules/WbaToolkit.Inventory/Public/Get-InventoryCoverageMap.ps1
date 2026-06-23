function Get-InventoryCoverageMap {
    <#
    .SYNOPSIS
        Retorna o mapa de cobertura do inventario do Xtudo.

    .DESCRIPTION
        Entrega a lista dos blocos do inventario que o script oficial cobre hoje
        e, opcionalmente, as lacunas conhecidas para evolucao futura.

    .PARAMETER IncludeGaps
        Quando informado, inclui as lacunas conhecidas alem dos blocos cobertos.

    .EXAMPLE
        Get-InventoryCoverageMap

    .EXAMPLE
        Get-InventoryCoverageMap -IncludeGaps
    #>
    [CmdletBinding()]
    param(
        [switch]$IncludeGaps
    )

    # WBA-DOCS: Category=Inventory; Related=Inventario-Hardware-Software; Manual=Mapa do escopo coberto e lacunas do inventario

    $covered = @(
        [pscustomobject]@{ Name = 'Sistema operacional'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Processador'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Memória RAM'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Placa-mãe e BIOS'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Armazenamento'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Placa de vídeo'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Rede'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Monitores'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Software instalado'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Atualizações / hotfixes'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Serviços'; Status = 'Completo' }
        [pscustomobject]@{ Name = 'Resumo de hardware e drivers'; Status = 'Parcial' }
    )

    if (-not $IncludeGaps) {
        return $covered
    }

    $gaps = @(
        'Inventário de Active Directory do cliente'
        'Inventário de impressoras e periféricos dedicados'
        'Inventário de rede por topologia, VLAN ou switch'
        'Inventário de usuários, perfis e sessões locais'
        'Inventário patrimonial/CMDB'
    )

    [pscustomobject]@{
        Covered = $covered
        Gaps    = $gaps
    }
}
