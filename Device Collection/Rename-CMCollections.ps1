[CmdletBinding()]
param(
[parameter(Mandatory=$true)]
[string]$SiteServer,
[parameter(Mandatory=$true)]
[string]$SiteCode,
[parameter(Mandatory=$true)]
[int]$CollectionType,
[parameter(Mandatory=$true)]
[string]$SearchFor,
[parameter(Mandatory=$true)]
[string]$ReplaceWith,
[parameter(Mandatory=$false)]
[switch]$WhatIf
)
Process {
    $Collections = Get-WmiObject -Class SMS_Collection -Namespace "root\SMS\site_$($SiteCode)" -ComputerName "$($SiteServer)" | Where-Object { ($_.CollectionType -eq $CollectionType) -and ($_.Name -like "*$($SearchFor)*") }
    $Collections | ForEach-Object {
        if ($WhatIf -eq $true) {
            Write-Output "Collection to rename: $($_.Name)"
        }
        elseif ($WhatIf -ne $true) {
            Write-Output "Current collection name: $($_.Name)"
            Write-Output "New collection name: $($_.Name -replace "$($SearchFor)","$($ReplaceWith)")`n"
            $_.Name = $_.Name -replace "$($SearchFor)","$($ReplaceWith)"
            $_.Put() | Out-Null
        }
    }
}