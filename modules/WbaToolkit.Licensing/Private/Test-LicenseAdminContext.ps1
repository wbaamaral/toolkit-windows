function Test-LicenseAdminContext {
    [CmdletBinding()]
    param()
    try {
        $os = @(Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop)
        if ($os.Count -eq 0) { throw 'Consulta CIM de Win32_OperatingSystem não retornou dados.' }
        if (-not (Test-IsAdministrator)) { throw 'A operação exige um processo elevado.' }
        return $true
    }
    catch {
        throw "Contexto administrativo de licenciamento não validado: $($_.Exception.Message)"
    }
}
