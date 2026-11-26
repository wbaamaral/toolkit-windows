function Resolve-LicenseError {
    <#
    .SYNOPSIS
        Consulta a tabela canônica de erros de ativação 0xC004*/0x80* (RF-02).
    .DESCRIPTION
        Recebe um código de erro de ativação (de Invoke-Slmgr.ExitCode ou digitado
        pelo operador) e retorna significado, causas prováveis, procedimentos
        recomendados e severidade. Nunca executa correção — apenas recomenda.
    .PARAMETER Codigo
        Código no formato 0xXXXXXXXX (ex.: 0xC004F034).
    .EXAMPLE
        Resolve-LicenseError -Codigo '0xC004F034'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^0x[0-9A-Fa-f]{8}$')]
        [string]$Codigo
    )

    $normalized = $Codigo.ToUpperInvariant()

    if ($script:LicenseErrorTable.ContainsKey($normalized)) {
        $entry = $script:LicenseErrorTable[$normalized]
        return [pscustomobject]@{
            Codigo = $normalized
            Hex = '0x{0:X8}' -f ([int64]('0x' + $normalized.Substring(2)))
            Significado = $entry.Significado
            Causas = @($entry.Causas)
            Procedimentos = @($entry.Procedimentos)
            Severidade = $entry.Severidade
        }
    }

    return [pscustomobject]@{
        Codigo = $normalized
        Hex = '0x{0:X8}' -f ([int64]('0x' + $normalized.Substring(2)))
        Significado = 'Não catalogado'
        Causas = @('Código não presente na tabela canônica do toolkit')
        Procedimentos = @('Consultar documentação Microsoft para o código informado')
        Severidade = 'informativo'
    }
}

$script:LicenseErrorTable = @{
    '0XC004F034' = @{
        Significado  = 'Software Licensing Service reports license could not be found'
        Causas       = @('Chave não instalada', 'Product Key removida (/upk) sem reinstalação')
        Procedimentos = @('Instalar uma Product Key válida (Install-WindowsProductKey)', 'Ativar (Activate-WindowsLicense)')
        Severidade   = 'erro'
    }
    '0XC004C003' = @{
        Significado  = 'Activation server determined the product key is blocked'
        Causas       = @('Chave bloqueada pela Microsoft', 'Uso em PCs além do limite da licença')
        Procedimentos = @('Usar outra chave legítima', 'Chave definitivamente bloqueada — não tentar destravar')
        Severidade   = 'erro'
    }
    '0XC004C008' = @{
        Significado  = 'Activation server determined the product could not be activated'
        Causas       = @('Limite de ativações online atingido', 'Retail reaproveitada em vários hardwares')
        Procedimentos = @('Ativar por telefone (slui.exe 4)', 'Obter chave MAK/KMS corporativa')
        Severidade   = 'erro'
    }
    '0XC004F050' = @{
        Significado  = 'Software Licensing Service reported the product key is invalid'
        Causas       = @('Chave com typo', 'Chave de SKU diferente (ex.: Home em Pro)', 'Chave blacklisted')
        Procedimentos = @('Verificar edição (Get-WindowsLicenseInfo)', 'Reinstalar chave correta da edição')
        Severidade   = 'erro'
    }
    '0X803FA067' = @{
        Significado  = 'Activation failed because Windows is in an invalid hardware state'
        Causas       = @('Hardware mudou desde a última ativação', 'Digital License precisa re-vinculação')
        Procedimentos = @('Executar Invoke-LicenseRearm', 'Reiniciar', 'Ativar (Activate-WindowsLicense -Modo Online)')
        Severidade   = 'erro'
    }
    '0X8007232B' = @{
        Significado  = 'DNS name does not exist'
        Causas       = @('KMS host não resolve em DNS', 'Registro SRV _vlmcs._tcp ausente', 'Cliente não ingressado no domínio')
        Procedimentos = @('Verificar ingresso em domínio com KMS publicado', 'Configurar KMS manualmente (Set-KmsServer)', 'Validar resolução de _vlmcs._tcp')
        Severidade   = 'aviso'
    }
    '0XC004F074' = @{
        Significado  = 'Key Management Service is not responding'
        Causas       = @('Host KMS inatingível', 'Firewall/porta 1688 fechada', 'Serviço KMS parado')
        Procedimentos = @('Testar conectividade TCP 1688 com o host KMS', 'Iniciar sppsvc no host', 'Verificar firewall')
        Severidade   = 'aviso'
    }
    '0XC004F042' = @{
        Significado  = 'Software Licensing Service reported that the KMS license is not activated'
        Causas       = @('Host KMS ainda não ativado', 'SKU do Windows não suportada pelo host KMS')
        Procedimentos = @('Ativar o host KMS com chave de host KMS', 'Validar suporte da SKU do cliente pelo host')
        Severidade   = 'aviso'
    }
    '0XC004C020' = @{
        Significado  = 'Product Key has reached its activation limit'
        Causas       = @('Limite da MAK atingido')
        Procedimentos = @('Solicitar aumento do activation count no VLSC/Partner Center', 'Migrar para KMS')
        Severidade   = 'erro'
    }
    '0XC004F200' = @{
        Significado  = 'Software Licensing Service reported that the computer BIOS is invalid'
        Causas       = @('Tabela MSDM/SMBIOS ausente ou corrompida', 'Flash de BIOS em OEM_DM')
        Procedimentos = @('Re-flash do BIOS', 'Contatar o OEM se persistir')
        Severidade   = 'erro'
    }
    '0X80070422' = @{
        Significado  = 'Service is disabled or not running'
        Causas       = @('sppsvc parado ou desabilitado')
        Procedimentos = @('Set-Service sppsvc -StartupType Automatic; Start-Service sppsvc', 'Reativar em seguida')
        Severidade   = 'aviso'
    }
}
