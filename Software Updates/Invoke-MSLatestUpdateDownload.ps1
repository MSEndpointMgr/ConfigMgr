<#
.SYNOPSIS
    Download Windows 10 updates for a specific version, e.g. 1803 from Update Catalog.

.DESCRIPTION
    This script can download given updates, more specifically Cumulative Updates, Servicing Stack Updates and Adobe Flash Updates, for a given version of Windows 10.

.PARAMETER UpdateType
    Specify the update type to download, either Cumulative, ServiceStack and/or AdobeFlash.

.PARAMETER Path
    Specify the path where the updates will be downloaded.

.PARAMETER OSBuild
    Specify a single or multiple operating system build versions, e.g. 1803, 1809 or 1903.

.PARAMETER OSArchitecture
    Specify the operating system architecture, either x64-based or x86-based.

.PARAMETER List
    Show only the updates and skip downloading them.

.EXAMPLE
    # Download the latest Cumulative Update, Servicing Stack Update and Adobe Flash Update for Windows 10 version 1803:
    .\Invoke-MSLatestUpdateDownload.ps1 -UpdateType CumulativeUpdate, ServicingStackUpdate, AdobeFlashUpdate -Path "C:\Updates\Win10" -OSBuild "1803" -OSArchitecture "x64-based"

    # List the latest Cumulative Update, Servicing Stack Update and Adobe Flash Update for Windows 10 version 1809:
    .\Invoke-MSLatestUpdateDownload.ps1 -UpdateType CumulativeUpdate, ServicingStackUpdate, AdobeFlashUpdate -Path "C:\Updates\Win10" -OSBuild "1803" -OSArchitecture "x64-based" -List

    # Download the latest Cumulative Update, Servicing Stack Update and Adobe Flash Update for Windows 10 version 1803 and version 1809:
    .\Invoke-MSLatestUpdateDownload.ps1 -UpdateType CumulativeUpdate, ServicingStackUpdate, AdobeFlashUpdate -Path "C:\Updates\Win10" -OSBuild "1803", "1809" -OSArchitecture "x64-based"

.NOTES
    FileName:    Invoke-MSLatestUpdateDownload.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2019-02-13
    Updated:     2019-02-13

    Version history:
    1.0.0 - (2019-02-13) Script created
    1.0.1 - (2019-02-13) Fixed a few static values and replaced them with variables. Added support for specifying an array of OSBuilds. File names now also contain the OSBuild version.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Specify the update type to download, either Cumulative, ServiceStack and/or AdobeFlash.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("CumulativeUpdate", "ServicingStackUpdate", "AdobeFlashUpdate")]
    [string[]]$UpdateType,

    [parameter(Mandatory=$true, HelpMessage="Specify the path where the updates will be downloaded.")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+")]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters"
        }
        else {
            # Check if the whole path exists
            if (Test-Path -Path $_ -PathType Container) {
                return $true
            }
            else {
                Write-Warning -Message "Unable to locate part of or the whole specified path, specify a valid path"
            }
        }
    })]
    [string]$Path,

    [parameter(Mandatory=$true, HelpMessage="Specify a single or multiple operating system build versions, e.g. 1803, 1809 or 1903.")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^(1[789]|2[01])0(3|9)$")]
    [string[]]$OSBuild,

    [parameter(Mandatory=$false, HelpMessage="Specify the operating system architecture, either x64-based or x86-based.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64-based", "x86-based")]
    [string]$OSArchitecture = "x64-based",

    [parameter(Mandatory=$false, HelpMessage="Show only the updates and skip downloading them.")]
    [switch]$List
)
Process {
    # Functions
    function Start-DownloadFile {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$URL,
    
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,
    
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        Begin {
            # Construct WebClient object
            $WebClient = New-Object -TypeName System.Net.WebClient
        }
        Process {
            # Create path if it doesn't exist
            if (-not(Test-Path -Path $Path)) {
                New-Item -Path $Path -ItemType Directory -Force | Out-Null
            }

            # Register events for tracking download progress
            $Global:DownloadComplete = $false
            $EventDataComplete = Register-ObjectEvent $WebClient DownloadFileCompleted -SourceIdentifier WebClient.DownloadFileComplete -Action {$Global:DownloadComplete = $true}
            $EventDataProgress = Register-ObjectEvent $WebClient DownloadProgressChanged -SourceIdentifier WebClient.DownloadProgressChanged -Action { $Global:DPCEventArgs = $EventArgs }                

            # Start download of file
            $WebClient.DownloadFileAsync($URL, (Join-Path -Path $Path -ChildPath $Name))

            # Track the download progress
            do {
                $PercentComplete = $Global:DPCEventArgs.ProgressPercentage
                $DownloadedBytes = $Global:DPCEventArgs.BytesReceived
                if ($DownloadedBytes -ne $null) {
                    Write-Progress -Activity "Downloading file: $($Name)" -Id 1 -Status "Downloaded bytes: $($DownloadedBytes)" -PercentComplete $PercentComplete
                }
            }
            until ($Global:DownloadComplete)
        }
        End {
            # Dispose of the WebClient object
            $WebClient.Dispose()

            # Unregister events used for tracking download progress
            Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged
            Unregister-Event -SourceIdentifier WebClient.DownloadFileComplete
        }
    }

    function Get-MSUpdateXML {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$FeedURL
        )
        # Construct a temporary file to store the XML content
        $XMLTempFile = Join-Path -Path $env:TEMP -ChildPath "UpdateFeed.xml"
        
        try {
            # Download update feed url and output content to temporary file
            Invoke-WebRequest -Uri $FeedURL -ContentType "application/atom+xml; charset=utf-8" -OutFile $XMLTempFile -UseBasicParsing -ErrorAction Stop -Verbose:$false
            
            if (Test-Path -Path $XMLTempFile) {
                try {
                    # Read XML file content and return data from function
                    [xml]$XMLData = Get-Content -Path $XMLTempFile -ErrorAction Stop -Encoding UTF8 -Force
    
                    try {
                        # Remove temporary XML file
                        Remove-Item -Path $XMLTempFile -Force -ErrorAction Stop
    
                        return $XMLData
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Failed to remove temporary XML file '$($XMLTempFile)'. Error message: $($_.Exception.Message)"
                    }
                }
                catch [System.Exception] {
                    Write-Warning -Message "Failed to read XML data from '$($XMLTempFile)'. Error message: $($_.Exception.Message)"
                }
            }
            else {
                Write-Warning -Message "Unable to locate temporary update XML file"
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to download update feed XML content to temporary file. Error message: $($_.Exception.Message)"
        }
    }
    
    function Get-MSDownloadInfo {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$UpdateID
        )
    
        try {
            # Retrieve the KB page from update catalog
            $UpdateCatalogRequest = Invoke-WebRequest -Uri "http://www.catalog.update.microsoft.com/Search.aspx?q=$($UpdateID)" -UseBasicParsing -ErrorAction Stop -Verbose:$false
            if ($UpdateCatalogRequest -ne $null) {
                # Determine link id's and update description
                $UpdateCatalogItems = ($UpdateCatalogRequest.Links | Where-Object { $_.Id -match "_link" })
                foreach ($UpdateCatalogItem in $UpdateCatalogItems) {
                    if (($UpdateCatalogItem.outerHTML -match $OSArchitecture) -and ($UpdateCatalogItem.outerHTML -match "Windows 10")) {
                        $CurrentUpdateDescription = ($UpdateCatalogItem.outerHTML -replace "<a[^>]*>([^<]+)<\/a>", '$1').TrimStart().TrimEnd()
                        $CurrentUpdateLinkID = $UpdateCatalogItem.id.Replace("_link", "")
                    }
                }
                
                # Construct update catalog object that will be used to call update catalog download API
                $UpdateCatalogData = [PSCustomObject]@{
                    KB = $CurrentUpdate.ID
                    LinkID = $CurrentUpdateLinkID
                    Description = $CurrentUpdateDescription
                }
    
                # Construct an ordered hashtable containing the update ID data and convert to JSON
                $UpdateCatalogTable = [ordered]@{
                    Size = 0
                    Languages = ""
                    UidInfo = $UpdateCatalogData.LinkID
                    UpdateID = $UpdateCatalogData.LinkID
                }
                $UpdateCatalogJSON = $UpdateCatalogTable | ConvertTo-Json -Compress
    
                # Construct body object for web request call
                $Body = @{
                    UpdateIDs = "[$($UpdateCatalogJSON)]"
                }
    
                # Call update catalog download dialog using a rest call
                $DownloadDialogURL = "http://www.catalog.update.microsoft.com/DownloadDialog.aspx"
                $CurrentUpdateDownloadURL = Invoke-WebRequest -Uri $DownloadDialogURL -Body $Body -Method Post -UseBasicParsing -ErrorAction Stop -Verbose:$false | Select-Object -ExpandProperty Content | Select-String -AllMatches -Pattern "(http[s]?\://download\.windowsupdate\.com\/[^\'\""]*)" | ForEach-Object { $_.Matches.Value }
                
                $UpdateCatalogDownloadItem = [PSCustomObject]@{
                    KB = $UpdateCatalogData.KB
                    Description = $CurrentUpdateDescription
                    DownloadURL = $CurrentUpdateDownloadURL
                }
                return $UpdateCatalogDownloadItem
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to invoke web request and search update catalog for specific KB article '$($CurrentUpdate.ID)'. Error message: $($_.Exception.Message)"
        }
    }
    
    function Get-MSCumulativeUpdate {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidatePattern("^(1[789]|2[01])0(3|9)$")]
            [string]$OSBuild,
    
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("x64-based", "x86-based")]
            [string]$OSArchitecture
        )
        # Construct OS build and version table
        $OSVersionTable = @{
            "1607" = 14393
            "1703" = 15063
            "1709" = 16299
            "1803" = 17134
            "1809" = 17763
        }

        # Filter object matching desired update type
        $OSBuildPattern = "$($OSVersionTable[$OSBuild]).(\d+)"
        $UpdateEntryList = New-Object -TypeName System.Collections.ArrayList
        foreach ($UpdateEntry in $UpdateFeedXML.feed.entry) {
            if ($UpdateEntry.title -match $OSBuildPattern) {
                $BuildVersion = [regex]::Match($UpdateEntry.title, $OSBuildPattern).Value
                $PSObject = [PSCustomObject]@{
                    Title = $UpdateEntry.title
                    ID = $UpdateEntry.id
                    Build = $BuildVersion
                    Updated = $UpdateEntry.updated
                }
                $UpdateEntryList.Add($PSObject) | Out-Null
            }
        }
    
        if ($UpdateEntryList.Count -ge 1) {
            # Filter and select the most current update
            $UpdateList = New-Object -TypeName System.Collections.ArrayList
            foreach ($Update in $UpdateEntryList) {
                $PSObject = [PSCustomObject]@{
                    Title = $Update.title
                    ID = "KB{0}" -f ($Update.id).Split(":")[2]
                    Build = $Update.Build.Split(".")[0]
                    Revision = [int]($Update.Build.Split(".")[1])
                    Updated = ([DateTime]::Parse($Update.updated))
                }
                $UpdateList.Add($PSObject) | Out-Null
            }
            $CurrentUpdate = $UpdateList | Sort-Object -Property Revision -Descending | Select-Object -First 1
        }
    
        # Retrieve download data from update catalog
        if ($CurrentUpdate -ne $null) {
            return Get-MSDownloadInfo -UpdateID $CurrentUpdate.ID
        }
    }
    
    function Get-MSServicingStackUpdate {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidatePattern("^(1[789]|2[01])0(3|9)$")]
            [string]$OSBuild,
    
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("x64-based", "x86-based")]
            [string]$OSArchitecture
        )
        # Filter object matching desired update type
        $UpdateEntryList = New-Object -TypeName System.Collections.ArrayList
        foreach ($UpdateEntry in $UpdateFeedXML.feed.entry) {
            if (($UpdateEntry.title -match "Servicing stack update.*") -and ($UpdateEntry.title -match ".*$($OSBuild).*")) {
                $PSObject = [PSCustomObject]@{
                    Title = $UpdateEntry.title
                    ID = $UpdateEntry.id
                    Updated = $UpdateEntry.updated
                }
                $UpdateEntryList.Add($PSObject) | Out-Null
            }
        }
    
        if ($UpdateEntryList.Count -ge 1) {
            # Filter and select the most current update
            $UpdateList = New-Object -TypeName System.Collections.ArrayList
            foreach ($Update in $UpdateEntryList) {
                $PSObject = [PSCustomObject]@{
                    Title = $Update.title
                    ID = "KB{0}" -f ($Update.id).Split(":")[2]
                    Updated = ([DateTime]::Parse($Update.updated))
                }
                $UpdateList.Add($PSObject) | Out-Null
            }
            $CurrentUpdate = $UpdateList | Sort-Object -Property Updated -Descending | Select-Object -First 1
    
            # Retrieve download data from update catalog
            if ($CurrentUpdate -ne $null) {
                return Get-MSDownloadInfo -UpdateID $CurrentUpdate.ID
            }
        }
    }

    function Get-MSAdobeFlashUpdate {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidatePattern("^(1[789]|2[01])0(3|9)$")]
            [string]$OSBuild,
    
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("x64-based", "x86-based")]
            [string]$OSArchitecture
        )       
        # Filter object matching desired update type
        $UpdateEntryList = New-Object -TypeName System.Collections.ArrayList
        foreach ($UpdateEntry in $UpdateFeedXML.feed.entry) {
            if ($UpdateEntry.title -match ".*Adobe Flash Player.*") {
                $PSObject = [PSCustomObject]@{
                    Title = $UpdateEntry.title
                    ID = $UpdateEntry.id
                    Updated = $UpdateEntry.updated
                }
                $UpdateEntryList.Add($PSObject) | Out-Null
            }
        }
    
        if ($UpdateEntryList.Count -ge 1) {
            # Filter and select the most current update
            $UpdateList = New-Object -TypeName System.Collections.ArrayList
            foreach ($Update in $UpdateEntryList) {
                $PSObject = [PSCustomObject]@{
                    Title = $Update.title
                    ID = "KB{0}" -f ($Update.id).Split(":")[2]
                    Updated = ([DateTime]::Parse($Update.updated))
                }
                $UpdateList.Add($PSObject) | Out-Null
            }
            $CurrentUpdate = $UpdateList | Sort-Object -Property Updated -Descending | Select-Object -First 1
    
            # Retrieve download data from update catalog
            if ($CurrentUpdate -ne $null) {
                return Get-MSDownloadInfo -UpdateID $CurrentUpdate.ID
            }
        }
    }

    # Retrieve the update feed XML document
    $UpdateFeedXML = Get-MSUpdateXML -FeedURL "https://support.microsoft.com/app/content/api/content/feeds/sap/en-us/6ae59d69-36fc-8e4d-23dd-631d98bf74a9/atom"        
    
    # Process each update type and retrieve update and download information
    $UpdateList = New-Object -TypeName System.Collections.ArrayList
    foreach ($UpdateItem in $UpdateType) {
        switch ($UpdateItem) {
            "CumulativeUpdate" {
                foreach ($OSBuildItem in $OSBuild) {
                    $Update = Get-MSCumulativeUpdate -OSBuild $OSBuildItem -OSArchitecture $OSArchitecture
                    $Update | Add-Member -MemberType NoteProperty -Name "Type" -Value $UpdateItem
                    $Update | Add-Member -MemberType NoteProperty -Name "OSBuild" -Value $OSBuildItem
                    $UpdateList.Add($Update) | Out-Null
                }
            }
            "ServicingStackUpdate" {
                foreach ($OSBuildItem in $OSBuild) {
                    $Update = Get-MSServicingStackUpdate -OSBuild $OSBuildItem -OSArchitecture $OSArchitecture
                    $Update | Add-Member -MemberType NoteProperty -Name "Type" -Value $UpdateItem
                    $Update | Add-Member -MemberType NoteProperty -Name "OSBuild" -Value $OSBuildItem
                    $UpdateList.Add($Update) | Out-Null
                }
            }
            "AdobeFlashUpdate" {
                foreach ($OSBuildItem in $OSBuild) {
                    $Update = Get-MSAdobeFlashUpdate -OSBuild $OSBuildItem -OSArchitecture $OSArchitecture
                    $Update | Add-Member -MemberType NoteProperty -Name "Type" -Value $UpdateItem
                    $Update | Add-Member -MemberType NoteProperty -Name "OSBuild" -Value $OSBuildItem
                    $UpdateList.Add($Update) | Out-Null
                }
            }
        }
    }
    
    # Download updates or list them only
    if ($UpdateList.Count -ge 1) {
        if ($PSBoundParameters["List"]) {
            return $UpdateList
        }
        else {
            foreach ($UpdateItem in $UpdateList) {
                Write-Verbose -Message "Starting download of '$($UpdateItem.Description)' from: $($UpdateItem.DownloadURL)"
                Start-DownloadFile -URL $UpdateItem.DownloadURL -Path $Path -Name ("Windows10.0-$($UpdateItem.OSBuild)-$($UpdateItem.KB)-$($UpdateItem.Type).msu")
            }
        }
    }
}