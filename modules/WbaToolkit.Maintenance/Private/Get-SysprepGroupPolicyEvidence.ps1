function Get-SysprepGroupPolicyEvidence {
    <#
    .SYNOPSIS
        Lista evidencias de diretivas de grupo realmente aplicadas na maquina.

    .DESCRIPTION
        A simples existencia de HKLM:\SOFTWARE\Policies\Microsoft ou de
        HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies NAO indica GPO:
        as duas chaves existem em toda instalacao do Windows. Esta funcao so
        reporta evidencias concretas:

        - GPO de dominio na lista de GPOs aplicadas (FileSysPath em SYSVOL, UNC);
        - Politica local com configuracoes de registro (GroupPolicy\Machine\Registry.pol).

        A entrada "Politicas de grupo locais" da GPO-List existe mesmo fora de
        dominio e sozinha nao e considerada evidencia.

    .OUTPUTS
        System.String[]. Uma descricao por evidencia; vazio quando nao ha GPO aplicada.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $evidencias = New-Object System.Collections.Generic.List[string]

    $gpoListPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine\GPO-List'
    if (Test-Path -LiteralPath $gpoListPath) {
        foreach ($gpoKey in @(Get-ChildItem -LiteralPath $gpoListPath)) {
            $gpo = Get-ItemProperty -LiteralPath $gpoKey.PSPath
            # StrictMode: acessar .Value de propriedade inexistente lanca excecao.
            $fileSysPathProp = $gpo.PSObject.Properties['FileSysPath']
            $fileSysPath = if ($fileSysPathProp) { [string]$fileSysPathProp.Value } else { '' }
            if ($fileSysPath -like '\\*') {
                $displayNameProp = $gpo.PSObject.Properties['DisplayName']
                $nome = if ($displayNameProp) { [string]$displayNameProp.Value } else { '(sem nome)' }
                $evidencias.Add("GPO de dominio aplicada: $nome ($fileSysPath)")
            }
        }
    }

    $registryPol = Join-Path $env:SystemRoot 'System32\GroupPolicy\Machine\Registry.pol'
    if (Test-Path -LiteralPath $registryPol -PathType Leaf) {
        $evidencias.Add("Politica local com configuracoes de registro: $registryPol")
    }

    # Emite os itens no pipeline; o chamador agrega com @().
    $evidencias.ToArray()
}
