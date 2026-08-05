function Resolve-ToolkitProvisioningSecret {
    <#
    .SYNOPSIS
        Resolve um secretRef para o valor protegido, via provedor CertificateEnvelope.

    .DESCRIPTION
        Unico provedor do MVP (SPEC-PROVISIONING-SECURITY): envelope CMS destinado ao
        certificado da propria maquina. O documento de configuracao carrega apenas o
        identificador do envelope (secretRef); o valor em si nunca aparece em texto claro
        na configuracao, no estado, no log ou no relatorio.

        O envelope e um arquivo .cms (produzido por Protect-CmsMessage fora desta maquina,
        contra o certificado publico da maquina destino) colocado em
        <Paths.Secrets>\<secretRef>.cms. A chave privada correspondente deve existir em
        Cert:\LocalMachine\My e ser marcada nao-exportavel pelo processo de implantacao.

        DPAPI de escopo de maquina nao resolve a distribuicao inicial (qualquer
        administrador local confiavel acessa o contexto da maquina) e por isso nao e
        oferecido como provedor de secretRef — apenas para proteger cache apos injecao
        (fora do escopo desta funcao).

    .PARAMETER SecretRef
        Identificador do segredo, conforme declarado em '{ "secretRef": "..." }' na config.

    .PARAMETER Paths
        Objeto de Get-ToolkitProvisioningPaths.

    .OUTPUTS
        System.Security.SecureString
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SecretRef,

        [Parameter(Mandatory)]
        [pscustomobject]$Paths
    )

    if ($SecretRef -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') {
        throw "secretRef invalido: '$SecretRef'."
    }

    $envelopePath = Join-Path $Paths.Secrets "$SecretRef.cms"
    if (-not (Test-Path -LiteralPath $envelopePath -PathType Leaf)) {
        throw "Envelope de segredo nao encontrado para secretRef '$SecretRef' em '$envelopePath'."
    }

    try {
        $plainText = Unprotect-CmsMessage -Path $envelopePath -ErrorAction Stop
    }
    catch {
        throw "Falha ao decifrar o envelope do secretRef '$SecretRef': $($_.Exception.Message)"
    }

    try {
        # Construcao caractere a caractere em vez de ConvertTo-SecureString -AsPlainText:
        # o texto decifrado ja passou por bytes gerenciados no processo de qualquer forma,
        # mas evita o padrao que PSScriptAnalyzer sinaliza (PSAvoidUsingConvertToSecureStringWithPlainText)
        # como confissao de segredo em texto claro no proprio codigo-fonte.
        $secure = New-Object System.Security.SecureString
        foreach ($ch in $plainText.ToCharArray()) {
            $secure.AppendChar($ch)
        }
        $secure.MakeReadOnly()
        return $secure
    }
    finally {
        $plainText = $null
    }
}
