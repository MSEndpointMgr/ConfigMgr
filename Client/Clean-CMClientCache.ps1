<#
.SYNOPSIS
    Clean the ConfigMgr client cache for items not used within the set amount of retention days.

.DESCRIPTION
    Clean the ConfigMgr client cache for items not used within the set amount of retention days.

.PARAMETER RetentionDays
    Purge client cache items not refreshed within the set value.

.EXAMPLE
    # Purge items in the ConfigMgr client cache that have not been refreshed within the last 7 days:
    .\Clean-CMClientCache.ps1 -RetentionDays 7

.NOTES
    FileName:    Clean-CMClientCache.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2019-02-15
    Updated:     2019-02-15

    Version history:
    1.0.0 - (2019-02-15) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Purge client cache items not refreshed within the set value.")]
    [ValidateNotNullOrEmpty()]
    [string]$RetentionDays
)
Process {
    # Construct a new UIResourceMgr object
    $CCMClient = New-Object -ComObject UIResource.UIResourceMgr
    if ($CCMClient -ne $null) {
        if (($CCMClient.GetType()).Name -match "_ComObject") {
            # Get client cache directory location
            $CCMCacheDir = ($CCMClient.GetCacheInfo().Location)
            
            # List all applications due in the future or currently running
            $PendingApps = $CCMClient.GetAvailableApplications() | Where-Object { (($_.StartTime -gt (Get-Date)) -or ($_.IsCurrentlyRunning -eq "1")) }
            
            # Create list of applications to purge from cache
            $PurgeApps = $CCMClient.GetCacheInfo().GetCacheElements() | Where-Object { ($_.ContentID -notin $PendingApps.PackageID) -and $((Test-Path -Path $_.Location) -eq $true) -and ($_.LastReferenceTime -lt (Get-Date).AddDays(-$RetentionDays)) }
            
            # Purge apps no longer required
            foreach ($App in $PurgeApps)
            {
                $CCMClient.GetCacheInfo().DeleteCacheElement($App.CacheElementID)
            }
            
            # Clean Up Misc Directories 
            $ActiveDirs = $CCMClient.GetCacheInfo().GetCacheElements() | ForEach-Object { Write-Output $_.Location }
            Get-ChildItem -Path $CCMCacheDir | Where-Object { (($_.PsIsContainer -eq $true) -and ($_.FullName -notin $ActiveDirs)) } | Remove-Item -Recurse -Force -Verbose
        }
    }
}