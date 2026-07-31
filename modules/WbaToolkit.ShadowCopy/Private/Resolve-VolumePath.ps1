function Resolve-VolumePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Volume
    )

    $v = $Volume.TrimEnd('\').TrimEnd(':')
    if ($v.Length -eq 1 -and $v -match '[A-Za-z]') {
        return "${v}:\"
    }
    if ($v -match '^[A-Za-z]:\\') {
        return $v
    }
    throw "Volume invalido: '$Volume'. Use formato como 'C:' ou 'C:\'."
}
