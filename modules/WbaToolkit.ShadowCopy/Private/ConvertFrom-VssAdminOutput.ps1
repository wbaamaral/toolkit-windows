function ConvertFrom-VssAdminOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $result = [pscustomobject]@{
        Shadows   = @()
        Storage   = @()
        Providers = @()
    }

    $currentSection = ''
    $currentItem    = $null

    foreach ($line in ($Text -split "`n")) {
        $trimmed = $line.Trim()

        if ($trimmed -match '^\s*Provider ID:') {
            if ($null -ne $currentItem) { $result.Providers += $currentItem }
            $currentItem = [pscustomobject]@{
                ProviderId   = ''
                Type         = ''
                Version      = ''
                Description  = ''
            }
            $currentSection = 'Provider'
        }
        elseif ($trimmed -match '^\s*Shadow Copy ID:') {
            if ($null -ne $currentItem -and $currentSection -eq 'Shadow') { $result.Shadows += $currentItem }
            $currentItem = [pscustomobject]@{
                ShadowCopyId  = ''
                ShadowCopySetId = ''
                OriginalVolume = ''
                ShadowCopyVolume = ''
                Provider       = ''
                State          = ''
                CreationTime   = ''
            }
            $currentSection = 'Shadow'
        }
        elseif ($trimmed -match '^\s*Volume:') {
            if ($null -ne $currentItem -and $currentSection -eq 'Storage') { $result.Storage += $currentItem }
            $currentItem = [pscustomobject]@{
                Volume            = ''
                ShadowCopyStorage = ''
                UsedSpace         = ''
                AllocatedSpace    = ''
                MaximumSpace      = ''
            }
            $currentSection = 'Storage'
        }

        if ($null -ne $currentItem) {
            if ($trimmed -match 'Original Volume:\s*(.+)') {
                $currentItem.OriginalVolume = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Shadow Copy Volume:\s*(.+)') {
                $currentItem.ShadowCopyVolume = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Provider Id:\s*(.+)') {
                if ($currentSection -eq 'Provider') {
                    $currentItem.ProviderId = $Matches[1].Trim()
                } else {
                    $currentItem.Provider = $Matches[1].Trim()
                }
            }
            elseif ($trimmed -match 'State:\s*(.+)') {
                $currentItem.State = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Creation Time:\s*(.+)') {
                $currentItem.CreationTime = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Shadow Copy ID:\s*(.+)') {
                $currentItem.ShadowCopyId = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Shadow Copy Set ID:\s*(.+)') {
                $currentItem.ShadowCopySetId = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Used Space:\s*(.+)') {
                $currentItem.UsedSpace = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Allocated Space:\s*(.+)') {
                $currentItem.AllocatedSpace = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Maximum Space:\s*(.+)') {
                $currentItem.MaximumSpace = $Matches[1].Trim()
            }
            elseif ($trimmed -match 'Shadow Copy Storage Volume:\s*(.+)') {
                $currentItem.ShadowCopyStorage = $Matches[1].Trim()
            }
        }
    }

    if ($null -ne $currentItem) {
        switch ($currentSection) {
            'Shadow'  { $result.Shadows += $currentItem }
            'Storage' { $result.Storage += $currentItem }
            'Provider'{ $result.Providers += $currentItem }
        }
    }

    $result
}
