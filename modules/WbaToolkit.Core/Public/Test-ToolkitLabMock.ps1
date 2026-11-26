function Test-ToolkitLabMock {
    <#
    .SYNOPSIS
        Indica se os mocks do laboratorio Docker (WBA_MOCK_AD) podem ser usados.

    .DESCRIPTION
        Os mocks de tests/lab-docker simulam w32tm, nltest, servicos e sincronizacao
        de horario para rodar o diagnostico de AD em pwsh no Linux. Em Windows eles
        nunca valem: uma variavel de ambiente esquecida (ou plantada) faria o toolkit
        relatar sucesso sem executar nada. Por isso exigem WBA_MOCK_AD definida E
        plataforma diferente de Windows.

    .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ([string]::IsNullOrWhiteSpace($env:WBA_MOCK_AD)) { return $false }
    return ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT)
}
