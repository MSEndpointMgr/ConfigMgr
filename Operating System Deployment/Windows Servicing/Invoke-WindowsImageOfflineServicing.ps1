<#
.SYNOPSIS
    Service a Windows image from a source files location with the latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and optionally Dynamic Updates if specified.

.DESCRIPTION
    This script will service Windows image from a source files location with the latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and optionally Dynamic Updates if specified.
    There are four types of updates the script handles and can automatically download:
     - Cumulative Updates
     - Service Stack Updates
     - Adobe Flash Player updates
     - Dynamic Updates (Component Updates and Setup Updates)

    Original servicing logic is using the same as published here, with a few modifications:
    https://deploymentresearch.com/Research/Post/672/Windows-10-Servicing-Script-Creating-the-better-In-Place-upgrade-image

    Requirements for running this script:
    - Access to Windows ADK locally installed on the machine where executed
    - Access to a SMS Provider in a ConfigMgr hierarchy or stand-alone site
    - UNC paths are not supported
    - Folder containing the Windows source files extracted from an ISO
    - Supported operating system editions: Enterprise, Education
    - Synchronized WSUS products: Windows 10, Windows 10 version 1903 and later, Windows 10 Dynamic Updates, Windows 10 Language Interface Packs

    Required folder structure should exist beneath the location specified for the OSMediaFilesRoot parameter:
    - Source (this folder should contain the OS media source files used for the Operating System Upgrade Package)

    An example of the complete folder structure created by the script, when E:\CMSource\OSD\OSUpgrade\W10E1809X64 has been specified for the OSMediaFilesRoot parameter:
    <OSMediaFilesRoot>\Source (Created manually, not by the script. This folder should contain the media files for Windows 10)
    <OSMediaFilesRoot>\Mount
    <OSMediaFilesRoot>\Mount\OSImage
    <OSMediaFilesRoot>\Mount\BootImage
    <OSMediaFilesRoot>\Mount\Temp
    <OSMediaFilesRoot>\Mount\WinRE
    <OSMediaFilesRoot>\Updates
    <OSMediaFilesRoot>\Updates\DUSU
    <OSMediaFilesRoot>\Updates\DUCU
    <OSMediaFilesRoot>\LanguagePack\Base
    <OSMediaFilesRoot>\LanguagePack\LXP

    This script has been tested and executed on the following platforms and requires PowerShell 5.x:
    - Windows Server 2012 R2
    - Windows Server 2016

.PARAMETER SiteServer
    Site server where the SMS Provider is installed.

.PARAMETER OSMediaFilesRoot
    Specify the full path for the root location containing a folder named Source with the Windows 10 installation media files.

.PARAMETER OSEdition
    Specify the image edition property to be extracted from the OS image.

.PARAMETER IncludeDynamicUpdates
    Apply Dynamic Updates to serviced Windows image source files.

.PARAMETER OSVersion
    Specify the operating system version being serviced.
    
.PARAMETER OSArchitecture
    Specify the operating system architecture being serviced.

.PARAMETER IncludeLanguagePack
    Specify to include Language Packs into serviced image.

.PARAMETER LPMediaFile
    Specify the full path to the Language Pack ISO media file, which includes both base LP.cab files and Local Experience Packs.

.PARAMETER LPRegionTag
    Apply specified Local Experience Pack language region tag, e.g. en-GB. Supports multiple inputs.

.PARAMETER IncludeLXP
    Specify to include Local Experience Packs (.appx packages) in addition to base Language Packs (LP.cab packages).

.PARAMETER IncludeNetFramework
    Include .NET Framework 3.5.1 when servicing the OS image.

.PARAMETER RemoveAppxPackages
    Remove built-in provisioned appx packages when servicing the OS image.

.PARAMETER SkipBackup
    Skip the complete backup of OS media source files before servicing is executed.

.EXAMPLE
    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64

    # Service a Windows Education image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -OSEdition "Education"

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeNetFramework

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1 and remove provisioned Appx packages:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeNetFramework -RemoveAppxPackages

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update, Adobe Flash Player and Dynamic Updates:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeDynamicUpdates

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update, Adobe Flash Player, Dynamic Updates and include en-GB and sv-SE Local Experience Packs:
    # NOTE: LXPMediaFile ISO file name looks similar to the following: mu_windows_10_version_1903_local_experience_packs_lxps_for_lip_languages_released_oct_2019_x86_arm64_x64_dvd_2f05e51a.iso
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeDynamicUpdates -IncludeLanguagePack -LPMediaFile "C:\CMSource\OSD\W10E1903X64\LXP.iso" -LPRegionTag "en-GB", "sv-SE"

.NOTES
    FileName:    Invoke-WindowsImageOfflineServicing.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-09-12
    Updated:     2019-11-28
    
    Version history:
    1.0.0 - (2018-09-12) Script created
    1.0.1 - (2018-09-16) Added support to remove appx packages from OS image
    1.0.2 - (2018-10-23) Added support for detecting and applying Dynamic Updates, both Setup Updates (DUSU) and Component Updates (DUCU). 
                         Simplified script parameters, OSMediaFilesPath, MountPathRoot and UpdateFilesRoot are now all replaced with OSMediaFilesRoot parameter.
    1.0.3 - (2018-11-28) Fixed an issue where the output would show the wrong backup paths for install.wim and boot.wim
    1.0.4 - (2018-11-30) Removed -Optimize parameter for Mount-WindowsImage cmdlets to support 1809 (and perhaps above). From 1803 and above it's actually slower according to test performed by David Segura
    1.0.5 - (2019-02-13) Fixed an issue where WinRE would not be exported correctly after servicing
    1.0.6 - (2019-02-19) Updated the help section to better explain the required folder structure (thanks to @JankeSkanke for pointing this out)
    1.0.7 - (2019-02-19) Fixed an issue where Dynamic Updates would be attempted to copied into the OS media source folder structure, even if the parameter switch was not specified
    1.1.0 - (2019-02-20) Added support to automatically download the latest Cumulative Update, Servicing Stack Update and Adobe Flash Player update for the specified OSVersion and OSArchitecture.
                         This change requires access to a SMS Provider where the latest update information can be accessed. Updated the help section with information changes to the folder structure that
                         has significantly been reduced. From this version and onwards the script will automatically create all required folders.
    1.1.1 - (2019-09-30) Added support for new Windows 10 product category 'Windows 10, version 1903 and later' for when updates are located through WSUS and downloaded to staging directory. Fixed an issue
                         where appx packages would not get removed cause the DisplayName instead of the PackageName property was passed. Also, added support for handling update downloades when multiple
                         content ID's exist for the same update.
    1.1.2 - (2019-10-01) Fixed an issue where Cumulative Updates download process would attempt to retrieve the .NET Framework Cumulative Update instead of the one for Windows 10.
    1.1.3 - (2019-10-02) Fixed an issue where the Invoke-MSUpdateItemDownload function would not download multiple ContentIDs when available (e.g. for .NET Framework updates).
    1.1.4 - (2019-11-15) Added support for adding Local Experience Packs (language packs) to the image that's being served in addition to setting the desired default UI language.
    1.1.5 - (2019-11-28) Added SkipBackup parameter to not perform backup steps. Improved execution logic to skip .NET Framework and Adobe Flash Player updates if they're not currently available for the 
                         Windows 10 version that's being serviced.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Site server where the SMS Provider is installed.")]
    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the full path for the root location containing a folder named Source with the Windows 10 installation media files.")]
    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters" ; break
        }
        else {
            # Check if the whole directory path exists
            if (-not(Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue)) {
                Write-Warning -Message "Unable to locate part of or the whole specified mount path" ; break
            }
            elseif (Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue) {
                return $true
            }
            else {
                Write-Warning -Message "Unhandled error" ; break
            }
        }
    })]
    [string]$OSMediaFilesRoot,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Specify the image edition property to be extracted from the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Enterprise", "Education")]
    [string]$OSEdition = "Enterprise",

    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates", HelpMessage="Apply Dynamic Updates to serviced Windows image source files.")]
    [switch]$IncludeDynamicUpdates,

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the operating system version being serviced.")]
    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("1703", "1709", "1803", "1809", "1903", "1909", "2004", "2009", "2103", "2109")]
    [string]$OSVersion,

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the operating system architecture being serviced.")]
    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64", "x86")]
    [string]$OSArchitecture = "x64",

    [parameter(Mandatory=$true, ParameterSetName="LanguagePack", HelpMessage="Specify to include Language Packs into serviced image.")]
    [switch]$IncludeLanguagePack,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Specify the full path to the Language Pack ISO media file, which includes both base LP.cab files and Local Experience Packs.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters"; break
        }
        else {
        # Check if file extension is CSV
            if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".iso") {
                return $true
            }
            else {
                Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains unsupported file extension. Supported extension is '.iso'"; break
            }
        }
    })]
    [string]$LPMediaFile,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Apply specified Local Experience Pack language region tag, e.g. en-GB. Supports multiple inputs.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ar-sa", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-gb", "en-us", "es-es", "es-mx", "et-ee", "fi-fi", "fr-ca", "fr-fr", "he-il", "hr-hr", "hu-hu", "it-it", "ja-jp", "ko-kr", "lt-lt", "lv-lv", "nb-no", "nl-nl", "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sr-latn-rs", "sv-se", "th-th", "tr-tr", "uk-ua", "zh-cn", "zh-tw")]
    [string[]]$LPRegionTag,

    [parameter(Mandatory=$false, ParameterSetName="LanguagePack", HelpMessage="Specify to include Local Experience Packs (.appx packages) in addition to base Language Packs (LP.cab packages).")]
    [switch]$IncludeLXP,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Include .NET Framework 3.5.1 when servicing the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [switch]$IncludeNetFramework,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Remove built-in provisioned appx packages when servicing the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [switch]$RemoveAppxPackages,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Skip the complete backup of OS media source files before servicing is executed.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [switch]$SkipBackup    
)
Begin {
    Write-Verbose -Message "[Environment]: Initiating environment requirements phase"

    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message " - Determining Site Code for Site server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Verbose -Message " - Using automatically detected Site Code: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine site code from specified Configuration Manager site server, specify the site server name where the SMS Provider is installed" ; break
    }

    # Detect if Windows ADK is installed, and determine installation location
    try {
        $ADKInstallPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots" -ErrorAction Stop | Select-Object -ExpandProperty KitsRoot*
        $DeploymentToolsDISMPath = Join-Path -Path $ADKInstallPath -ChildPath "Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe"
        Write-Verbose -Message " - Windows ADK installation path: $($ADKInstallPath)"
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to detect Windows ADK installation location. Error message: $($_.Exception.Message)"; break
    }
}
Process {
    # Functions
    function Invoke-Executable {
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the file name or path of the executable to be invoked, including the extension.")]
            [ValidateNotNullOrEmpty()]
            [string]$FilePath,
    
            [parameter(Mandatory=$false, HelpMessage="Specify arguments that will be passed to the executable.")]
            [ValidateNotNull()]
            [string]$Arguments
        )
    
        # Construct a hash-table for default parameter splatting
        $SplatArgs = @{
            FilePath = $FilePath
            NoNewWindow = $true
            Passthru = $true
            RedirectStandardOutput = "null.txt"
            ErrorAction = "Stop"
        }
    
        # Add ArgumentList param if present
        if (-not([System.String]::IsNullOrEmpty($Arguments))) {
            $SplatArgs.Add("ArgumentList", $Arguments)
        }
    
        # Invoke executable and wait for process to exit
        try {
            $Invocation = Start-Process @SplatArgs
            $Handle = $Invocation.Handle
            $Invocation.WaitForExit()
    
            # Remove redirected output file
            Remove-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath "null.txt") -Force
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message; break
        }
    
        return $Invocation.ExitCode
    }

    function Start-DownloadFile {
        param(
            [parameter(Mandatory=$true, HelpMessage="URL for the file to be downloaded.")]
            [ValidateNotNullOrEmpty()]
            [string]$URL,
    
            [parameter(Mandatory=$true, HelpMessage="Folder where the file will be downloaded.")]
            [ValidateNotNullOrEmpty()]
            [string]$Path,
    
            [parameter(Mandatory=$true, HelpMessage="Name of the file including file extension.")]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        Begin {
            # Set global variable
            $ErrorActionPreference = "Stop"

            # Construct WebClient object
            $WebClient = New-Object -TypeName System.Net.WebClient
        }
        Process {
            try {
                # Create path if it doesn't exist
                if (-not(Test-Path -Path $Path)) {
                    New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
                }
        
                # Start download of file
                $WebClient.DownloadFile($URL, (Join-Path -Path $Path -ChildPath $Name))
            }
            catch [System.Exception] {
                Write-Error -Message "Failed to download file from URL '$($URL)'"
            }
        }
        End {
            # Dispose of the WebClient object
            $WebClient.Dispose()
        }
    }

    function Invoke-MSUpdateItemDownload {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the path to where the update item will be downloaded.")]
            [ValidateNotNullOrEmpty()]
            [string]$FilePath,
        
            [parameter(Mandatory=$true, HelpMessage="Specify the path to where the update item will be downloaded.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("Cumulative Update", "Servicing Stack Update", "Adobe Flash Player", ".NET Framework")]
            [string]$UpdateType
        )

        # Determine correct WMI filtering for version greater than 1903, since it requires a new product type
        if ([int]$OSVersion -ge 1903) {
            $WMIQueryFilter = "LocalizedCategoryInstanceNames = 'Windows 10, version 1903 and later'"
        }
        else {
            $WMIQueryFilter = "LocalizedCategoryInstanceNames = 'Windows 10'"
        }

        # Determine the correct display name filtering options based upon update type
        switch ($UpdateType) {
            "Cumulative Update" {
                $UpdateItem = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_SoftwareUpdate -ComputerName $SiteServer -Filter $WMIQueryFilter -ErrorAction Stop | Where-Object { ($_.LocalizedDisplayName -like "*$($UpdateType)*$($OSVersion)*$($OSArchitecture)*") -and ($_.LocalizedDisplayName -notlike "*.NET Framework*") -and ($_.IsSuperseded -eq $false) -and ($_.IsLatest -eq $true)  } | Sort-Object -Property DatePosted -Descending | Select-Object -First 1
            }
            default {
                $UpdateItem = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_SoftwareUpdate -ComputerName $SiteServer -Filter $WMIQueryFilter -ErrorAction Stop | Where-Object { ($_.LocalizedDisplayName -like "*$($UpdateType)*$($OSVersion)*$($OSArchitecture)*") -and ($_.IsSuperseded -eq $false) -and ($_.IsLatest -eq $true)  } | Sort-Object -Property DatePosted -Descending | Select-Object -First 1
            }
        }
    
        if ($UpdateItem -ne $null) {
            # Determine the ContentID instances associated with the update instance
            $UpdateItemContentIDs = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_CIToContent -ComputerName $SiteServer -Filter "CI_ID = $($UpdateItem.CI_ID)" -ErrorAction Stop
            if ($UpdateItemContentIDs -ne $null) {
                # Account for multiple content ID items
                foreach ($UpdateItemContentID in $UpdateItemContentIDs) {
                    # Get the content files associated with current Content ID
                    $UpdateItemContent = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_CIContentFiles -ComputerName $SiteServer -Filter "ContentID = $($UpdateItemContentID.ContentID)" -ErrorAction Stop
                    if ($UpdateItemContent -ne $null) {
                        # Create new custom object for the update content
                        $PSObject = [PSCustomObject]@{
                            "DisplayName" = $UpdateItem.LocalizedDisplayName
                            "ArticleID" = $UpdateItem.ArticleID
                            "FileName" = $UpdateItemContent.FileName.Insert($UpdateItemContent.FileName.Length-4, "-$($OSVersion)-$($UpdateType.Replace(' ', ''))")
                            "SourceURL" = $UpdateItemContent.SourceURL
                            "DateRevised" = [System.Management.ManagementDateTimeConverter]::ToDateTime($UpdateItem.DateRevised)
                        }

                        try {
                            # Start the download of the update item
                            Write-Verbose -Message " - Downloading update item '$($UpdateType)' content from: $($PSObject.SourceURL)"
                            Start-DownloadFile -URL $PSObject.SourceURL -Path $FilePath -Name $PSObject.FileName -ErrorAction Stop
                            Write-Verbose -Message " - Completed download successfully and renamed file to: $($PSObject.FileName)"
                            $ReturnValue = 0
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "Unable to download update item content. Error message: $($_.Exception.Message)"
                            $ReturnValue = 1
                        }
                    }
                    else {
                        Write-Warning -Message " - Unable to determine update content instance for CI_ID: $($UpdateItemContentID.ContentID)"
                        $ReturnValue = 1
                    }
                }
            }
            else {
                Write-Warning -Message " - Unable to determine ContentID instance for CI_ID: $($UpdateItem.CI_ID)"
                $ReturnValue = 1
            }
        }
        else {
            Write-Warning -Message " - Unable to locate update item from SMS Provider for update type: $($UpdateType)"
            $ReturnValue = 2
        }

        # Handle return value from function
        return $ReturnValue
    }

    # PowerShell variables
    $ProgressPreference = "SilentlyContinue"

    # Define default values for skip variables
    $SkipNETFrameworkUpdate = $false
    $SkipAdobeFlashPlayerUpdate = $false
    $SkipDUCUPatch = $false
    $SkipDUSUPatch = $false
    $SkipLanguagePack = $false
    $SkipLanguagePackLXP = $false

    # Construct an array list for referencing validated and allowed LXP's to be serviced to the image
    $LPLXPAllowList = New-Object -TypeName System.Collections.ArrayList

    # White list of Appx packages to keep in the serviced image
    $WhiteListedApps = @(
        "Microsoft.DesktopAppInstaller",
        "Microsoft.Messaging", 
        "Microsoft.MSPaint",
        "Microsoft.Windows.Photos",
        "Microsoft.StorePurchaseApp",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsCalculator", 
        "Microsoft.WindowsCommunicationsApps", # Mail, Calendar etc
        "Microsoft.WindowsSoundRecorder", 
        "Microsoft.WindowsStore",
        "Microsoft.ScreenSketch",
        "Microsoft.HEIFImageExtension",
        "Microsoft.VP9VideoExtensions",
        "Microsoft.WebMediaExtensions",
        "Microsoft.WebpImageExtension"
    )

    # Construct required variables for content location
    $OSMediaFilesPath = Join-Path -Path $OSMediaFilesRoot -ChildPath "Source"
    $MountPathRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Mount"
    $UpdateFilesRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Updates"
    $LPFilesRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "LanguagePack"
    $BackupPathRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Backup"

    # Verify that Dynamic Update product is enabled in Software Update point
    if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
        try {
            $DynamicUpdateProduct = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_UpdateCategoryInstance -ComputerName $SiteServer -Filter "LocalizedCategoryInstanceName like 'Windows 10 Dynamic Update'" -ErrorAction Stop
            if ($DynamicUpdateProduct.IsSubscribed -eq $true) {
                Write-Verbose -Message " - Successfully validated that the Windows 10 Dynamic Update product is enabled in the Software Update Point component configuration"
            }
            else {
                Write-Warning -Message "Validation for the Windows 10 Dynamic Update product failed, please enable it in the Software Update Point component configuration"; break
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to validate that the Windows 10 Dynamic Update product is enabled in the Software Update Point component configuration. Error message: $($_.Exception.Message)"
        }
    }

    Write-Verbose -Message "[Environment]: Successfully completed phase"
    Write-Verbose -Message "[Content]: Initiating content requirements phase"

    # Validate Source subfolder exist
    if (-not(Test-Path -Path $OSMediaFilesPath)) {
        Write-Warning -Message "Failed to locate required Source subfolder in: $($OSMediaFilesRoot)"; break
    }

    # Validate Updates subfolder exist
    if (-not(Test-Path -Path $UpdateFilesRoot)) {
        New-Item -Path $OSMediaFilesRoot -Name "Updates" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the Updates subfolder in in: $($OSMediaFilesRoot)"
    }

    # Create Mount subfolder
    if (-not(Test-Path -Path $MountPathRoot)) {
        New-Item -Path $OSMediaFilesRoot -Name "Mount" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the Mount subfolder in: $($OSMediaFilesRoot)"
    }

    # Create Backup subfolder
    if (-not(Test-Path -Path $BackupPathRoot)) {
        New-Item -Path $OSMediaFilesRoot -Name "Backup" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the Backup subfolder in: $($OSMediaFilesRoot)"
    }

    # Create Language folder and subfolders
    if ($PSCmdlet.ParameterSetName -like "LanguagePack") {
        # Define required path variables for subfolders
        $LPBaseFilesRoot = Join-Path -Path $LPFilesRoot -ChildPath "Base"
        $LPLXPFilesRoot = Join-Path -Path $LPFilesRoot -ChildPath "LXP"

        if (-not(Test-Path -Path $LPBaseFilesRoot)) {
            # Create folder for base language packs (.cab files)
            New-Item -Path $LPBaseFilesRoot -ItemType Directory -Force | Out-Null
            Write-Verbose -Message " - Successfully created the LanguagePack\Base subfolder in: $($OSMediaFilesRoot)"
        }

        if (-not(Test-Path -Path $LPLXPFilesRoot)) {
            # Create folder for Local Experience Packs (.appx files)
            New-Item -Path $LPLXPFilesRoot -ItemType Directory -Force | Out-Null
            Write-Verbose -Message " - Successfully created the LanguagePack\LXP subfolder in: $($OSMediaFilesRoot)"
        }
    }

    # Attempt to cleanup any existing update item content files
    $UpdateItemContentFiles = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*.cab" -ErrorAction Stop
    if ($UpdateItemContentFiles -ne $null) {
        foreach ($UpdateItemContentFile in $UpdateItemContentFiles) {
            Write-Verbose -Message " - Attempting to remove existing update item content file: $($UpdateItemContentFile.Name)"
            switch -Regex ($UpdateItemContentFile.Name) {
                ".*ServicingStackUpdate.*" {
                    Write-Verbose -Message " - Existing Servicing Stack Update content file detected, will not remove"
                    $ServiceStackUpdateExists = $true
                }
                default {
                    Remove-Item -Path $UpdateItemContentFile.FullName -Force -ErrorAction Stop
                }
            }
        }
    }

    # Create OS image mount path subfolder
    $MountPathOSImage = Join-Path -Path $MountPathRoot -ChildPath "OSImage"
    if (-not(Test-Path -Path $MountPathOSImage)) {
        New-Item -Path $MountPathRoot -Name "OSImage" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the OS image mount subfolder: $($MountPathOSImage)"
    }

    # Create boot image mount path sub folder
    $MountPathBootImage = Join-Path -Path $MountPathRoot -ChildPath "BootImage"
    if (-not(Test-Path -Path $MountPathBootImage)) {
        New-Item -Path $MountPathRoot -Name "BootImage" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the boot image mount subfolder: $($MountPathBootImage)"
    }

    # Create boot image mount path sub folder
    $MountPathWinRE = Join-Path -Path $MountPathRoot -ChildPath "WinRE"
    if (-not(Test-Path -Path $MountPathWinRE)) {
        New-Item -Path $MountPathRoot -Name "WinRE" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the WinRE mount subfolder: $($MountPathWinRE)"
    }

    # Create temp mount path sub folder
    $ImagePathTemp = Join-Path -Path $MountPathRoot -ChildPath "Temp"
    if (-not(Test-Path -Path $ImagePathTemp)) {
        New-Item -Path $MountPathRoot -Name "Temp" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the temp image subfolder: $($ImagePathTemp)"
    }

    # Validate specified OS media files path contains required install.wim file
    $OSInstallWim = Join-Path -Path $OSMediaFilesPath -ChildPath "sources\install.wim"
    if (-not(Test-Path -Path $OSInstallWim)) {
        Write-Warning -Message "Unable to locate install.wim file from specified OS media file location"; break
    }

    # Validate specified OS media files path contains required boot.wim file
    $OSBootWim = Join-Path -Path $OSMediaFilesPath -ChildPath "sources\boot.wim"
    if (-not(Test-Path -Path $OSBootWim)) {
        Write-Warning -Message "Unable to locate boot.wim file from specified OS media file location"; break
    }

    # Download update item content
    $UpdateItemTypeList = @("Cumulative Update", "Servicing Stack Update" , "Adobe Flash Player", ".NET Framework")
    foreach ($UpdateItemType in $UpdateItemTypeList) {
        $Invocation = Invoke-MSUpdateItemDownload -FilePath $UpdateFilesRoot -UpdateType $UpdateItemType
        switch ($Invocation) {
            0 {
                Write-Verbose -Message " - Successfully downloaded update item content file for update type: $($UpdateItemType)"
            }
            1 {
                Write-Warning -Message " - Failed to download update item content file for update type: $($UpdateItemType)"; exit
            }
            2 {
                switch ($UpdateItemType) {
                    "Adobe Flash Player" {
                        Write-Warning -Message " - Failed to locate update item content file for update type, will proceed and mark Adobe Flash Player for skiplist"
                        $SkipAdobeFlashPlayerUpdate = $true
                    }
                    "Servicing Stack Update" {
                        if ($ServiceStackUpdateExists -eq $true) {
                            Write-Verbose -Message " - Unable to download Servicing Stack Update content, but existing content file already exists"
                        }
                        else {
                            Write-Warning -Message " - Failed to download update item content file for update type: $($UpdateItemType)"; exit
                        }
                    }
                    ".NET Framework" {
                        Write-Warning -Message " - Failed to locate update item content file for update type, will proceed and mark .NET Framework for skiplist"
                        $SkipNETFrameworkUpdate = $true
                    }
                    "Cumulative Update" {
                        Write-Warning -Message " - Failed to download update item content file for update type: $($UpdateItemType)"; exit
                    }
                }
            }
        }
    }

    if ($PSCmdlet.ParameterSetName -like "LanguagePack") {
        try {
            # Mount the language pack ISO media
            Write-Verbose -Message " - Attempting to mount the language pack media ISO: $($LPMediaFile)"
            $LPMediaMount = Mount-DiskImage -ImagePath $LPMediaFile -ErrorAction Stop -Verbose:$false -PassThru
            $LPMediaMountVolume = $LPMediaMount | Get-Volume -ErrorAction Stop -Verbose:$false | Select-Object -ExpandProperty DriveLetter
            $LPMediaMountDriveLetter = -join($LPMediaMountVolume, ":")
            Write-Verbose -Message " - Language pack media was mounted with drive letter: $($LPMediaMountDriveLetter)"

            try {
                if ($LPMediaMountDriveLetter -ne $null) {
                    # Process each specified language pack region tag and copy base language packs to servicing folder
                    $LPBaseContentRoot = Join-Path -Path $LPMediaMountDriveLetter -ChildPath $OSArchitecture
                    $LPRegionTags = $LPRegionTag -join "|"
                    foreach ($LPBasePackageItem in (Get-ChildItem -Path $LPBaseContentRoot -Recurse -Filter "*.cab" -ErrorAction Stop | Where-Object { ($_.Name -match $OSArchitecture) -and ($_.Name -notmatch "Interface") -and ($_.Name -match $LPRegionTags) })) {
                        try {
                            Write-Verbose -Message " - Copying base language pack content file to servicing location: $($LPBasePackageItem.Name)"
                            Copy-Item -Path $LPBasePackageItem.FullName -Destination (Join-Path -Path $LPBaseFilesRoot -ChildPath $LPBasePackageItem.Name) -Force -ErrorAction Stop -Verbose:$false
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "Failed to copy language pack content file '$($LPBasePackageItem.Name)' from mounted Language Pack ISO media file. Error message: $($_.Exception.Message)"
                        }
                    }

                    # Copy Local Experience Packs to servicing location, only if specified on command line
                    if ($PSBoundParameters["IncludeLXP"]) {
                        Write-Verbose -Message " - Local experience packs switch was passed on command line, will attempt to copy LXP packages to servicing location"

                        # Process each specified language pack region tag, match against local experience packs on ISO media and copy packages to servicing folder
                        $LPLXPContentRoot = Join-Path -Path $LPMediaMountDriveLetter -ChildPath "LocalExperiencePack"
                        foreach ($LPLXPPackageItem in (Get-ChildItem -Path $LPLXPContentRoot -Recurse -ErrorAction Stop -Directory | Where-Object { $_.Name -match $LPRegionTags })) {
                            try {
                                Write-Verbose -Message " - Preparing local experience pack content files for copy operation from path: $($LPLXPPackageItem.FullName)"

                                # Create region tag sub-folder
                                $LPLXPRegionTagFolder = Join-Path -Path $LPLXPFilesRoot -ChildPath $LPLXPPackageItem.Name
                                if (-not(Test-Path -Path $LPLXPRegionTagFolder)) {
                                    New-Item -Path $LPLXPRegionTagFolder -ItemType Directory -ErrorAction Stop | Out-Null
                                }

                                # Copy each file in region tab subfolder to servicing location
                                $LPLXPPackageItemFiles = Get-ChildItem -Path $LPLXPPackageItem.FullName -ErrorAction Stop | Where-Object { $_.Extension -in ".appx", ".xml" }
                                foreach ($LPLXPPackageItemFile in $LPLXPPackageItemFiles) {
                                    Write-Verbose -Message " - Copying local experience pack content file to servicing location: $($LPLXPPackageItemFile.Name)"
                                    Copy-Item -Path $LPLXPPackageItemFile.FullName -Destination (Join-Path -Path $LPLXPRegionTagFolder -ChildPath $LPLXPPackageItemFile.Name) -Force -ErrorAction Stop -Verbose:$false
                                }
                            }
                            catch [System.Exception] {
                                Write-Warning -Message "Failed to copy local experience pack content files for region tag '$($LPLXPPackageItem.Name)' from mounted Language Pack ISO media file. Error message: $($_.Exception.Message)"
                            }
                        }
                    }
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Failed to determine language pack content location in mounted Language Pack ISO media file. Error message: $($_.Exception.Message)"; break
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to mount specified Language Pack ISO media file. Error message: $($_.Exception.Message)"; break
        }
    }

    if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
        # Create Dynamic Update setup update folder
        $DUSUDownloadPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUSU"
        if (-not(Test-Path -Path $DUSUDownloadPath)) {
            New-Item -Path $UpdateFilesRoot -Name "DUSU" -ItemType Directory -Force | Out-Null
            Write-Verbose -Message " - Successfully created the dynamic update setup update subfolder"
        }

        # Create the Dynamic Update setup update extract folder
        $DUSUExtractPath = Join-Path -Path $DUSUDownloadPath -ChildPath "Extract"
        if (-not(Test-Path -Path $DUSUExtractPath)) {
            New-Item -Path $DUSUDownloadPath -Name "Extract" -ItemType Directory -Force | Out-Null
            Write-Verbose -Message " - Successfully created the dynamic update setup update extract subfolder"
        }
        else {
            # Remove extracted Dynamic Updates setup update files
            Remove-Item -Path $DUSUExtractPath -Recurse -Force

            # Re-create the DUSU extract folder
            New-Item -Path $DUSUDownloadPath -Name "Extract" -ItemType Directory -Force | Out-Null
            Write-Verbose -Message " - Successfully removed and re-created the dynamic update setup update extract subfolder"
        }

        # Create Dynamic Update component update folder
        $DUCUDownloadPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUCU"
        if (-not(Test-Path -Path $DUCUDownloadPath)) {
            New-Item -Path $UpdateFilesRoot -Name "DUCU" -ItemType Directory -Force | Out-Null
            Write-Verbose -Message " - Successfully created the dynamic update component update subfolder"
        }        
    
        # Attempt to cleanup any existing dynamic update setup update content files
        $DUSUContentFiles = Get-ChildItem -Path $DUSUDownloadPath -Recurse -Filter "*.cab" -ErrorAction Stop
        if ($DUSUContentFiles -ne $null) {
            foreach ($DUSUContentFile in $DUSUContentFiles) {
                Write-Verbose -Message " - Attempting to remove existing dynamic update setup update file: $($DUSUContentFile.Name)"
                Remove-Item -Path $DUSUContentFile.FullName -Force -ErrorAction Stop
            }
        }
    
        # Attempt to cleanup any existing dynamic update component update content files
        $DUCUContentFiles = Get-ChildItem -Path $DUCUDownloadPath -Recurse -Filter "*.cab" -ErrorAction Stop
        if ($DUCUContentFiles -ne $null) {
            foreach ($DUCUContentFile in $DUCUContentFiles) {
                Write-Verbose -Message " - Attempting to remove existing dynamic update component update file: $($DUCUContentFile.Name)"
                Remove-Item -Path $DUCUContentFile.FullName -Force -ErrorAction Stop
            }
        }    
    
        # Construct a list for dynamic update content objects
        $DynamicUpdatesList = New-Object -TypeName System.Collections.ArrayList
    
        # Get all dynamic update objects
        Write-Verbose -Message " - Attempting to retrieve dynamic update objects from SMS Provider"
        $DynamicUpdates = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_SoftwareUpdate -ComputerName $SiteServer -Filter "LocalizedCategoryInstanceNames = 'Windows 10 Dynamic Update'" -ErrorAction Stop | Where-Object { ($_.LocalizedDisplayName -like "*$($OSVersion)*$($OSArchitecture)*") -and ($_.IsSuperseded -eq $false) -and ($_.IsLatest -eq $true)  } | Sort-Object -Property LocalizedDisplayName
        if ($DynamicUpdates -ne $null) {
            foreach ($DynamicUpdate in $DynamicUpdates) {
                # Determine the Content IDs for each dynamic update
                $DynamicUpdateContentIDs = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_CIToContent -ComputerName $SiteServer -Filter "CI_ID = $($DynamicUpdate.CI_ID)" -ErrorAction Stop
                if ($DynamicUpdateContentIDs -ne $null) {
                    foreach ($DynamicUpdateContentID in $DynamicUpdateContentIDs) {
                        # Get the content files associated with current Content ID
                        $DynamicUpdateContent = Get-WmiObject -Namespace "root\SMS\Site_$($SiteCode)" -Class SMS_CIContentFiles -ComputerName $SiteServer -Filter "ContentID = $($DynamicUpdateContentID.ContentID)" -ErrorAction Stop
    
                        # Create new custom object for the Content ID and add to download list
                        $PSObject = [PSCustomObject]@{
                            "DisplayName" = $DynamicUpdate.LocalizedDisplayName
                            "ArticleID" = $DynamicUpdate.ArticleID
                            "FileName" = $DynamicUpdateContent.FileName
                            "FileType" = if (($DynamicUpdate.ArticleID -eq "4457190") -or ($DynamicUpdate.ArticleID -eq "4457189")) { "SetupUpdate" } else { $DynamicUpdate.LocalizedDescription.Replace(":","") } # Fix for ensuring 2018-09 KB4457190/KB4457189 are treated as a SetupUpdate due to wrong labeling from Microsoft
                            "SourceURL" = $DynamicUpdateContent.SourceURL
                            "DateRevised" = [System.Management.ManagementDateTimeConverter]::ToDateTime($DynamicUpdate.DateRevised)
                        }
                        $DynamicUpdatesList.Add($PSObject) | Out-Null
                    }
    
                    # Download dynamic update content objects
                    foreach ($DynamicUpdateItem in $DynamicUpdatesList) {
                        # Determine the download location based on dynamic update content file type
                        switch ($DynamicUpdateItem.FileType) {
                            "SetupUpdate" {
                                $DynamicUpdateDownloadLocation = $DUSUDownloadPath
                            }
                            "ComponentUpdate" {
                                $DynamicUpdateDownloadLocation = $DUCUDownloadPath
                            }
                        }
    
                        # Start the download of the dynamic update
                        $DynamicUpdateItemDateRevised = $DynamicUpdateItem.DateRevised.ToString("yyyy-MM-dd")
                        $DynamicUpdateItemFileName = $DynamicUpdateItem.FileName.Insert(0, "$($DynamicUpdateItemDateRevised)-")
                        Write-Verbose -Message " - Downloading dynamic update content '$($DynamicUpdateItem.FileName)' from: $($DynamicUpdateItem.SourceURL)"

                        try {
                            Start-DownloadFile -URL $DynamicUpdateItem.SourceURL -Path $DynamicUpdateDownloadLocation -Name $DynamicUpdateItemFileName -ErrorAction Stop
                            Write-Verbose -Message " - Completed download successfully and renamed file to: $($DynamicUpdateItemFileName)"
                        }
                        catch [System.Exception] {
                            Write-Warning -Message $_.Exception.Message; exit
                        }                        

                        # Expand the contents of the selected DUSU update
                        if ($DynamicUpdateItem.FileType -like "SetupUpdate") {
                            # Create dynamic update content specific folder in extract path
                            $DUSUExtractPathFolderName = Join-Path -Path $DUSUExtractPath -ChildPath $DynamicUpdateItemFileName.Replace(".cab", "")
                            if (-not(Test-Path -Path $DUSUExtractPathFolderName)) {
                                New-Item -Path $DUSUExtractPathFolderName -ItemType Directory -Force | Out-Null
                            }

                            # Invoke expand.exe for the expansion of the cab file
                            Write-Verbose -Message " - Expanding dynamic update content to: $($DUSUExtractPathFolderName)"
                            $ReturnValue = Invoke-Executable -FilePath "expand.exe" -Arguments "$(Join-Path -Path $DynamicUpdateDownloadLocation -ChildPath $DynamicUpdateItemFileName) -F:* $($DUSUExtractPathFolderName)"
                            if ($ReturnValue -ne 0) {
                                Write-Warning -Message "Failed to expand Dynamic Updates setup update files"; break
                            }
                        }
                    }
                }
            }
        }
        else {
            Write-Verbose -Message " - Query for dynamic updates returned empty"
        }
    }    

    # Validate updates root folder contains required Cumulative Update content cabinet file
    if (-not((Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*CumulativeUpdate*.cab" | Measure-Object).Count -ge 1)) {
        Write-Warning -Message "Unable to detect downloaded 'Cumulative Update' content cabinet file, breaking operation"; break
    }
    else {
        # Determine Cumulative Update file to be applied
        $CumulativeUpdateFilePath = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*CumulativeUpdate*.cab" | Where-Object { $_.Length -ge 30720000 } | Sort-Object -Descending -Property $_.CreationTime | Select-Object -First 1 -ExpandProperty FullName
        if ($CumulativeUpdateFilePath -eq $null) {
            Write-Warning -Message "Failed to locate required Cumulative Update content cabinet file, breaking operation"; break
        }
        else {
            Write-Verbose -Message " - Selected the most recent Cumulative Update content cabinet file: $($CumulativeUpdateFilePath)"
        }
    }

    # Validate updates root folder contains required Servicing Stack Update content cabinet file
    if (-not((Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*ServicingStackUpdate*.cab" | Measure-Object).Count -ge 1)) {
        Write-Warning -Message "Unable to detect downloaded 'Servicing Stack Update' content cabinet file, breaking operation"; break
    }
    else {
        # Determine Servicing Stack Update file to be applied
        $ServiceStackUpdateFilePath = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*ServicingStackUpdate*.cab" | Sort-Object -Descending -Property $_.CreationTime | Select-Object -First 1 -ExpandProperty FullName
        if ($ServiceStackUpdateFilePath -eq $null) {
            Write-Warning -Message "Failed to locate required Servicing Stack Update content cabinet file, breaking operation"; break
        }
        else {
            Write-Verbose -Message " - Selected the most recent Servicing Stack Update content cabinet file: $($ServiceStackUpdateFilePath)"
        }
    }

    # Validate updates root folder contains required .NET Framework Cumulative Update content cabinet file
    if (-not((Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*NETFramework*.cab" | Measure-Object).Count -ge 1)) {
        Write-Verbose -Message " - Unable to detect downloaded '.NET Framework Cumulative Update' content cabinet files, proceeding with script operation"
    }
    else {
        # Determine .NET Framework Cumulative Update files to be applied
        $NETFrameworkUpdateFilePaths = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*NETFramework*.cab" | Sort-Object -Descending -Property $_.CreationTime | Select-Object -ExpandProperty FullName
        if ($NETFrameworkUpdateFilePaths -eq $null) {
            Write-Warning -Message "Failed to locate required .NET Framework Cumulative Update content cabinet files, breaking operation"; break
        }
        else {
            $NETFrameworkUpdateFilePathsCount = ($NETFrameworkUpdateFilePaths | Measure-Object).Count
            foreach ($NETFrameworkUpdateFilePath in $NETFrameworkUpdateFilePaths) {
                Write-Verbose -Message " - Selected the .NET Framework Cumulative Update content cabinet file: $($NETFrameworkUpdateFilePath)"
            }
        }
    }    

    # Validate updates root folder contains required Adobe Flash Player content cabinet file
    if (-not((Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*AdobeFlashPlayer*.cab" | Measure-Object).Count -ge 1)) {
        Write-Verbose -Message " - Unable to detect downloaded 'Adobe Flash Player' content cabinet file, proceeding with script operation"
    }
    else {
        # Determine Adobe Flash Player file to be applied
        $OtherUpdateFilePaths = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter "*AdobeFlashPlayer*.cab" | Sort-Object -Descending -Property $_.CreationTime | Select-Object -First 1 -ExpandProperty FullName
        if ($OtherUpdateFilePaths -eq $null) {
            Write-Warning -Message "Failed to locate required Adobe Flash Player content cabinet file, breaking operation"; break
        }
        else {
            Write-Verbose -Message " - Selected the most recent Adobe Flash Player content cabinet file: $($OtherUpdateFilePaths)"
        }
    }

    if ($PSCmdlet.ParameterSetName -like "LanguagePack") {
        # Validate Language Packs base content files have successfully been copied over to servicing location
        if (Test-Path -Path $LPBaseFilesRoot) {
            Write-Verbose -Message " - Located the Language Pack base content folder"
            $LPBaseFilesRootItems = Get-ChildItem -Path $LPBaseFilesRoot -Recurse -Filter "*.cab"
            if (-not(($LPBaseFilesRootItems | Measure-Object).Count -ge 1)) {
                Write-Warning -Message "Unable to detect any Language Pack base content files in servicing location, setting variable to skip processing of Language Packs"
                $SkipLanguagePack = $true
            }
            else {
                Write-Verbose -Message " - Detected '$(($LPBaseFilesRootItems).Count)' required Language Pack base content files for injection in servicing location: $($LPBaseFilesRoot)"
            }
        }

        if ($PSBoundParameters["IncludeLXP"]) {
            Write-Verbose -Message " - Local experience packs switch was passed on command line, validating LXP packages existence in servicing location"
            if (Test-Path -Path $LPLXPFilesRoot) {
                Write-Verbose -Message " - Located the Language Pack LXP content folder"
                $LPLXPRegionTagFolders = Get-ChildItem -Path $LPLXPFilesRoot
                if ($LPLXPRegionTagFolders -ne $null) {
                    Write-Verbose -Message " - Detect Language Pack LXP region tag folders present in servicing location"
                    foreach ($LPLXPRegionTagFolder in $LPLXPRegionTagFolders) {
                        Write-Verbose -Message " - Processing current Language Pack LXP region tag folder '$($LPLXPRegionTagFolder.Name)' with path: $($LPLXPRegionTagFolder.FullName)"
                        if (-not((Get-ChildItem -Path $LPLXPRegionTagFolder.FullName -Recurse | Where-Object { ($_.Extension -like ".appx") -or ($_.Extension -like ".xml") }) | Measure-Object).Count -eq 2) {
                            Write-Warning -Message "Unable to validate current Language Pack LXP content files, ensure both .appx and .xml files are present in folder"
                        }
                        else {
                            Write-Verbose -Message " - Validated Language Pack LXP region tag with required content files, adding to allow list"
                            $LPLXPCustomItem = [PSCustomObject]@{
                                RegionTag = $LPLXPRegionTagFolder.Name
                                Path = $LPLXPRegionTagFolder.FullName
                            }
                            $LPLXPAllowList.Add($LPLXPCustomItem) | Out-Null
                        }
                    }
                }
                else {
                    Write-Verbose -Message " - Language Pack LXP servicing location was empty, setting variable to skip processing of Language Pack LXPs"
                    $SkipLanguagePackLXP = $true
                }
            }
        }
    }

    if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
        # Validate Dynamic Updates DUCU folder contains required files
        $UpdatesDUCUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUCU"
        if (Test-Path -Path $UpdatesDUCUFolderPath) {
            Write-Verbose -Message " - Located the Dynamic Updates required 'DUCU' folder"
            if (-not((Get-ChildItem -Path $UpdatesDUCUFolderPath -Recurse -Filter "*.cab" | Measure-Object).Count -ge 1)) {
                Write-Warning -Message "Required Dynamic Updates 'DUCU' folder is empty, setting variable to skip processing of DUCU files"
                $SkipDUCUPatch = $true
            }
            else {
                # Determine Dynamic Updates files to be applied
                $UpdatesDUCUFilePaths = Get-ChildItem -Path $UpdatesDUCUFolderPath -Recurse -Filter "*.cab" | Sort-Object -Property $_.Name | Select-Object -ExpandProperty FullName
                if ($UpdatesDUCUFilePaths -eq $null) {
                    Write-Warning -Message "Failed to locate any Dynamic Updates files in 'DUCU' folder"
                }
                else {
                    foreach ($UpdatesDUCUFilePath in $UpdatesDUCUFilePaths) {
                        Write-Verbose -Message " - Found the following Dynamic Updates file in the 'DUCU' folder: $($UpdatesDUCUFilePath)"
                    }
                }
            }
        }
        else {
            Write-Warning -Message "Unable to locate required Dynamic Updates 'DUCU' subfolder in the update files root location"; break
        }

        # Validate Dynamic Updates DUSU folder contains required files
        $UpdatesDUSUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUSU"
        if (Test-Path -Path $UpdatesDUSUFolderPath) {
            Write-Verbose -Message " - Located the Dynamic Updates required 'DUSU' folder"
            if (-not((Get-ChildItem -Path $UpdatesDUSUFolderPath -Recurse -Filter "*.cab" | Measure-Object).Count -ge 1)) {
                Write-Warning -Message "Required Dynamic Updates 'DUSU' folder is empty, setting variable to skip processing of DUSU files"
                $SkipDUSUPatch = $true
            }
            else {
                # Determine Dynamic Updates files to be applied
                $UpdatesDUSUFilePath = Get-ChildItem -Path $UpdatesDUSUFolderPath -Recurse -Filter "*.cab" | Sort-Object -Property $_.Name | Select-Object -First 1 -ExpandProperty FullName
                if ($UpdatesDUSUFilePath -eq $null) {
                    Write-Warning -Message "Failed to locate any Dynamic Updates files in 'DUSU' folder"
                }
                else {
                    Write-Verbose -Message " - Selected the most recent Dynamic Update (DUSU) file: $($UpdatesDUSUFilePath)"
                }
            }
        }
        else {
            Write-Warning -Message "Unable to locate required Dynamic Updates 'DUSU' subfolder in the update files root location"; break
        }
    }

    Write-Verbose -Message "[Content]: Successfully completed phase"
    Write-Verbose -Message "[Pre-cleanup]: Initiating pre-cleanup phase"

    try {
        # Perform cleanup of existing files if folder structure already exist
        Write-Verbose -Message " - Checking for backed up image files to be removed"
        $BakFiles = Get-ChildItem -Path $ImagePathTemp -Recurse -Filter "*.bak" -ErrorAction Stop
        if ($BakFiles -ne $null) {
            foreach ($BakFile in $BakFiles) {
                Write-Verbose -Message " - Attempting to remove backed up image file: $($BakFile.FullName)"
                Remove-Item -Path $BakFile.FullName -Force -ErrorAction Stop
            }
        }
        else {
            Write-Verbose -Message " - There were no backed up image files that needs to be removed"
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Failed to remove backed up image files. Error message: $($_.Exception.Message)"
    }

    Write-Verbose -Message "[Pre-cleanup]: Successfully completed phase"

    try {
        Write-Verbose -Message "[OSImageTempExport]: Initiating temporary OS image export phase"

        # Export selected OS image edition from OS media files location to a temporary image
        $OSImageTempWim = Join-Path -Path $ImagePathTemp -ChildPath "install_temp.wim"
        Write-Verbose -Message " - Exporting OS image from media source location to temporary OS image: $($OSImageTempWim)"
        Export-WindowsImage -SourceImagePath $OSInstallWim -DestinationImagePath $OSImageTempWim -SourceName "Windows 10 $($OSEdition)" -ErrorAction Stop | Out-Null

        Write-Verbose -Message "[OSImageTempExport]: Successfully completed phase"

        try {
            Write-Verbose -Message "[Backup]: Initiating backup phase"
            
            if (-not($PSBoundParameters["SkipBackup"])) {
                # Backup complete set of OS media source files
                $OSMediaFilesBackupPath = Join-Path -Path $BackupPathRoot -ChildPath "$((Get-Date).ToString("yyyy-MM-dd_HHmm"))-Source"
                Write-Verbose -Message " - Backing up complete set of OS media source files into: $($OSMediaFilesBackupPath)"
                Copy-Item -Path $OSMediaFilesPath -Destination $OSMediaFilesBackupPath -Container -Recurse -Force -ErrorAction Stop
            }
            else {
                Write-Verbose -Message " - Skipping backup of OS media source files since SkipBackup parameter was specified"
            }

            Write-Verbose -Message "[Backup]: Successfully completed phase"

            try {
                Write-Verbose -Message "[OSImage]: Initiating OS image servicing phase"

                # Mount the temporary OS image
                Write-Verbose -Message " - Mounting temporary OS image file: $($OSImageTempWim)"
                Mount-WindowsImage -ImagePath $OSImageTempWim -Index 1 -Path $MountPathOSImage -ErrorAction Stop | Out-Null
    
                try {
                    # Attempt to apply required updates for OS image: Service Stack Update
                    Write-Verbose -Message " - Attempting to apply required patch in OS image for: Service Stack Update"
                    Write-Verbose -Message " - Currently processing: $($ServiceStackUpdateFilePath)"
                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
    
                    if ($ReturnValue -eq 0) {
                        try {
                            if ($PSCmdlet.ParameterSetName -like "LanguagePack") {
                                if ($SkipLanguagePack -ne $true) {
                                    # Attempt to apply package for OS image: Base Language Pack
                                    Write-Verbose -Message " - Attempting to apply package in OS image for: Base Language Pack"
                                    $LPPackageCount = 0
                                    $LPBaseFilesRootItems = Get-ChildItem -Path $LPBaseFilesRoot
                                    if ($LPBaseFilesRootItems -ne $null) {
                                        foreach ($LPBaseFilesRootItem in $LPBaseFilesRootItems) {
                                            Write-Verbose -Message " - Currently processing: $($LPBaseFilesRootItem.Name)"
                                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($LPBaseFilesRootItem.FullName)"""
    
                                            if ($ReturnValue -ne 0) {
                                                Write-Warning -Message "Failed to apply Language Pack base package: $($LPBaseFilesRootItem.Name)"
                                            }
                                            else {
                                                $LPPackageCount++
                                            }
                                        }
                                    }
    
                                    # Attempt to apply package for OS image: LXP Language Pack
                                    if ($PSBoundParameters["IncludeLXP"]) {
                                        Write-Verbose -Message " - Local experience packs switch was passed on command line, will attempt to apply LXP packages to OS image"
                                        if ($SkipLanguagePackLXP -ne $true) {
                                            $LPLXPPackageCount = 0
                                            if (($LPLXPAllowList | Measure-Object).Count -ge 1) {
                                                foreach ($LPLXPItem in $LPLXPAllowList) {
                                                    $LPLXPItemPackage = Get-ChildItem -Path $LPLXPItem.Path -Filter "*.appx"
                                                    $LPLXPItemLicense = Get-ChildItem -Path $LPLXPItem.Path -Filter "*.xml"
                                                    Write-Verbose -Message " - Currently processing: $($LPLXPItemPackage.Name)"
                                                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-ProvisionedAppxPackage /PackagePath:""$($LPLXPItemPackage.FullName)"" /LicensePath:""$($LPLXPItemLicense.FullName)"""
    
                                                    if ($ReturnValue -ne 0) {
                                                        Write-Warning -Message "Failed to apply Language Pack base package: $($LPLXPItemPackage.Name)"
                                                    }
                                                    else {
                                                        $LPLXPPackageCount++
                                                    }
                                                }
                                            }
                                        }
                                        else {
                                            Write-Verbose -Message " - Skipping Language Pack LXPs due to missing content in servicing location"
                                        }
                                    }

                                    # Determine if Language Pack and LXP injections was successfull
                                    if ($LPPackageCount -eq ($LPBaseFilesRootItems | Measure-Object).Count) {
                                        $ReturnValue = 0
                                        if ($PSBoundParameters["IncludeLXP"]) {
                                            if ($LPLXPPackageCount -eq $LPLXPAllowList.Count) {
                                                $ReturnValue = 0
                                            }
                                            else {
                                                $ReturnValue = 1
                                            }
                                        }
                                    }
                                    else {
                                        $ReturnValue = 1
                                    }
                                }
                            }
    
                            if ($ReturnValue -eq 0) {
                                # Attempt to apply required updates for OS image: Cumulative Update
                                Write-Verbose -Message " - Attempting to apply required patch in OS image for: Cumulative Update"
                                Write-Verbose -Message " - Currently processing: $($CumulativeUpdateFilePath)"
                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""

                                if ($ReturnValue -eq 0) {
                                    if ($SkipNETFrameworkUpdate -eq $false) {
                                        # Attempt to apply required updates for OS image: .NET Framework Cumulative Updates
                                        Write-Verbose -Message " - Attempting to apply required patch in OS image for: .NET Framework Cumulative Updates"
                                        $NETFrameworkUpdatesCount = 0
                                        foreach ($NETFrameworkUpdateFilePath in $NETFrameworkUpdateFilePaths) {
                                            Write-Verbose -Message " - Currently processing: $($NETFrameworkUpdateFilePath)"
                                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($NETFrameworkUpdateFilePath)"""
        
                                            if ($ReturnValue -ne 0) {
                                                Write-Warning -Message "Failed to apply required patch in OS image for: $($NETFrameworkUpdateFilePath)"
                                            }
                                            else {
                                                $NETFrameworkUpdatesCount++
                                            }
                                        }
                                    }
                                    else {
                                        $ReturnValue = 0
                                        $NETFrameworkUpdatesCount = 0
                                        $NETFrameworkUpdateFilePathsCount = 0
                                    }
        
                                    if (($ReturnValue -eq 0) -and ($NETFrameworkUpdateFilePathsCount -eq $NETFrameworkUpdatesCount)) {
                                        if ($SkipAdobeFlashPlayerUpdate -eq $false) {
                                            # Attempt to apply required updates for OS image: Other
                                            Write-Verbose -Message " - Attempting to apply '$(($OtherUpdateFilePaths | Measure-Object).Count)' required patches in OS image for: Other"
                                            foreach ($OtherUpdateFilePath in $OtherUpdateFilePaths) {
                                                Write-Verbose -Message " - Currently processing: $($OtherUpdateFilePath)"
                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($OtherUpdateFilePath)"""

                                                if ($ReturnValue -ne 0) {
                                                    Write-Warning -Message "Failed to apply required patch in OS image for: $($OtherUpdateFilePath)"
                                                }
                                            }
                                        }
        
                                        if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
                                            if ($SkipDUCUPatch -ne $true) {
                                                # Attempt to apply required updates for OS image: Dynamic Updates (DUCU)
                                                Write-Verbose -Message " - Attempting to apply '$(($UpdatesDUCUFilePaths | Measure-Object).Count)' required patches in OS image for: Dynamic Updates (DUCU)"
                                                foreach ($UpdatesDUCUFilePath in $UpdatesDUCUFilePaths) {
                                                    Write-Verbose -Message " - Currently processing: $($UpdatesDUCUFilePath)"
                                                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($UpdatesDUCUFilePath)"""
    
                                                    if ($ReturnValue -ne 0) {
                                                        Write-Warning -Message "Failed to apply required patch in OS image for: $($UpdatesDUCUFilePath)"
                                                    }                                        
                                                }
                                            }
                                            else {
                                                Write-Verbose -Message " - Skipping Dynamic Updates (DUCU) updates due to missing update files in sub-folder"
                                            }
                                        }
                                        else {
                                            $ReturnValue = 0
                                        }
        
                                        if ($ReturnValue -eq 0) {
                                            # Cleanup OS image before applying .NET Framework 3.5
                                            Write-Verbose -Message " - Attempting to perform a component cleanup and reset base of OS image, this operation could take some time"
                                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Cleanup-Image /StartComponentCleanup /ResetBase"
        
                                            if ($ReturnValue -eq 0) {
                                                if ($PSBoundParameters["IncludeNetFramework"]) {
                                                    Write-Verbose -Message " - Include .NET Framework 3.5.1 parameter was specified"
        
                                                    # Attempt to apply .NET Framework 3.5.1 to OS image
                                                    $OSMediaSourcesSxsPath = Join-Path -Path $OSMediaFilesPath -ChildPath "sources\sxs"
                                                    Write-Verbose -Message " - Attempting to apply .NET Framework 3.5.1 in OS image"
                                                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:""$($OSMediaSourcesSxsPath)"""
        
                                                    if ($ReturnValue -eq 0) {
                                                        # Attempt to re-apply (because of .NET Framework requirements) required updates for OS image: Cumulative Update
                                                        Write-Verbose -Message " - Attempting to re-apply Cumulative Update after .NET Framework 3.5.1 injection"
                                                        Write-Verbose -Message " - Currently processing: $($CumulativeUpdateFilePath)"
                                                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
        
                                                        if ($ReturnValue -eq 0) {
                                                            Write-Verbose -Message " - Successfully re-applied the Cumulative Update patch to OS image"
        
                                                            if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
                                                                if ($SkipDUCUPatch -ne $true) {
                                                                    # Attempt to apply required updates for OS image: Dynamic Updates (DUCU)
                                                                    Write-Verbose -Message " - Attempting to re-apply '$(($UpdatesDUCUFilePaths | Measure-Object).Count)' required Dynamic Updates (DUCU) after .NET Framework 3.5.1 injection"
                                                                    foreach ($UpdatesDUCUFilePath in $UpdatesDUCUFilePaths) {
                                                                        Write-Verbose -Message " - Currently processing: $($UpdatesDUCUFilePath)"
                                                                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($UpdatesDUCUFilePath)"""
                                                                        if ($ReturnValue -ne 0) {
                                                                            Write-Warning -Message "Failed to re-apply required patch in OS image for: $($UpdatesDUCUFilePath)"
                                                                        }
                                                                    }
                                                                }
                                                                else {
                                                                    Write-Verbose -Message " - Skipping Dynamic Updates (DUCU) updates due to missing update files in sub-folder"
                                                                }
                                                            }
                                                        }
                                                        else {
                                                            Write-Warning -Message "Failed to re-apply the Cumulative Update patch to OS image"
                                                        }
                                                    }
                                                    else {
                                                        Write-Warning -Message "Failed to apply .NET Framework 3.5.1 in OS image"
                                                    }
                                                }
        
                                                if ($PSBoundParameters["RemoveAppxPackages"]) {
                                                    Write-Verbose -Message " - Remove appx provisioned packages parameter was specified"
        
                                                    try {
                                                        # Retrieve existing appx provisioned apps in the mounted OS image
                                                        Write-Verbose -Message " - Attempting to retrieve provisioned appx packages in OS image"
                                                        $AppxProvisionedPackagesList = Get-AppxProvisionedPackage -Path $MountPathOSImage -ErrorAction Stop
        
                                                        # Loop through the list of provisioned appx packages
                                                        foreach ($App in $AppxProvisionedPackagesList) {
                                                            # Remove provisioned appx package if name not in white list
                                                            if (($App.DisplayName -in $WhiteListedApps)) {
                                                                Write-Verbose -Message " - Skipping excluded provisioned appx package: $($App.DisplayName)"
                                                            }
                                                            else {
                                                                try {
                                                                    # Attempt to remove AppxProvisioningPackage
                                                                    Write-Verbose -Message " - Attempting to remove provisioned appx package from OS image: $($App.PackageName)"
                                                                    Remove-AppxProvisionedPackage -PackageName $App.PackageName -Path $MountPathOSImage -ErrorAction Stop -Verbose:$false | Out-Null
                                                                }
                                                                catch [System.Exception] {
                                                                    Write-Verbose -Message "Failed to remove provisioned appx package '$($App.DisplayName)' in OS image. Error message: $($_.Exception.Message)"
                                                                }
                                                            }
                                                        }
                                                    }
                                                    catch [System.Exception] {
                                                        Write-Verbose -Message "Failed to retrieve provisioned appx package in OS image. Error message: $($_.Exception.Message)"
                                                    }
                                                }
        
                                                Write-Verbose -Message "[OSImage]: Successfully completed phase"
                                                Write-Verbose -Message "[WinREImage]: Initiating WinRE image servicing phase"
        
                                                try {
                                                    # Move WinRE image from mounted OS image to a temporary location
                                                    $OSImageWinRETemp = Join-Path -Path $ImagePathTemp -ChildPath "winre_temp.wim"
                                                    Write-Verbose -Message " - Attempting to move winre.wim file from mounted OS image to temporary location: $($OSImageWinRETemp)"
                                                    Move-Item -Path (Join-Path -Path $MountPathOSImage -ChildPath "\Windows\System32\Recovery\winre.wim") -Destination $OSImageWinRETemp -ErrorAction Stop | Out-Null
        
                                                    try {
                                                        # Mount the WinRE temporary image
                                                        Write-Verbose -Message " - Attempting to mount temporary winre_temp.wim file from: $($OSImageWinRETemp)"
                                                        Mount-WindowsImage -ImagePath $OSImageWinRETemp -Path $MountPathWinRE -Index 1 -ErrorAction Stop | Out-Null
                                                        
                                                        # Attempt to apply required updates for WinRE image: Service Stack Update
                                                        Write-Verbose -Message " - Attempting to apply required patch in temporary WinRE image for: Service Stack Update"
                                                        Write-Verbose -Message " - Currently processing: $($ServiceStackUpdateFilePath)"
                                                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathWinRE)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
                                                        
                                                        if ($ReturnValue -eq 0) {
                                                            # Attempt to apply required updates for WinRE image: Cumulative Update
                                                            Write-Verbose -Message " - Attempting to apply required patch in temporary WinRE image for: Cumulative Update"
                                                            Write-Verbose -Message " - Currently processing: $($CumulativeUpdateFilePath)"
                                                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathWinRE)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
                                                            
                                                            if ($ReturnValue -eq 0) {
                                                                # Cleanup WinRE image
                                                                Write-Verbose -Message " - Attempting to perform a component cleanup and reset base of temporary WinRE image, this operation could take some time"
                                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathWinRE)"" /Cleanup-Image /StartComponentCleanup /ResetBase"
        
                                                                if ($ReturnValue -eq 0) {
                                                                    try {
                                                                        # Dismount the WinRE image
                                                                        Write-Verbose -Message " - Attempting to dismount and save changes made to temporary WinRE image"
                                                                        Dismount-WindowsImage -Path $MountPathWinRE -Save -ErrorAction Stop | Out-Null
        
                                                                        try {
                                                                            # Move temporary WinRE to back to original source location in OS image
                                                                            Write-Verbose -Message " - Attempting to export temporary WinRE image to mounted OS image location"
                                                                            Export-WindowsImage -SourceImagePath $OSImageWinRETemp -DestinationImagePath (Join-Path -Path $MountPathOSImage -ChildPath "Windows\System32\Recovery\winre.wim") -SourceName "Microsoft Windows Recovery Environment (x64)" -ErrorAction Stop | Out-Null
        
                                                                            Write-Verbose -Message "[WinREImage]: Successfully completed phase"
                                                                            Write-Verbose -Message "[OSImageExport]: Initiating OS image export servicing phase"
        
                                                                            try {
                                                                                # Dismount the OS image
                                                                                Write-Verbose -Message " - Attempting to dismount the OS image"
                                                                                Dismount-WindowsImage -Path $MountPathOSImage -Save -ErrorAction Stop | Out-Null
        
                                                                                try {
                                                                                    # Export OS image to temporary location
                                                                                    $NewOSImageWim = Join-Path -Path $ImagePathTemp -ChildPath "install.wim"
                                                                                    Write-Verbose -Message " - Attempting to export OS edition Windows 10 $($OSEdition) to temporary location from file: $($OSImageTempWim)"
                                                                                    Export-WindowsImage -SourceImagePath $OSImageTempWim -DestinationImagePath $NewOSImageWim -SourceName "Windows 10 $($OSEdition)" -ErrorAction Stop | Out-Null
        
                                                                                    try {
                                                                                        # Remove install.wim from OS media source file location
                                                                                        Write-Verbose -Message " - Attempting to remove install.wim from OS media source file location"
                                                                                        Remove-Item -Path (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\install.wim") -Force -ErrorAction Stop
        
                                                                                        try {
                                                                                            # Replace serviced OS image wim file with existing wim file
                                                                                            Write-Verbose -Message " - Attempting to replace serviced install.wim from temporary location to OS media source files location"
                                                                                            Move-Item -Path $NewOSImageWim -Destination (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\install.wim") -Force -ErrorAction Stop
        
                                                                                            Write-Verbose -Message "[OSImageExport]: Successfully completed phase"
                                                                                            Write-Verbose -Message "[BootImage]: Initiating boot image servicing phase"
        
                                                                                            try {
                                                                                                # Copy boot.wim from OS media source location to temporary location
                                                                                                $OSBootWim = Join-Path -Path $OSMediaFilesPath -ChildPath "sources\boot.wim"
                                                                                                $OSBootWimTemp = Join-Path -Path $ImagePathTemp -ChildPath "boot_temp.wim"
                                                                                                Write-Verbose -Message " - Attempting to copy boot.wim file from OS media source files location to temporary location: $($OSBootWimTemp)"
                                                                                                Copy-Item -Path $OSBootWim -Destination $OSBootWimTemp -ErrorAction Stop
        
                                                                                                try {
                                                                                                    # Remove the read-only attribute on the temporary boot.wim file
                                                                                                    Write-Verbose -Message " - Attempting to remove read-only attribute from boot_temp.wim file"
                                                                                                    Set-ItemProperty -Path $OSBootWimTemp -Name "IsReadOnly" -Value $false -ErrorAction Stop
        
                                                                                                    try {
                                                                                                        # Mount temporary boot image file
                                                                                                        Write-Verbose -Message " - Attempting to mount temporary boot image file"
                                                                                                        Mount-WindowsImage -ImagePath $OSBootWimTemp -Index 2 -Path $MountPathBootImage -ErrorAction Stop | Out-Null
        
                                                                                                        # Attempt to apply required updates for boot image: Service Stack Update
                                                                                                        Write-Verbose -Message " - Attempting to apply required patch in temporary boot image for: Service Stack Update"
                                                                                                        Write-Verbose -Message " - Currently processing: $($ServiceStackUpdateFilePath)"
                                                                                                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathBootImage)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
        
                                                                                                        if ($ReturnValue -eq 0) {
                                                                                                            # Attempt to apply required updates for boot image: Cumulative Update
                                                                                                            Write-Verbose -Message " - Attempting to apply required patch in temporary boot image for: Cumulative Update"
                                                                                                            Write-Verbose -Message " - Currently processing: $($CumulativeUpdateFilePath)"
                                                                                                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathBootImage)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
        
                                                                                                            if ($ReturnValue -eq 0) {
                                                                                                                try {
                                                                                                                    # Dismount the temporary boot image
                                                                                                                    Write-Verbose -Message " - Attempting to dismount temporary boot image"
                                                                                                                    Dismount-WindowsImage -Path $MountPathBootImage -Save -ErrorAction Stop | Out-Null
        
                                                                                                                    Write-Verbose -Message "[BootImage]: Successfully completed phase"
                                                                                                                    Write-Verbose -Message "[BootImageExport]: Initiating boot image export servicing phase"
                                                                                                                    
                                                                                                                    try {
                                                                                                                        # Remove boot.wim from OS media source file location
                                                                                                                        Write-Verbose -Message " - Attempting to remove boot.wim from OS media source files location"
                                                                                                                        Remove-Item -Path (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\boot.wim") -Force -ErrorAction Stop
        
                                                                                                                        try {
                                                                                                                            # Replace serviced boot image wim file with existing wim file
                                                                                                                            Write-Verbose -Message " - Attempting to move temporary boot image file to OS media source files location"
                                                                                                                            Move-Item -Path $OSBootWimTemp -Destination (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\boot.wim") -Force -ErrorAction Stop
        
                                                                                                                            Write-Verbose -Message "[BootImageExport]: Successfully completed phase"
        
                                                                                                                            if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
                                                                                                                                if ($SkipDUSUPatch -ne $true) {
                                                                                                                                    try {
                                                                                                                                        Write-Verbose -Message "[OSImageFinal]: Initiating OS image final servicing phase"
                                                                                                                                        Write-Verbose -Message " - Attempting to copy Dynamic Updates setup update files into OS media source file location"
                                                                                                                                        $OSMediaSourcesPath = Join-Path -Path $OSMediaFilesPath -ChildPath "sources"
                                                                                                                                        $UpdateDUSUExtractedFolders = Get-ChildItem -Path $DUSUExtractPath -Directory -ErrorAction Stop
                                                                                                                                        foreach ($UpdateDUSUExtractedFolder in $UpdateDUSUExtractedFolders) {
                                                                                                                                            Write-Verbose -Message " - Currently processing folder: $($UpdateDUSUExtractedFolder.FullName)"
                                                                                                                                            Copy-Item -Path "$($UpdateDUSUExtractedFolder.FullName)\*" -Destination $OSMediaSourcesPath -Container -Force -Recurse -ErrorAction Stop
                                                                                                                                        }
                                                                                                                                        Write-Verbose -Message "[OSImageFinal]: Successfully completed phase"
                                                                                                                                    }
                                                                                                                                    catch [System.Exception] {
                                                                                                                                        Write-Warning -Message "Failed to copy Dynamic Updates setup update files into OS media source files. Error message: $($_.Exception.Message)"
                                                                                                                                    }
                                                                                                                                }
                                                                                                                                else {
                                                                                                                                    Write-Verbose -Message " - Skipping Dynamic Updates (DUSU) updates due to missing update files in sub-folder"
                                                                                                                                }
                                                                                                                            }
        
                                                                                                                            # Set Windows image servicing completed variable
                                                                                                                            $WindowsImageServicingCompleted = $true
                                                                                                                        }
                                                                                                                        catch [System.Exception] {
                                                                                                                            Write-Warning -Message "Failed to move boot.wim from temporary location to OS media source files location. Error message: $($_.Exception.Message)"
                                                                                                                        }
                                                                                                                    }
                                                                                                                    catch [System.Exception] {
                                                                                                                        Write-Warning -Message "Failed to remove boot.wim from OS media source files location. Error message: $($_.Exception.Message)"
                                                                                                                    }
                                                                                                                }
                                                                                                                catch [System.Exception] {
                                                                                                                    Write-Warning -Message "Failed to dismount the temporary boot image. Error message: $($_.Exception.Message)"
                                                                                                                }
                                                                                                            }
                                                                                                            else {
                                                                                                                Write-Warning -Message "Failed to apply the Cumulative Update patch to boot image"
                                                                                                            }
                                                                                                        }
                                                                                                        else {
                                                                                                            Write-Warning -Message "Failed to apply the Service Stack Update to boot image"
                                                                                                        }
                                                                                                    }
                                                                                                    catch [System.Exception] {
                                                                                                        Write-Warning -Message "Failed to mount the temporary boot image. Error message: $($_.Exception.Message)"
                                                                                                    }
                                                                                                }
                                                                                                catch [System.Exception] {
                                                                                                    Write-Warning -Message "Failed to remove read-only attribute from temporary boot.wim file. Error message: $($_.Exception.Message)"
                                                                                                }
                                                                                            }
                                                                                            catch [System.Exception] {
                                                                                                Write-Warning -Message "Failed to copy boot.wim from OS media source files location to temporary location. Error message: $($_.Exception.Message)"
                                                                                            }
                                                                                        }
                                                                                        catch [System.Exception] {
                                                                                            Write-Warning -Message "Failed to move install.wim from temporary location to OS media source files location. Error message: $($_.Exception.Message)"
                                                                                        }
                                                                                    }
                                                                                    catch [System.Exception] {
                                                                                        Write-Warning -Message "Failed to remove install.wim from OS media source files location. Error message: $($_.Exception.Message)"
                                                                                    }
                                                                                }
                                                                                catch [System.Exception] {
                                                                                    Write-Warning -Message "Failed to export OS image into temporary location. Error message: $($_.Exception.Message)"
                                                                                }
                                                                            }
                                                                            catch [System.Exception] {
                                                                                Write-Warning -Message "Failed to export WinRE image into OS image. Error message: $($_.Exception.Message)"
                                                                            }
                                                                        }
                                                                        catch [System.Exception] {
                                                                            Write-Warning -Message "Failed to export WinRE image into OS image. Error message: $($_.Exception.Message)"
                                                                        }
                                                                    }
                                                                    catch [System.Exception] {
                                                                        Write-Warning -Message "Failed to dismount WinRE image. Error message: $($_.Exception.Message)"
                                                                    }
                                                                }
                                                                else {
                                                                    Write-Warning -Message "Failed to perform cleanup operation of WinRE image"
                                                                }
                                                            }
                                                            else {
                                                                Write-Warning -Message "Failed to apply the Cumulative Update to WinRE image"
                                                            }
                                                        }
                                                        else {
                                                            Write-Warning -Message "Failed to apply the Service Stack Update to WinRE image"
                                                        }
                                                    }
                                                    catch [System.Exception] {
                                                        Write-Warning -Message "Failed to mount WinRE image. Error message: $($_.Exception.Message)"
                                                    }                                            
                                                }
                                                catch [System.Exception] {
                                                    Write-Warning -Message "Failed to move WinRE image from mounted OS image to temporary location. Error message: $($_.Exception.Message)"
                                                }                                
                                            }
                                            else {
                                                Write-Warning -Message "Failed to perform cleanup operation of OS image"
                                            }                          
                                        }
                                        else {
                                            Write-Warning -Message "Failed to apply the Other patch to OS image"
                                        }
                                    }
                                    else {
                                        Write-Warning -Message "Failed to apply the .NET Framework Cumulative Update patches to OS image"
                                    }
                                }
                                else {
                                    Write-Warning -Message "Failed to apply the Cumulative Update patch to OS image"
                                }
                            }
                            else {
                                Write-Warning -Message "Failed to apply Language Packs package in OS image"
                            }
                        }
                        catch [System.Exception] {
                            Write-Verbose -Message "Failed to apply Language Packs package in OS image. Error message: $($_.Exception.Message)"
                        }
                    }
                    else {
                        Write-Warning -Message "Failed to apply Servicing Stack update in OS image"
                    }
                }
                catch [System.Exception] {
                    Write-Warning -Message "Failed to apply updates to OS image. Error message: $($_.Exception.Message)"
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Failed to mount temporary OS image. Error message: $($_.Exception.Message)"
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to backup install.wim and/or boot.wim from OS media source files location. Error message: $($_.Exception.Message)"
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Failed to export OS image from media files. Error message: $($_.Exception.Message)"
    }
}
End {
    if ($WindowsImageServicingCompleted -eq $true) {
        Write-Verbose -Message "[Servicing]: Windows image servicing completed successfully"
    }
    else {
        Write-Warning -Message "[Servicing]: Windows image servicing failed, please refer to warning messages in the output stream"
    }

    Write-Verbose -Message "[Cleanup]: Initiaing servicing cleanup process"
    try {
        # Cleanup any mounted images that should not be mounted
        Write-Verbose -Message " - Checking for mounted images that should not be mounted at this stage"
        $MountedImages = Get-WindowsImage -Mounted -ErrorAction Stop

        if ($MountedImages -ne $null) {
            foreach ($MountedImage in $MountedImages) {
                Write-Verbose -Message " - Attempting to dismount and discard image: $($MountedImage.Path)"
                Dismount-WindowsImage -Path $MountedImage.Path -Discard -ErrorAction Stop | Out-Null
                Write-Verbose -Message " - Successfully dismounted image"
            }
        }
        else {
            Write-Verbose -Message " - There were no images that was required to be dismounted"
        }

        Write-Verbose -Message "[Cleanup]: Successfully completed mounted images cleanup process"
    }
    catch [System.Exception] {
        Write-Warning -Message "Failed to dismount mounted image. Error message: $($_.Exception.Message)"
    }

    Write-Verbose -Message "[Cleanup]: Initiaing temporary image files cleanup process"
    try {
        # Remove any temporary files left after processing
        Write-Verbose -Message " - Checking for temporary image files to be removed"
        $WimFiles = Get-ChildItem -Path $MountPathRoot -Recurse -Filter "*.wim" -ErrorAction Stop
        if ($WimFiles -ne $null) {
            foreach ($WimFile in $WimFiles) {
                Write-Verbose -Message " - Attempting to remove temporary image file: $($WimFile.FullName)"
                Remove-Item -Path $WimFile.FullName -Force -ErrorAction Stop
                Write-Verbose -Message " - Successfully removed temporary image file"
            }
        }
        else {
            Write-Verbose -Message " - There were no image files that needs to be removed"
        }

        Write-Verbose -Message "[Cleanup]: Successfully completed temporary servicing cleanup files"        
    }
    catch [System.Exception] {
        Write-Warning -Message "Failed to remove temporary image files. Error message: $($_.Exception.Message)"
    }

    Write-Verbose -Message "[Cleanup]: Initiaing extracted Dynamic Update setup update files cleanup process"
    if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
        try {
            # Remove extracted Dynamic Updates setup update files
            Remove-Item -Path $DUSUExtractPath -Recurse -Force -ErrorAction Stop

            Write-Verbose -Message "[Cleanup]: Successfully completed extracted Dynamic Update setup update files cleanup process"
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to remove extracted Dynamic Updates setup update files. Error message: $($_.Exception.Message)"
        }
    }
}