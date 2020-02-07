<#
.SYNOPSIS
    Service a Windows image from a source files location with the latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and optionally Dynamic Updates if specified.

.DESCRIPTION
    This script will service Windows image from a source files location with the latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and optionally 
    Dynamic Updates and Language Packs if specified.
    
    There are four types of updates the script handles and can automatically download:
     - Cumulative Updates
     - Service Stack Updates
     - Adobe Flash Player updates
     - Dynamic Updates (Component Updates and Setup Updates)

    Additionally, the script can perform the following functions when servicing the image:
    - Add .NET Framework 3.5.1
    - Add Language Packs including Local Experience Packs and Language Features (Feature on Demand packages)
    - Cleanup components and perform a reset base of the image that shrinks the overall image size
    - Remove built-in provisioned application packages
    - Update the OneDriveSetup.exe executable

    Requirements for running this script:
    - Access to Windows ADK locally installed on the machine where script is executed
    - Access to a SMS Provider in a ConfigMgr hierarchy or stand-alone site
    - Local paths only, UNC paths are not supported
    - Folder containing the Windows source files extracted from an ISO media
    - Supported operating system editions for servicing: Enterprise, Education
    - Synchronized WSUS products: Windows 10, Windows 10 version 1903 and later, Windows 10 Dynamic Updates
    - Windows Management Framework 5.x is required when used on Windows Server 2012 R2

    Required folder structure should exist beneath the location specified for the OSMediaFilesRoot parameter:
    - Source (this folder should contain the OS media source files)

    An example of the complete folder structure created by the script, when E:\CMSource\OSD\OSUpgrade\W10E1809X64 has been specified for the OSMediaFilesRoot parameter:
    <OSMediaFilesRoot>\Source (created manually, not by the script. This folder should contain the original source media files)
    <OSMediaFilesRoot>\Image (this is the folder that will contains the serviced Windows image once the script has completed)
    <OSMediaFilesRoot>\Backup (will contains backups of the Image folder unless the -SkipBackup switch is passed on the command line)
    <OSMediaFilesRoot>\Mount (root folder for various sub-folders used during servicing)
    <OSMediaFilesRoot>\Mount\OSImage (will contain a temporary mounted OS image during servicing)
    <OSMediaFilesRoot>\Mount\BootImage (will contain a temporary mounted boot image during servicing)
    <OSMediaFilesRoot>\Mount\Temp (will contain exported temporary image files during servicing)
    <OSMediaFilesRoot>\Mount\WinRE (will contain a temporary mounted WinRE image during servicing)
    <OSMediaFilesRoot>\Updates (root folder for the different update content downloaded by the script)
    <OSMediaFilesRoot>\Updates\DUSU (folder containing all Dynamic Update Setup Components)
    <OSMediaFilesRoot>\Updates\DUCU (folder containing all Dynamic Update Component Updates)
    <OSMediaFilesRoot>\LanguagePack\Base (folder containing all extracted base Language Packs from ISO media)
    <OSMediaFilesRoot>\LanguagePack\LXP (folder containing all extracted Local Experience Packs from ISO media)
    <OSMediaFilesRoot>\LanguagePack\Features (folder containing all extracted Language Features from ISO media)

    This script has been tested and executed on the following platforms and requires PowerShell 5.x:
    - Windows Server 2012 R2
    - Windows Server 2016
    - Windows 10

    Logging from this script is by default set to %WINDIR%\Temp\WindowsImageServicing.log

.PARAMETER SiteServer
    Site server where the SMS Provider is installed.

.PARAMETER OSMediaFilesRoot
    Specify the full path for the root location containing a folder named Source with the Windows 10 installation media files.

.PARAMETER OSEdition
    Specify the image edition property to be extracted from the OS image.

.PARAMETER OSVersion
    Specify the operating system version being serviced.
    
.PARAMETER OSArchitecture
    Specify the operating system architecture being serviced.

.PARAMETER IncludeDynamicUpdates
    Apply Dynamic Updates to serviced Windows image source files.

.PARAMETER IncludeLanguagePack
    Specify to include Language Packs into serviced image.

.PARAMETER LPMediaFile
    Specify the full path to the Language Pack ISO media file, which includes both base LP.cab files and Local Experience Packs.

.PARAMETER LPRegionTag
    Apply specified Local Experience Pack language region tag, e.g. en-GB. Supports multiple inputs.

.PARAMETER IncludeLocalExperiencePack
    Specify to include Local Experience Packs (.appx packages) in addition or in case of non-existing base Language Packs (LP.cab packages).

.PARAMETER IncludeLanguageFeatures
    Specify to include Language Features from the Windows 10 Features on Demand ISO media.

.PARAMETER LanguageFeaturesMediaFile
    Specify the full path to the Feature on Demand ISO media file, which inclues the required language feature cabinet files.

.PARAMETER LanguageFeaturesType
    Specify any desired language feature type. Defaults to all types when not specified. Supports multiple inputs.

.PARAMETER IncludeNetFramework
    Include .NET Framework 3.5.1 when servicing the OS image.

.PARAMETER RemoveAppxPackages
    Remove built-in provisioned appx packages when servicing the OS image.

.PARAMETER UpdateOneDriveSetup
    Update the OneDriveSetup.exe file to the latest version currently available.

.PARAMETER SkipComponentCleanup
    Skip the OS image component cleanup operation.

.PARAMETER SkipBackup
    Skip the complete backup of OS media source files before servicing is executed.

.PARAMETER ShowProgress
    Display the dism.exe output in-console which is hidden by default.

.EXAMPLE
    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64

    # Service a Windows Education image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -OSEdition "Education"

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1:
    .\Invoke-WindowsImageServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeNetFramework

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1 and remove provisioned Appx packages:
    .\Invoke-WindowsImageServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeNetFramework -RemoveAppxPackages

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update, Adobe Flash Player and Dynamic Updates:
    .\Invoke-WindowsImageServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeDynamicUpdates

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update, Adobe Flash Player, Dynamic Updates and include en-GB and sv-SE language packs:
    # NOTE: LXPMediaFile ISO file name looks similar to the following: mu_windows_10_version_1903_local_experience_packs_lxps_for_lip_languages_released_oct_2019_x86_arm64_x64_dvd_2f05e51a.iso
    .\Invoke-WindowsImageServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1903X64" -OSVersion 1903 -OSArchitecture x64 -IncludeDynamicUpdates -IncludeLanguagePack -LPMediaFile "C:\CMSource\OSD\W10E1903X64\LP.iso" -LPRegionTag "en-GB", "sv-SE"

.NOTES
    FileName:    Invoke-WindowsImageServicing.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-09-12
    Updated:     2020-01-27
    
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
    2.0.0 - (2019-12-09) Most of the script has been converted into functions, to easier manage the dynamic requirements of the script. Script was renamed to Invoke-WindowsImageServicing.ps1 from previous
                         Invoke-WindowsImageOfflineServicing.ps1. Logging is now also added, console output is still possible using the -Verbose parameter. Additional progress details are now available
                         using the ShowProgress switch. Additionally, language features can now also be added using the IncludeLanguageFeatures and LanguageFeaturesMediaFile parameters.
    2.1.0 - (2020-01-27) Added new parameters to support content refresh on Distribution Points for either an Operating System Image or Operating System Upgrade Package object in ConfigMgr.
                         New parameters are RefreshPackage, PackageID and PackageType.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Site server where the SMS Provider is installed.")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the full path for the root location containing a folder named Source with the Windows 10 installation media files.")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters"; break
        }
        else {
            # Check if the whole directory path exists
            if (-not(Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue)) {
                Write-Warning -Message "Unable to locate part of or the whole specified mount path"; break
            }
            elseif (Test-Path -Path $_ -PathType Container -ErrorAction SilentlyContinue) {
                return $true
            }
            else {
                Write-Warning -Message "Unhandled error"; break
            }
        }
    })]
    [string]$OSMediaFilesRoot,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Specify the image edition property to be extracted from the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Enterprise", "Education")]
    [string]$OSEdition = "Enterprise",

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the operating system version being serviced.")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("1703", "1709", "1803", "1809", "1903", "1909", "2004", "2009", "2103", "2109")]
    [string]$OSVersion,

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the operating system architecture being serviced.")]
    [parameter(Mandatory=$true, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64", "x86")]
    [string]$OSArchitecture = "x64",

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Apply Dynamic Updates to serviced Windows image source files.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$IncludeDynamicUpdates,

    [parameter(Mandatory=$true, ParameterSetName="LanguagePack", HelpMessage="Specify to include Language Packs into serviced image.")]
    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures")]
    [switch]$IncludeLanguagePack,

    [parameter(Mandatory=$true, ParameterSetName="LanguagePack", HelpMessage="Specify the full path to the Language Pack ISO media file, which includes both base LP.cab files and Local Experience Packs.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
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

    [parameter(Mandatory=$true, ParameterSetName="LanguagePack", HelpMessage="Apply specified Local Experience Pack language region tag, e.g. en-GB. Supports multiple inputs.")]
    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ar-sa", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-gb", "en-us", "es-es", "es-mx", "et-ee", "fi-fi", "fr-ca", "fr-fr", "he-il", "hr-hr", "hu-hu", "it-it", "ja-jp", "ko-kr", "lt-lt", "lv-lv", "nb-no", "nl-nl", "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sr-latn-rs", "sv-se", "th-th", "tr-tr", "uk-ua", "zh-cn", "zh-tw")]
    [string[]]$LPRegionTag,

    [parameter(Mandatory=$false, ParameterSetName="LanguagePack", HelpMessage="Specify to include Local Experience Packs (.appx packages) in addition or in case of non-existing base Language Packs (LP.cab packages).")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$IncludeLocalExperiencePack,

    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures", HelpMessage="Specify to include Language Features from the Windows 10 Features on Demand ISO media.")]
    [switch]$IncludeLanguageFeatures,

    [parameter(Mandatory=$true, ParameterSetName="LanguageFeatures", HelpMessage="Specify the full path to the Feature on Demand ISO media file, which inclues the required language feature cabinet files.")]
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
    [string]$LanguageFeaturesMediaFile,

    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures", HelpMessage="Specify any desired language feature type. Defaults to all types when not specified. Supports multiple inputs.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Basic", "Handwriting", "OCR", "Speech", "TextToSpeech")]
    [string[]]$LanguageFeatureType = @("Basic", "Handwriting", "OCR", "Speech", "TextToSpeech"),

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Specify to refresh Distribution Points for a package in ConfigMgr.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$RefreshPackage,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Specify the PackageID value of the desired package type for content refresh on Distribution Points.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^([A-Z0-9]{3}[A-F0-9]{5})(\s*)(,[A-Z0-9]{3}[A-F0-9]{5})*$")]
    [string]$PackageID,    

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Specify the package type of either Operating System Image or Operating System Upgrade Package.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("OperatingSystemImage", "OperatingSystemUpgradePackage")]
    [string]$PackageType = "OperatingSystemImage",

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Include .NET Framework 3.5.1 when servicing the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$IncludeNetFramework,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Remove built-in provisioned appx packages when servicing the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$RemoveAppxPackages,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Update the OneDriveSetup.exe file to the latest version currently available.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$UpdateOneDriveSetup,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Skip the OS image component cleanup operation.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$SkipComponentCleanup,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Skip the complete backup of OS media source files before servicing is executed.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$SkipBackup,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Display the dism.exe output in-console which is hidden by default.")]
    [parameter(Mandatory=$false, ParameterSetName="LanguagePack")]
    [parameter(Mandatory=$false, ParameterSetName="LanguageFeatures")]
    [switch]$ShowProgress
)
Begin {
    try {
        # Validate that the script is being executed elevated
        $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $WindowsPrincipal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $CurrentIdentity
        if (-not($WindowsPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
            Write-Warning -Message "Script was not executed elevated, please re-launch."; exit
        }
    } 
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message; break
    }
}
Process {
    # Functions
    function Write-CMLogEntry {
		param (
			[parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
			[ValidateNotNullOrEmpty()]
            [string]$Value,
            
			[parameter(Mandatory=$true, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
			[ValidateNotNullOrEmpty()]
			[ValidateSet("1", "2", "3")]
            [string]$Severity,
            
			[parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
			[ValidateNotNullOrEmpty()]
			[string]$FileName = "WindowsImageServicing.log"
		)
        # Determine log file location
        $WindowsTempLocation = (Join-Path -Path $env:windir -ChildPath "Temp")
		$LogFilePath = Join-Path -Path $WindowsTempLocation -ChildPath $FileName
		
		# Construct time stamp for log entry
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""WindowsImageServicing"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file and if specified console output
		try {
            if ($Script:PSBoundParameters["Verbose"]) {
                # Write either verbose or warning output to console
                switch ($Severity) {
                    1 {
                        Write-Verbose -Message $Value
                    }
                    default {
                        Write-Warning -Message $Value
                    }
                }

                # Write output to log file
                Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
            }
            else {
                # Write output to log file
                Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
            }
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to WindowsImageServicing.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
		}
	}

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
            ErrorAction = "Stop"
        }

        # Redirect standard output unless ShowProgress script parameter is present
        if (-not($Script:PSBoundParameters["ShowProgress"])) {
            $SplatArgs.Add("RedirectStandardOutput", "null.txt")
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
            if (-not($Script:PSBoundParameters["ShowProgress"])) {
                Remove-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath "null.txt") -Force
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value $_.Exception.Message -Severity 3; throw
        }
    
        return $Invocation.ExitCode
    }

    function New-TerminatingErrorRecord {
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the exception message details.")]
            [ValidateNotNullOrEmpty()]
            [string]$Message,

            [parameter(Mandatory=$false, HelpMessage="Specify the violation exception causing the error.")]
            [ValidateNotNullOrEmpty()]
            [string]$Exception = "System.Management.Automation.RuntimeException",

            [parameter(Mandatory=$false, HelpMessage="Specify the error category of the exception causing the error.")]
            [ValidateNotNullOrEmpty()]
            [System.Management.Automation.ErrorCategory]$ErrorCategory = [System.Management.Automation.ErrorCategory]::NotImplemented,
            
            [parameter(Mandatory=$false, HelpMessage="Specify the target object causing the error.")]
            [ValidateNotNullOrEmpty()]
            [string]$TargetObject = ([string]::Empty)
        )
        # Construct new error record to be returned from function based on parameter inputs
        $SystemException = New-Object -TypeName $Exception -ArgumentList $Message
        $ErrorRecord = New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList @($SystemException, $ErrorID, $ErrorCategory, $TargetObject)

        # Handle return value
        return $ErrorRecord
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
                Write-CMLogEntry -Value " - Failed to download file from URL '$($URL)'" -Severity 3
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
                            "FileName" = $UpdateItemContent.FileName.Insert($UpdateItemContent.FileName.Length-4, "-$($OSVersion)-$($UpdateType.Replace(' ', '').Replace('.', ''))")
                            "SourceURL" = $UpdateItemContent.SourceURL
                            "DateRevised" = [System.Management.ManagementDateTimeConverter]::ToDateTime($UpdateItem.DateRevised)
                        }

                        try {
                            # Start the download of the update item
                            Write-CMLogEntry -Value " - Downloading update item '$($UpdateType)' content from: $($PSObject.SourceURL)" -Severity 1
                            Start-DownloadFile -URL $PSObject.SourceURL -Path $FilePath -Name $PSObject.FileName -ErrorAction Stop
                            Write-CMLogEntry -Value " - Download completed successfully, renamed file to: $($PSObject.FileName)" -Severity 1
                            $ReturnValue = 0
                        }
                        catch [System.Exception] {
                            Write-CMLogEntry -Value " - Unable to download update item content. Error message: $($_.Exception.Message)" -Severity 2
                            $ReturnValue = 1
                        }
                    }
                    else {
                        Write-CMLogEntry -Value " - Unable to determine update content instance for CI_ID: $($UpdateItemContentID.ContentID)" -Severity 2
                        $ReturnValue = 1
                    }
                }
            }
            else {
                Write-CMLogEntry -Value " - Unable to determine ContentID instance for CI_ID: $($UpdateItem.CI_ID)" -Severity 2
                $ReturnValue = 1
            }
        }
        else {
            Write-CMLogEntry -Value " - Unable to locate update item from SMS Provider for update type: $($UpdateType)" -Severity 2
            $ReturnValue = 2
        }

        # Handle return value from function
        return $ReturnValue
    }

    function Add-PSGalleryModule {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the name of the module that will be installed from PSGallery.")]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        # Determine if the module needs to be installed
        try {
            Write-CMLogEntry -Value " - Attempting to determine if the '$($Name)' module is already present for the current user" -Severity 1
            $CurrentVerboseValue = $VerbosePreference
            $VerbosePreference = "SilentlyContinue"
            $PSGalleryModule = Get-InstalledModule -Name $Name -ErrorAction Stop -Verbose:$false
            $VerbosePreference = $CurrentVerboseValue
            if ($PSGalleryModule -ne $null) {
                Write-CMLogEntry -Value " - Module '$($Name)' was detected, checking for latest version" -Severity 1
                $LatestModuleVersion = (Find-Module -Name $Name -ErrorAction Stop -Verbose:$false).Version
                if ($LatestModuleVersion -gt $PSGalleryModule.Version) {
                    Write-CMLogEntry -Value " - Latest version of the '$($Name)' module is not installed, attempting to install: $($LatestModuleVersion.ToString())" -Severity 1
                    $UpdateModuleInvocation = Update-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop -Confirm:$false -Verbose:$false
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Unable to detect the '$($Name)' module, attempting to install from PSGallery" -Severity 2
            try {
                # Install NuGet package provider
                $PackageProvider = Install-PackageProvider -Name NuGet -Force -Verbose:$false

                # Install module
                Install-Module -Name $Name -Scope CurrentUser -Force -ErrorAction Stop -Confirm:$false -Verbose:$false
                Write-CMLogEntry -Value " - Successfully installed the '$($Name)' module for the current user" -Severity 1
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to install the '$($Name)' module. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
    }

    function Save-OneDriveSetup {
        try {
            # Download the OneDriveSetup.exe file to temporary location
            $OneDriveSetupURL = "https://go.microsoft.com/fwlink/p/?LinkId=248256"
            Write-CMLogEntry -Value " - Attempting to download the latest OneDriveSetup.exe file from Microsoft download page to Updates root folder" -Severity 1
            Start-DownloadFile -URL $OneDriveSetupURL -Path $UpdateFilesRoot -Name "OneDriveSetup.exe"
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to download OneDriveSetup.exe file. Error message: $($_.Exception.Message)" -Severity 3
        }
    }

    function Test-OneDriveSetup {
        # Validate OneDriveSetup.exe file has successfully been downloaded to servicing to location
        if (Test-Path -Path $UpdateFilesRoot) {
            if (Test-Path -Path (Join-Path -Path $UpdateFilesRoot -ChildPath "OneDriveSetup.exe")) {
                Write-CMLogEntry -Value " - Detected 'OneDriveSetup.exe' in the root of the Updates folder" -Severity 1
            }
            else {
                Write-CMLogEntry -Value " - Unable to detect 'OneDriveSetup.exe' in the root of the Updates folder, setting variable to skip processing of OneDrive setup update" -Severity 2
                $Script:SkipOneDriveUpdate = $true
            }
        }
    }

    function Update-OneDriveSetup {
        if ($SkipOneDriveUpdate -eq $false) {
            # Ensure that the NTFSSecurity module is installed before attempting to take ownership of the OneDriveSetup.exe file
            Add-PSGalleryModule -Name "NTFSSecurity"

            try {
                # Import the NTFSSecurity module
                Write-CMLogEntry -Value " - Attempting to import the 'NTFSSecurity' module" -Severity 1
                Import-Module -Name "NTFSSecurity" -Verbose:$false -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to import the 'NTFSSecurity' module. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }

            try {
                # Save the existing ownership information
                Write-CMLogEntry -Value " - Attempting to read and temporarily store existing access permissions for 'OneDriveSetup.exe' in mounted temporary OS image" -Severity 1
                $OSImageOneDriveSetupFile = Join-Path -Path $MountOSImage -ChildPath "Windows\SysWOW64\OneDriveSetup.exe"
                $OSImageOneDriveSetupAccess = Get-NTFSAccess -Path $OSImageOneDriveSetupFile -Verbose:$false -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to temporarily store existing access permissions for 'OneDriveSetup.exe' in mounted temporary OS image. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }

            try {
                # Change access for BUILTIN\Administrators to FullControl
                Write-CMLogEntry -Value " - Attempting to add access for 'BUILTIN\Administrators' with 'FullControl' on 'OneDriveSetup.exe' in mounted temporary OS image" -Severity 1
                Add-NTFSAccess -Path $OSImageOneDriveSetupFile -Account "BUILTIN\Administrators" -AccessRights "FullControl" -AccessType "Allow" -Verbose:$false -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to add access for 'BUILTIN\Administrators' with 'FullControl' on 'OneDriveSetup.exe' in mounted temporary OS image. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }

            try {
                # Copy OneDriveSetup.exe from servicing location to mounted temporary OS image
                Write-CMLogEntry -Value " - Attempting to replace existing 'OneDriveSetup.exe' with latest version previously downloaded in Updates root folder" -Severity 1
                $UpdatesOneDriveSetupFile = Join-Path -Path $UpdateFilesRoot -ChildPath "OneDriveSetup.exe"
                Copy-Item -Path $UpdatesOneDriveSetupFile -Destination (Split-Path -Path $OSImageOneDriveSetupFile -Parent) -Verbose:$false -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to replace existing 'OneDriveSetup.exe' in mounted temporary OS image. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }

            try {
                # Restore access for BUILTIN\Administrators
                Write-CMLogEntry -Value " - Attempting to restore access permissions for 'BUILTIN\Administrators' account for the 'OneDriveSetup.exe' file in mounted temporary OS image" -Severity 1
                Remove-NTFSAccess -Path $OSImageOneDriveSetupFile -Account "BUILTIN\Administrators" -AccessRights "FullControl" -AccessType "Allow" -Verbose:$false -ErrorAction Stop
                Add-NTFSAccess -Path $OSImageOneDriveSetupFile -Account "BUILTIN\Administrators" -AccessRights "ReadAndExecute", "Synchronize" -AccessType "Allow" -Verbose:$false -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to restore access permissions for 'BUILTIN\Administrators' account. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
        else {
            Write-CMLogEntry -Value " - SkipOneDriveSetup variable set to True, skipping OneDrive Setup servicing" -Severity 2
        }
    }
    
    function New-RootFolderRequired {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the name of the root folder that will be created in the OSMediaFilesRoot location.")]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        switch ($Name) {
            "Source" {
                if (-not(Test-Path -Path (Join-Path -Path $OSMediaFilesRoot -ChildPath $Name))) {
                    Write-CMLogEntry -Value " - Failed to locate required Source root folder in: $($OSMediaFilesRoot)" -Severity 3
                    
                    # Throw terminating error
                    $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                    $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                }
            }
            default {
                if (-not(Test-Path -Path (Join-Path -Path $OSMediaFilesRoot -ChildPath $Name))) {
                    New-Item -Path $OSMediaFilesRoot -Name $Name -ItemType Directory -Force | Out-Null
                    Write-CMLogEntry -Value " - Successfully created the '$($Name)' root folder in in: $($OSMediaFilesRoot)" -Severity 1
                }
            }
        }
    }

    function New-SubFolderRequired {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the name of the root folder that will be used as the parent for the subfolder.")]
            [ValidateNotNullOrEmpty()]
            [string]$RootFolderName,

            [parameter(Mandatory=$true, HelpMessage="Specify the name of the sub folder that will be created in the specified root folder location.")]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        # Construct variable to contain the path to the subfolder
        $RootFolderPath = Join-Path -Path $OSMediaFilesRoot -ChildPath $RootFolderName
        $NewVariable = New-Variable -Name (-join($RootFolderName, $Name)) -Value (Join-Path -Path $RootFolderPath -ChildPath $Name) -Force -PassThru -Scope "Global"

        # Create subfolder if not exists
        if (-not(Test-Path -Path $NewVariable.Value)) {
            New-Item -Path $RootFolderPath -Name $Name -ItemType Directory -Force | Out-Null
            Write-CMLogEntry -Value " - Successfully created the '$($Name)' folder in: $(Split-Path -Path $NewVariable.Value -Parent)" -Severity 1
        }
    }

    function New-SubFolderOptional {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the full path of the sub folder that should be created.")]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [parameter(Mandatory=$true, HelpMessage="Specify the name of the sub folder.")]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        # Create subfolder if not exists
        if (-not(Test-Path -Path $Path)) {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-CMLogEntry -Value " - Successfully created the '$($Name)' folder in: $(Split-Path -Path $Path -Parent)" -Severity 1
        }
    }    

    function Test-ProductCategorySubscribedState {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the product category to be validated if it's subscribed too in the Software Update Point configuration.")]
            [ValidateNotNullOrEmpty()]
            [string]$Product
        )
        try {
            $CurrentProductCategory = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_UpdateCategoryInstance -ComputerName $SiteServer -Filter "LocalizedCategoryInstanceName like '$($Product)'" -ErrorAction Stop
            if ($CurrentProductCategory.IsSubscribed -eq $true) {
                return $true
            }
            else {
                return $false
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to validate that the $($Product) product is enabled in the Software Update Point component configuration. Error message: $($_.Exception.Message)" -Severity 3
            return $false
        }
    }

    function Remove-UpdateContentFiles {
        # Attempt to cleanup any existing update item content files
        $UpdateItemContentFiles = Get-ChildItem -Path $UpdateFilesRoot -Recurse -ErrorAction Stop | Where-Object { ($_.Extension -like ".exe") -or ($_.Extension -like ".cab") }
        if ($UpdateItemContentFiles -ne $null) {
            foreach ($UpdateItemContentFile in $UpdateItemContentFiles) {
                Write-CMLogEntry -Value " - Attempting to remove existing update item content file: $($UpdateItemContentFile.Name)" -Severity 1
                Remove-Item -Path $UpdateItemContentFile.FullName -Force -ErrorAction Stop
            }
        }

        if ($Script:PSBoundParameters["IncludeDynamicUpdates"]) {
            # Attempt to cleanup any existing dynamic update setup update content files
            $DUSUContentFiles = Get-ChildItem -Path $DUSUDownloadPath -Recurse -Filter "*.cab" -ErrorAction SilentlyContinue
            if ($DUSUContentFiles -ne $null) {
                foreach ($DUSUContentFile in $DUSUContentFiles) {
                    Write-CMLogEntry -Value " - Attempting to remove existing dynamic update setup update file: $($DUSUContentFile.Name)" -Severity 1
                    Remove-Item -Path $DUSUContentFile.FullName -Force -ErrorAction Stop
                }
            }

            # Attempt to cleanup any existing dynamic update component update content files
            $DUCUContentFiles = Get-ChildItem -Path $DUCUDownloadPath -Recurse -Filter "*.cab" -ErrorAction SilentlyContinue
            if ($DUCUContentFiles -ne $null) {
                foreach ($DUCUContentFile in $DUCUContentFiles) {
                    Write-CMLogEntry -Value " - Attempting to remove existing dynamic update component update file: $($DUCUContentFile.Name)" -Severity 1
                    Remove-Item -Path $DUCUContentFile.FullName -Force -ErrorAction Stop
                }
            }        

            # Remove extracted Dynamic Updates setup update files
            $DUSUExtractedFiles = Get-ChildItem -Path $DUSUExtractPath -Recurse -ErrorAction SilentlyContinue
            if ($DUSUExtractedFiles -ne $null) {
                Write-CMLogEntry -Value " - Attempting to cleanup existing extracted dynamic update setup update files in: $($DUSUExtractPath)" -Severity 1
                Remove-Item -Path $DUSUExtractPath -Force -Recurse -ErrorAction Stop
            }
        }
    }

    function Test-SourceFiles {
        # Validate specified OS media source files path contains required files
        $SourceFilesList = @("install.wim", "boot.wim")
        foreach ($SourceFile in $SourceFilesList) {
            $SourceFilePath = Join-Path -Path $OSMediaSourcePath -ChildPath "sources\$($SourceFile)"
            if (-not(Test-Path -Path $SourceFilePath)) {
                Write-CMLogEntry -Value " - Unable to locate '$($SourceFile)' file from specified OS media file location: $($OSMediaSourcePath)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
    }

    function Save-UpdateContent {
        $UpdateItemTypeList = @("Cumulative Update", "Servicing Stack Update" , "Adobe Flash Player", ".NET Framework")
        foreach ($UpdateItemType in $UpdateItemTypeList) {
            $Invocation = Invoke-MSUpdateItemDownload -FilePath $UpdateFilesRoot -UpdateType $UpdateItemType
            switch ($Invocation) {
                0 {
                    Write-CMLogEntry -Value " - Successfully downloaded update item content file for update type: $($UpdateItemType)" -Severity 1
                }
                1 {
                    Write-CMLogEntry -Value " - Failed to download update item content file for update type: $($UpdateItemType)" -Severity 3

                    # Throw terminating error
                    $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                    $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                }
                2 {
                    switch ($UpdateItemType) {
                        "Adobe Flash Player" {
                            Write-CMLogEntry -Value " - Failed to locate update item content file for update type, will proceed and mark '$($UpdateItemType)' for skiplist" -Severity 2
                            $Script:SkipAdobeFlashPlayerUpdate = $true
                        }
                        "Servicing Stack Update" {
                            Write-CMLogEntry -Value " - Failed to locate update item content file for update type, will proceed and mark '$($UpdateItemType)' for skiplist" -Severity 2
                            $Script:SkipServicingStackUpdate = $true
                        }
                        ".NET Framework" {
                            Write-CMLogEntry -Value " - Failed to locate update item content file for update type, will proceed and mark '$($UpdateItemType)' for skiplist" -Severity 2
                            $Script:SkipNETFrameworkUpdate = $true
                        }
                        "Cumulative Update" {
                            Write-CMLogEntry -Value " - Failed to locate update item content file for update type '$($UpdateItemType)', don't allow script execution to continue" -Severity 3

                            # Throw terminating error
                            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                        }
                    }
                }
            }
        }        
    }

    function Save-LanguageFeaturesContent {
        try {
            # Mount the language features ISO media
            Write-CMLogEntry -Value " - Attempting to mount the language features media ISO: $($LanguageFeaturesMediaFile)" -Severity 1
            $LanguageFeaturesMediaMount = Mount-DiskImage -ImagePath $LanguageFeaturesMediaFile -ErrorAction Stop -Verbose:$false -PassThru
            $LanguageFeaturesMediaMountVolume = $LanguageFeaturesMediaMount | Get-Volume -ErrorAction Stop -Verbose:$false | Select-Object -ExpandProperty DriveLetter
            $LanguageFeaturesMediaMountDriveLetter = -join($LanguageFeaturesMediaMountVolume, ":")
            Write-CMLogEntry -Value " - Language features media was mounted with drive letter: $($LanguageFeaturesMediaMountDriveLetter)" -Severity 1

            try {
                if ($LanguageFeaturesMediaMountDriveLetter -ne $null) {
                    # Process each specified language pack region tag and language feature type and copy related language features to servicing folder
                    $LPRegionTags = $LPRegionTag -join "|"
                    $LanguageFeaturesTypes = $LanguageFeaturesType -join "|"
                    $LanguageFeaturesPackageItems = Get-ChildItem -Path $LanguageFeaturesMediaMountDriveLetter -Recurse -Filter "*.cab" -ErrorAction Stop | Where-Object { ($_.Name -match "Microsoft-Windows-LanguageFeatures") -and ($_.Name -match $LPRegionTags) -and ($_.Name -match $LanguageFeaturesTypes) }
                    if ($LanguageFeaturesPackageItems -ne $null) {
                        foreach ($LanguageFeaturePackageItem in $LanguageFeaturesPackageItems) {
                            try {
                                Write-CMLogEntry -Value " - Copying language feature content file to servicing location: $($LanguageFeaturePackageItem.Name)" -Severity 1
                                Copy-Item -Path $LanguageFeaturePackageItem.FullName -Destination (Join-Path -Path $LPFeatureFilesRoot -ChildPath $LanguageFeaturePackageItem.Name) -Force -ErrorAction Stop -Verbose:$false
                            }
                            catch [System.Exception] {
                                Write-CMLogEntry -Value " - Failed to copy language feature content file '$($LanguageFeaturePackageItem.Name)' from mounted Language Features ISO media file. Error message: $($_.Exception.Message)" -Severity 3
                            }
                        }
                    }
                    else {
                        Write-CMLogEntry -Value " - Unable to locate any language features from the specified input parameters, please refine parameter input" -Severity 2
                    }
                }
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to determine Language Features content location in mounted Language Features ISO media file. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to mount specified Language Features ISO media file. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Save-LanguagePackContent {
        try {
            # Mount the language pack ISO media
            Write-CMLogEntry -Value " - Attempting to mount the language pack media ISO: $($LPMediaFile)" -Severity 1
            $LPMediaMount = Mount-DiskImage -ImagePath $LPMediaFile -ErrorAction Stop -Verbose:$false -PassThru
            $LPMediaMountVolume = $LPMediaMount | Get-Volume -ErrorAction Stop -Verbose:$false | Select-Object -ExpandProperty DriveLetter
            $LPMediaMountDriveLetter = -join($LPMediaMountVolume, ":")
            Write-CMLogEntry -Value " - Language pack media was mounted with drive letter: $($LPMediaMountDriveLetter)" -Severity 1

            try {
                if ($LPMediaMountDriveLetter -ne $null) {
                    # Process each specified language pack region tag and copy base language packs to servicing folder
                    $LPBaseContentRoot = Join-Path -Path $LPMediaMountDriveLetter -ChildPath $OSArchitecture
                    $LPRegionTags = $LPRegionTag -join "|"
                    $LPBasePackageItems = Get-ChildItem -Path $LPBaseContentRoot -Recurse -Filter "*.cab" -ErrorAction Stop | Where-Object { ($_.Name -match $OSArchitecture) -and ($_.Name -notmatch "Interface") -and ($_.Name -match $LPRegionTags) }
                    if ($LPBasePackageItems -ne $null) {
                        foreach ($LPBasePackageItem in $LPBasePackageItems) {
                            try {
                                Write-CMLogEntry -Value " - Copying base language pack content file to servicing location: $($LPBasePackageItem.Name)" -Severity 1
                                Copy-Item -Path $LPBasePackageItem.FullName -Destination (Join-Path -Path $LPBaseFilesRoot -ChildPath $LPBasePackageItem.Name) -Force -ErrorAction Stop -Verbose:$false
                            }
                            catch [System.Exception] {
                                Write-CMLogEntry -Value " - Failed to copy language pack content file '$($LPBasePackageItem.Name)' from mounted Language Pack ISO media file. Error message: $($_.Exception.Message)" -Severity 3
                            }
                        }
                    }
                    else {
                        Write-CMLogEntry -Value " - Unable to locate any base language packs from the specified input parameters, please refine parameter input" -Severity 2
                    }

                    # Copy Local Experience Packs to servicing location, only if specified on command line
                    if ($Script:PSBoundParameters["IncludeLocalExperiencePack"]) {
                        Write-CMLogEntry -Value " - Local experience packs switch was passed on command line, will attempt to copy LXP packages to servicing location" -Severity 1

                        # Process each specified language pack region tag, match against local experience packs on ISO media and copy packages to servicing folder
                        $LPLXPContentRoot = Join-Path -Path $LPMediaMountDriveLetter -ChildPath "LocalExperiencePack"
                        foreach ($LPLXPPackageItem in (Get-ChildItem -Path $LPLXPContentRoot -Recurse -ErrorAction Stop -Directory | Where-Object { $_.Name -match $LPRegionTags })) {
                            try {
                                Write-CMLogEntry -Value " - Preparing local experience pack content files for copy operation from path: $($LPLXPPackageItem.FullName)" -Severity 1

                                # Create region tag sub-folder
                                $LPLXPRegionTagFolder = Join-Path -Path $LPLXPFilesRoot -ChildPath $LPLXPPackageItem.Name
                                if (-not(Test-Path -Path $LPLXPRegionTagFolder)) {
                                    New-Item -Path $LPLXPRegionTagFolder -ItemType Directory -ErrorAction Stop | Out-Null
                                }

                                # Copy each file in region tab subfolder to servicing location
                                $LPLXPPackageItemFiles = Get-ChildItem -Path $LPLXPPackageItem.FullName -ErrorAction Stop | Where-Object { $_.Extension -in ".appx", ".xml" }
                                if ($LPLXPPackageItemFiles -ne $null) {
                                    foreach ($LPLXPPackageItemFile in $LPLXPPackageItemFiles) {
                                        Write-CMLogEntry -Value " - Copying local experience pack content file to servicing location: $($LPLXPPackageItemFile.Name)" -Severity 1
                                        Copy-Item -Path $LPLXPPackageItemFile.FullName -Destination (Join-Path -Path $LPLXPRegionTagFolder -ChildPath $LPLXPPackageItemFile.Name) -Force -ErrorAction Stop -Verbose:$false
                                    }
                                }
                                else {
                                    Write-CMLogEntry -Value " - Unable to locate any local experience packs from the specified input parameters" -Severity 2
                                }
                            }
                            catch [System.Exception] {
                                Write-CMLogEntry -Value " - Failed to copy local experience pack content files for region tag '$($LPLXPPackageItem.Name)' from mounted Language Pack ISO media file. Error message: $($_.Exception.Message)" -Severity 3
                            }
                        }
                    }
                }

                try {
                    Write-CMLogEntry -Value " - Attempting to dismount the language pack media ISO from drive letter: $($LPMediaMountDriveLetter)" -Severity 1
                    Dismount-DiskImage -InputObject $LPMediaMount -ErrorAction Stop
                }
                catch [System.Exception] {
                    Write-CMLogEntry -Value " - Failed to dismount the Language Pack ISO media file. Error message: $($_.Exception.Message)" -Severity 3
                }
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to determine language pack content location in mounted Language Pack ISO media file. Error message: $($_.Exception.Message)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to mount specified Language Pack ISO media file. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Save-DynamicUpdatesContent {
        # Construct a list for dynamic update content objects
        $DynamicUpdatesList = New-Object -TypeName System.Collections.ArrayList
            
        # Get all dynamic update objects
        Write-CMLogEntry -Value " - Attempting to retrieve dynamic update objects from SMS Provider" -Severity 1
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
                        Write-CMLogEntry -Value " - Downloading dynamic update content '$($DynamicUpdateItem.FileName)' from: $($DynamicUpdateItem.SourceURL)" -Severity 1

                        try {
                            Start-DownloadFile -URL $DynamicUpdateItem.SourceURL -Path $DynamicUpdateDownloadLocation -Name $DynamicUpdateItemFileName -ErrorAction Stop
                            Write-CMLogEntry -Value " - Completed download successfully and renamed file to: $($DynamicUpdateItemFileName)" -Severity 1
                        }
                        catch [System.Exception] {
                            Write-CMLogEntry -Value $_.Exception.Message -Severity 3

                            # Throw terminating error
                            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                        }                        

                        # Expand the contents of the selected DUSU update
                        if ($DynamicUpdateItem.FileType -like "SetupUpdate") {
                            # Create dynamic update content specific folder in extract path
                            $DUSUExtractPathFolderName = Join-Path -Path $DUSUExtractPath -ChildPath $DynamicUpdateItemFileName.Replace(".cab", "")
                            if (-not(Test-Path -Path $DUSUExtractPathFolderName)) {
                                New-Item -Path $DUSUExtractPathFolderName -ItemType Directory -Force | Out-Null
                            }

                            # Invoke expand.exe for the expansion of the cab file
                            Write-CMLogEntry -Value " - Expanding dynamic update content to: $($DUSUExtractPathFolderName)" -Severity 1
                            $ReturnValue = Invoke-Executable -FilePath "expand.exe" -Arguments "$(Join-Path -Path $DynamicUpdateDownloadLocation -ChildPath $DynamicUpdateItemFileName) -F:* $($DUSUExtractPathFolderName)"
                            if ($ReturnValue -ne 0) {
                                Write-CMLogEntry -Value " - Failed to expand Dynamic Updates setup update files" -Severity 3

                                # Throw terminating error
                                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                            }
                        }
                    }
                }
            }
        }
        else {
            Write-CMLogEntry -Value " - Query for dynamic updates returned empty" -Severity 1
        }        
    }

    function Test-LanguageFeaturesContent {
        # Validate Language Features content files have successfully been copied over to servicing location
        if (Test-Path -Path $LPFeatureFilesRoot) {
            Write-CMLogEntry -Value " - Located the Language Features content folder" -Severity 1
            $LanguageFeatureFilesItems = Get-ChildItem -Path $LPFeatureFilesRoot -Recurse -Filter "*.cab"
            if (-not(($LanguageFeatureFilesItems | Measure-Object).Count -ge 1)) {
                Write-CMLogEntry -Value " - Unable to detect any Language Feature content files in servicing location, setting variable to skip processing of Language Features" -Severity 2
                $Script:SkipLanguageFeatures = $true
            }
            else {
                Write-CMLogEntry -Value " - Detected '$(($LanguageFeatureFilesItems).Count)' required Language Feature content files for injection in servicing location: $($LPFeatureFilesRoot)" -Severity 1
            }
        }
    }

    function Test-LanguagePackContent {
        # Validate Language Packs base content files have successfully been copied over to servicing location
        if (Test-Path -Path $LPBaseFilesRoot) {
            Write-CMLogEntry -Value " - Located the Language Pack base content folder" -Severity 1
            $LPBaseFilesRootItems = Get-ChildItem -Path $LPBaseFilesRoot -Recurse -Filter "*.cab"
            if (-not(($LPBaseFilesRootItems | Measure-Object).Count -ge 1)) {
                Write-CMLogEntry -Value " - Unable to detect any Language Pack base content files in servicing location, setting variable to skip processing of Language Packs" -Severity 2
                $Script:SkipLanguagePack = $true
            }
            else {
                Write-CMLogEntry -Value " - Detected '$(($LPBaseFilesRootItems).Count)' required Language Pack base content files for injection in servicing location: $($LPBaseFilesRoot)" -Severity 1
            }
        }

        if ($Script:PSBoundParameters["IncludeLocalExperiencePack"]) {
            Write-CMLogEntry -Value " - Local experience packs switch was passed on command line, validating LXP packages existence in servicing location" -Severity 1
            if (Test-Path -Path $LPLXPFilesRoot) {
                Write-CMLogEntry -Value " - Located the Language Pack LXP content folder" -Severity 1
                $LPLXPRegionTagFolders = Get-ChildItem -Path $LPLXPFilesRoot
                if ($LPLXPRegionTagFolders -ne $null) {
                    Write-CMLogEntry -Value " - Detect Language Pack LXP region tag folders present in servicing location" -Severity 1
                    foreach ($LPLXPRegionTagFolder in $LPLXPRegionTagFolders) {
                        Write-CMLogEntry -Value " - Processing current Language Pack LXP region tag folder '$($LPLXPRegionTagFolder.Name)' with path: $($LPLXPRegionTagFolder.FullName)" -Severity 1
                        if (-not((Get-ChildItem -Path $LPLXPRegionTagFolder.FullName -Recurse | Where-Object { ($_.Extension -like ".appx") -or ($_.Extension -like ".xml") }) | Measure-Object).Count -eq 2) {
                            Write-CMLogEntry -Value " - Unable to validate current Language Pack LXP content files, ensure both .appx and .xml files are present in folder" -Severity 3
                        }
                        else {
                            Write-CMLogEntry -Value " - Validated Language Pack LXP region tag with required content files, adding to allow list" -Severity 1
                            $LPLXPCustomItem = [PSCustomObject]@{
                                RegionTag = $LPLXPRegionTagFolder.Name
                                Path = $LPLXPRegionTagFolder.FullName
                            }
                            $Script:LPLXPAllowList.Add($LPLXPCustomItem) | Out-Null
                        }
                    }
                }
                else {
                    Write-CMLogEntry -Value " - Language Pack LXP servicing location was empty, setting variable to skip processing of Language Pack LXPs" -Severity 1
                    $Script:SkipLanguagePackLXP = $true
                }
            }
        }
    }

    function Get-UpdateFiles {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Type of the update files to retrieve the full path too.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("CumulativeUpdate", "ServicingStack", "NETFramework", "AdobeFlash")]
            [string]$UpdateType
        )
        # Determine the update type filter to apply when retrieving update files
        $BreakOperation = $false
        switch ($UpdateType) {
            "CumulativeUpdate" {
                $UpdateFilter = "*CumulativeUpdate*.cab"
                $BreakOperation = $true
            }
            "ServicingStack" {
                $UpdateFilter = "*ServicingStackUpdate*.cab"
            }
            "NETFramework" {
                $UpdateFilter = "*NETFramework*.cab"
            }
            "AdobeFlash" {
                $UpdateFilter = "*AdobeFlashPlayer*.cab"
            }
        }

        # Retrieve update files based on update type filter and return full path property to all valid update files
        switch ($UpdateType) {
            "NETFramework" {
                $UpdateFiles = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter $UpdateFilter | Sort-Object -Descending -Property $_.CreationTime | Select-Object -ExpandProperty FullName
                if ($UpdateFiles -ne $null) {
                    $UpdateFilesCount = ($UpdateFiles | Measure-Object).Count
                    foreach ($UpdateFile in $UpdateFiles) {
                        Write-CMLogEntry -Value " - Selected the '$($UpdateType)' content cabinet file: $($UpdateFile)" -Severity 1
                        Write-Output -InputObject $UpdateFile
                    }
                }
                else {
                    Write-CMLogEntry -Value " - Failed to locate required content cabinet file for '$($UpdateType)' type, allowing script execution to continue" -Severity 2
                }
            }
            default {
                $UpdateFile = Get-ChildItem -Path $UpdateFilesRoot -Recurse -Filter $UpdateFilter | Sort-Object -Descending -Property $_.CreationTime | Select-Object -First 1 -ExpandProperty FullName
                if ($UpdateFile -ne $null) {
                    Write-CMLogEntry -Value " - Selected the '$($UpdateType)' content cabinet file: $($UpdateFile)" -Severity 1
                    return $UpdateFile
                }
                else {
                    if ($BreakOperation -eq $true) {
                        Write-CMLogEntry -Value " - Failed to locate required content cabinet file for '$($UpdateType)' type, breaking operation" -Severity 3

                        # Throw terminating error
                        $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                    }
                    else {
                        Write-CMLogEntry -Value " - Failed to locate required content cabinet file for '$($UpdateType)' type, allowing script execution to continue" -Severity 2
                    }
                }
            }
        }
    }

    function Get-DynamicUpdateComponentFiles {
        # Validate Dynamic Updates DUCU folder contains required files
        $UpdatesDUCUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUCU"
        if (Test-Path -Path $UpdatesDUCUFolderPath) {
            Write-CMLogEntry -Value " - Located the Dynamic Updates required 'DUCU' folder" -Severity 1
            if (-not((Get-ChildItem -Path $UpdatesDUCUFolderPath -Recurse -Filter "*.cab" | Measure-Object).Count -ge 1)) {
                Write-CMLogEntry -Value " - Required Dynamic Updates 'DUCU' folder is empty, setting variable to skip processing of DUCU files" -Severity 2
                $Script:SkipDUCUPatch = $true
            }
            else {
                # Determine Dynamic Updates files to be applied
                $UpdatesDUCUFilePaths = Get-ChildItem -Path $UpdatesDUCUFolderPath -Recurse -Filter "*.cab" | Sort-Object -Property $_.Name | Select-Object -ExpandProperty FullName
                if ($UpdatesDUCUFilePaths -ne $null) {
                    foreach ($UpdatesDUCUFilePath in $UpdatesDUCUFilePaths) {
                        Write-CMLogEntry -Value " - Found the following Dynamic Updates file in the 'DUCU' folder: $($UpdatesDUCUFilePath)" -Severity 1
                        Write-Output -InputObject $UpdatesDUCUFilePath
                    }
                }
            }
        }
        else {
            Write-CMLogEntry -Value " - Unable to locate required Dynamic Updates 'DUCU' subfolder in the update files root location" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Get-DynamicUpdateSetupFiles {
        # Validate Dynamic Updates DUSU folder contains required files
        $UpdatesDUSUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUSU"
        if (Test-Path -Path $UpdatesDUSUFolderPath) {
            Write-CMLogEntry -Value " - Located the Dynamic Updates required 'DUSU' folder" -Severity 1
            if (-not((Get-ChildItem -Path $UpdatesDUSUFolderPath -Recurse -Filter "*.cab" | Measure-Object).Count -ge 1)) {
                Write-CMLogEntry -Value " - Required Dynamic Updates 'DUSU' folder is empty, setting variable to skip processing of DUSU files" -Severity 2
                $Script:SkipDUSUPatch = $true
            }
            else {
                # Determine Dynamic Updates files to be applied
                $UpdatesDUSUFilePath = Get-ChildItem -Path $UpdatesDUSUFolderPath -Recurse -Filter "*.cab" | Sort-Object -Property $_.Name | Select-Object -First 1 -ExpandProperty FullName
                if ($UpdatesDUSUFilePath -ne $null) {
                    Write-CMLogEntry -Value " - Selected the most recent Dynamic Update (DUSU) file: $($UpdatesDUSUFilePath)" -Severity 1
                }
            }
        }
        else {
            Write-CMLogEntry -Value " - Unable to locate required Dynamic Updates 'DUSU' subfolder in the update files root location" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Copy-SourceFiles {
        try {
            # Copy the OS media source files to Image folder
            Write-CMLogEntry -Value " - Copying OS media source files into Image root folder: $($OSMediaImagePath)" -Severity 1
            Copy-Item -Path "$($OSMediaSourcePath)\*" -Destination $OSMediaImagePath -Recurse -Force -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to copy OS media source files to Image root folder. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Remove-ImageFiles {
        try {
            # Remove all files and folder in the Image root folder if exist
            if (Test-Path -Path $OSMediaImagePath) {
                $OSMediaImageItems = Get-ChildItem -Path $OSMediaImagePath -ErrorAction Stop
                $OSMediaImageItemsCount = ($OSMediaImageItems | Measure-Object).Count
                if ($OSMediaImageItemsCount -ge 1) {
                    Write-CMLogEntry -Value " - Detected existing source files in Image root folder, attempting to cleanup before OS image servicing can be initiated" -Severity 1
                    Get-ChildItem -Path $OSMediaImagePath -ErrorAction Stop | Remove-Item -Force -Recurse -Confirm:$false -ErrorAction Stop
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to cleanup Image root folder. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Invoke-ImageBackup {
        try {
            if ($Script:PSBoundParameters["SkipBackup"]) {
                Write-CMLogEntry -Value " - Skipping backup of OS image files in Image root folder since SkipBackup parameter was specified" -Severity 1
            }
            else {
                if (Test-Path -Path $OSMediaImagePath) {
                    if ((Get-ChildItem -Path $OSMediaImagePath | Measure-Object).Count -ge 1) {
                        # Backup complete set of OS image source files
                        $OSMediaImageBackupPath = Join-Path -Path $BackupPathRoot -ChildPath "$((Get-Date).ToString("yyyy-MM-dd-HHmm"))_Image"
                        Write-CMLogEntry -Value " - Backing up complete set of OS image source files from Image root folder into: $($OSMediaImageBackupPath)" -Severity 1
                        Copy-Item -Path $OSMediaImagePath -Destination $OSMediaImageBackupPath -Container -Recurse -Force -ErrorAction Stop
                    }
                    else {
                        Write-CMLogEntry -Value " - Unable to locate any files and folders in Image root folder, skipping backup" -Severity 1
                    }
                }
                else {
                    Write-CMLogEntry -Value " - Unable to detect Image root folder, skipping backup" -Severity 1
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to backup Image root folder. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Invoke-ImageBackupCleanup {
        if ($Script:PSBoundParameters["SkipBackup"]) {
            Write-CMLogEntry -Value " - SkipBackup switch was passed on the command line, will not attempt to cleanup any obsolete backup directories" -Severity 1
        }
        else {
            if (Test-Path -Path $BackupPathRoot) {
                $BackupFoldersList = New-Object -TypeName System.Collections.ArrayList
                $BackupFolderPaths = Get-ChildItem -Path $BackupPathRoot -Directory
                if ($BackupFolderPaths -ne $null) {
                    # Construct new custom object with full path and date time object of backup folder
                    foreach ($BackupFolderPath in $BackupFolderPaths) {
                        $PSObject = [PSCustomObject]@{
                            Name = $BackupFolderPath.Name
                            Path = $BackupFolderPath.FullName
                            DateTime = [System.Convert]::ToDateTime($BackupFolderPath.Name.Split("_")[0])
                        }
                        $BackupFoldersList.Add($PSObject) | Out-Null
                    }
            
                    # Remove all obsolete backup folders execpt the most recent one
                    $ObsoleteBackupFolders = $BackupFoldersList | Sort-Object -Property DateTime -Descending | Select-Object -Skip 1
                    foreach ($ObsoleteBackupFolder in $ObsoleteBackupFolders) {
                        try {
                            Write-CMLogEntry -Value " - Attempting to remove obsolete backup image folder with name: $($ObsoleteBackupFolder.Name)" -Severity 1
                            Remove-Item -Path $ObsoleteBackupFolder.Path -Recurse -Force -ErrorAction Stop
                        }
                        catch [System.Exception] {
                            Write-CMLogEntry -Value " - Failed to remove obsolete backup image folder '$($ObsoleteBackupFolder.Name)' from Backup directory. Error message: $($_.Exception.Message)" -Severity 3

                            # Throw terminating error
                            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                            $PSCmdlet.ThrowTerminatingError($ErrorRecord)            
                        }
                    }
                }
            }
        }
    }

    function Export-OSImage {
        try {
            # Export selected OS image edition from OS media files location to a temporary image
            Write-CMLogEntry -Value " - Exporting OS image from media source location to temporary OS image: $($Script:OSImageTempWim)" -Severity 1
            Export-WindowsImage -SourceImagePath $OSInstallWim -DestinationImagePath $OSImageTempWim -SourceName "Windows 10 $($OSEdition)" -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to export temporary OS image from media files. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Update-OSImage {
        try {
            # Export OS image to temporary location
            $NewOSImageWim = Join-Path -Path $MountTemp -ChildPath "install.wim"
            Write-CMLogEntry -Value " - Attempting to export OS edition Windows 10 $($OSEdition) to temporary location from file: $($OSImageTempWim)" -Severity 1
            Export-WindowsImage -SourceImagePath $OSImageTempWim -DestinationImagePath $NewOSImageWim -SourceName "Windows 10 $($OSEdition)" -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to export serviced OS image with edition '$($OSEdition)'. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        try {
            # Remove install.wim from OS media source file location
            Write-CMLogEntry -Value " - Attempting to remove install.wim from OS media source files location" -Severity 1
            Remove-Item -Path (Join-Path -Path $OSMediaImagePath -ChildPath "sources\install.wim") -Force -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to existing install.wim from OS media source file location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        try {
            # Replace serviced OS image wim file with existing wim file
            Write-CMLogEntry -Value " - Attempting to replace serviced install.wim from temporary location to OS media source files location" -Severity 1
            Move-Item -Path $NewOSImageWim -Destination (Join-Path -Path $OSMediaImagePath -ChildPath "sources\install.wim") -Force -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to replace serviced install.wim from temporary location to OS media source files location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Dismount-OSImage {
        try {
            # Dismount the OS image
            Write-CMLogEntry -Value " - Attempting to dismount and commit the mounted temporary OS image, this operation could take some time" -Severity 1
            Dismount-WindowsImage -Path $MountOSImage -Save -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to dismount temporary OS image from mounted location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Mount-OSImage {
        try {
            # Mount the temporary OS image
            Write-CMLogEntry -Value " - Mounting temporary OS image file: $($OSImageTempWim)" -Severity 1
            Mount-WindowsImage -ImagePath $OSImageTempWim -Index 1 -Path $MountOSImage -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to mount temporary OS image. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Add-OSImagePackage {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the update type that will be injected into OS image.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("Cumulative Update", "Servicing Stack Update", ".NET Framework", "Adobe Flash", "Dynamic Update Component Update")]
            [string]$UpdateType,

            [parameter(Mandatory=$true, HelpMessage="Specify the full path of the package that will be injected into OS image.")]
            [ValidateNotNullOrEmpty()]
            [string[]]$PackagePath
        )
        # Attempt to apply all required updates for OS image
        Write-CMLogEntry -Value " - Attempting to apply required patch to OS image for: $($UpdateType)" -Severity 1

        try {
            $PackagePathItemCount = 0
            $PackagePathCount = ($PackagePath | Measure-Object).Count
            foreach ($PackagePathItem in $PackagePath) {
                Write-CMLogEntry -Value " - Currently processing package: $($PackagePathItem)" -Severity 1
                $PackagePathItemCount++
                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountOSImage)"" /Add-Package /PackagePath:""$($PackagePathItem)""" -ErrorAction Stop

                if ($ReturnValue -ne 0) {
                    Write-CMLogEntry -Value " - Failed to apply '$($UpdateType)' package to OS image, see DISM.log for more details" -Severity 3

                    # Throw terminating error
                    $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                    $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                }

                if ($PackagePathItemCount -eq $PackagePathCount) {
                    Write-CMLogEntry -Value " - Successfully applied $($PackagePathItemCount) / $($PackagePathCount) packages to OS Image" -Severity 1
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to apply '$($UpdateType)' package to OS image. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }        
    }

    function Add-WinREImagePackage {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the update type that will be injected into WinRE image.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("Cumulative Update", "Servicing Stack Update")]
            [string]$UpdateType,

            [parameter(Mandatory=$true, HelpMessage="Specify the full path of the package that will be injected into WinRE image.")]
            [ValidateNotNullOrEmpty()]
            [string[]]$PackagePath
        )
        # Attempt to apply all required updates for WinRE image
        Write-CMLogEntry -Value " - Attempting to apply required patch to WinRE image for: $($UpdateType)" -Severity 1

        try {
            $PackagePathItemCount = 0
            $PackagePathCount = ($PackagePath | Measure-Object).Count
            foreach ($PackagePathItem in $PackagePath) {
                Write-CMLogEntry -Value " - Currently processing package: $($PackagePathItem)" -Severity 1
                $PackagePathItemCount++
                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountWinRE)"" /Add-Package /PackagePath:""$($PackagePathItem)""" -ErrorAction Stop

                if ($ReturnValue -ne 0) {
                    Write-CMLogEntry -Value " - Failed to apply '$($UpdateType)' package to WinRE image, see DISM.log for more details" -Severity 3

                    # Throw terminating error
                    $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                    $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                }

                if ($PackagePathItemCount -eq $PackagePathCount) {
                    Write-CMLogEntry -Value " - Successfully applied $($PackagePathItemCount) / $($PackagePathCount) packages to WinRE Image" -Severity 1
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to apply '$($UpdateType)' package to WinRE image. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Add-BootImagePackage {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the update type that will be injected into boot image.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("Cumulative Update", "Servicing Stack Update")]
            [string]$UpdateType,

            [parameter(Mandatory=$true, HelpMessage="Specify the full path of the package that will be injected into boot image.")]
            [ValidateNotNullOrEmpty()]
            [string[]]$PackagePath
        )
        # Attempt to apply all required updates for boot image
        Write-CMLogEntry -Value " - Attempting to apply required patch to boot image for: $($UpdateType)" -Severity 1

        try {
            $PackagePathItemCount = 0
            $PackagePathCount = ($PackagePath | Measure-Object).Count
            foreach ($PackagePathItem in $PackagePath) {
                Write-CMLogEntry -Value " - Currently processing package: $($PackagePathItem)" -Severity 1
                $PackagePathItemCount++
                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountBootImage)"" /Add-Package /PackagePath:""$($PackagePathItem)""" -ErrorAction Stop

                if ($ReturnValue -ne 0) {
                    Write-CMLogEntry -Value " - Failed to apply '$($UpdateType)' package to boot image, see DISM.log for more details" -Severity 3

                    # Throw terminating error
                    $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                    $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                }

                if ($PackagePathItemCount -eq $PackagePathCount) {
                    Write-CMLogEntry -Value " - Successfully applied $($PackagePathItemCount) / $($PackagePathCount) packages to boot Image" -Severity 1
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to apply '$($UpdateType)' package to boot image. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Add-OSImageLanguageFeature {
        if ($SkipLanguageFeatures -ne $true) {
            # Attempt to apply package for OS image: Language Features
            Write-CMLogEntry -Value " - Attempting to apply package to OS image for: Language Features" -Severity 1
            $LanguageFeaturesCount = 0
            $LanguageFeatureItems = Get-ChildItem -Path $LPFeatureFilesRoot
            $LanguageFeatureItemsCount = ($LanguageFeatureItems | Measure-Object).Count
            if ($LanguageFeatureItems -ne $null) {
                foreach ($LanguageFeatureItem in $LanguageFeatureItems) {
                    Write-CMLogEntry -Value " - Currently processing package: $($LanguageFeatureItem.Name)" -Severity 1
                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountOSImage)"" /Add-Package /PackagePath:""$($LanguageFeatureItem.FullName)"""

                    if ($ReturnValue -ne 0) {
                        Write-CMLogEntry -Value " - Failed to apply Language Feature package: $($LanguageFeatureItem.Name). See DISM.log for more details" -Severity 3

                        # Throw terminating error
                        $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                    }
                    else {
                        $LanguageFeaturesCount++
                    }
                }

                if ($LanguageFeaturesCount -eq $LanguageFeatureItemsCount) {
                    Write-CMLogEntry -Value " - Successfully added $($LanguageFeaturesCount) / $($LanguageFeatureItemsCount) base Language Features to OS Image" -Severity 1
                }
            }            
        }
    }

    function Add-OSImageLanguagePack {
        if ($SkipLanguagePack -ne $true) {
            # Attempt to apply package for OS image: Base Language Pack
            Write-CMLogEntry -Value " - Attempting to apply package to OS image for: Base Language Pack" -Severity 1
            $LPPackageCount = 0
            $LPBaseFilesRootItems = Get-ChildItem -Path $LPBaseFilesRoot
            $LPBaseFilesRootItemsCount = ($LPBaseFilesRootItems | Measure-Object).Count
            if ($LPBaseFilesRootItems -ne $null) {
                foreach ($LPBaseFilesRootItem in $LPBaseFilesRootItems) {
                    Write-CMLogEntry -Value " - Currently processing package: $($LPBaseFilesRootItem.Name)" -Severity 1
                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountOSImage)"" /Add-Package /PackagePath:""$($LPBaseFilesRootItem.FullName)"""

                    if ($ReturnValue -ne 0) {
                        Write-CMLogEntry -Value " - Failed to apply Language Pack base package: $($LPBaseFilesRootItem.Name). See DISM.log for more details" -Severity 3

                        # Throw terminating error
                        $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                    }
                    else {
                        $LPPackageCount++
                    }
                }

                if ($LPPackageCount -eq $LPBaseFilesRootItemsCount) {
                    Write-CMLogEntry -Value " - Successfully added $($LPPackageCount) / $($LPBaseFilesRootItemsCount) base language packs to OS Image" -Severity 1
                }
            }

            # Attempt to apply package for OS image: LXP Language Pack
            if ($Script:PSBoundParameters["IncludeLocalExperiencePack"]) {
                Write-CMLogEntry -Value " - Local experience packs switch was passed on command line, will attempt to apply LXP packages to OS image" -Severity 1
                if ($SkipLanguagePackLXP -ne $true) {
                    $LPLXPPackageCount = 0
                    if (($LPLXPAllowList | Measure-Object).Count -ge 1) {
                        foreach ($LPLXPItem in $LPLXPAllowList) {
                            $LPLXPItemPackage = Get-ChildItem -Path $LPLXPItem.Path -Filter "*.appx"
                            $LPLXPItemLicense = Get-ChildItem -Path $LPLXPItem.Path -Filter "*.xml"
                            Write-CMLogEntry -Value " - Currently processing package: $($LPLXPItemPackage.Name)" -Severity 1
                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountOSImage)"" /Add-ProvisionedAppxPackage /PackagePath:""$($LPLXPItemPackage.FullName)"" /LicensePath:""$($LPLXPItemLicense.FullName)"""

                            if ($ReturnValue -ne 0) {
                                Write-CMLogEntry -Value " - Failed to apply Language Pack LXP package: $($LPLXPItemPackage.Name). See DISM.log for more details" -Severity 3

                                # Throw terminating error
                                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                            }
                            else {
                                $LPLXPPackageCount++
                            }
                        }

                        if ($LPLXPPackageCount -eq $LPLXPAllowList.Count) {
                            Write-CMLogEntry -Value " - Successfully added $($LPLXPPackageCount) / $($LPLXPAllowList.Count) Language Pack LXPs to OS Image" -Severity 1
                        }
                    }
                }
                else {
                    Write-CMLogEntry -Value " - Skipping Language Pack LXPs due to missing content in servicing location" -Severity 1
                }
            }
        }
    }

    function Invoke-OSImageCleanup {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true, HelpMessage="Specify the image type that will be cleaned up.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("OS Image", "WinRE Image")]
            [string]$ImageType,

            [parameter(Mandatory=$false, HelpMessage="Perform a Reset base operation at the same time as cleaning components.")]
            [switch]$ResetBase
        )
        switch ($ImageType) {
            "OS Image" {
                $ImagePath = $MountOSImage
            }
            "WinRE Image" {
                $ImagePath = $MountWinRE
            }
        }

        if ($Script:PSBoundParameters["SkipComponentCleanup"]) {
            Write-CMLogEntry -Value " - Skipping cleanup of '$($ImageType)' components since SkipComponentCleanup parameter was specified" -Severity 1
        }
        else {
            # Dynamically build the arguments for dism based on parameter input
            if ($PSBoundParameters["ResetBase"]) {
                Write-CMLogEntry -Value " - Attempting to perform a component cleanup and reset base of $($ImageType), this operation could take some time" -Severity 1
                $DISMArguments = "/Image:""$($ImagePath)"" /Cleanup-Image /StartComponentCleanup /ResetBase"
            }
            else {
                Write-CMLogEntry -Value " - Attempting to perform a component cleanup of $($ImageType), this operation could take some time" -Severity 1
                $DISMArguments = "/Image:""$($ImagePath)"" /Cleanup-Image /StartComponentCleanup"
            }

            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments $DISMArguments

            if ($ReturnValue -ne 0) {
                Write-CMLogEntry -Value " - Failed to perform component cleanup operation and reset base of mounted temporary $($ImageType)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }
    }

    function Add-LegacyNetFramework {    
        # Attempt to apply .NET Framework 3.5.1 to OS image
        Write-CMLogEntry -Value " - Include .NET Framework 3.5.1 parameter was specified" -Severity 1
        $OSMediaSourcesSxsPath = Join-Path -Path $OSMediaImagePath -ChildPath "sources\sxs"
        Write-CMLogEntry -Value " - Attempting to apply .NET Framework 3.5.1 to OS image from SXS location: $($OSMediaSourcesSxsPath)" -Severity 1
        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountOSImage)"" /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:""$($OSMediaSourcesSxsPath)"""

        if ($ReturnValue -ne 0) {
            Write-CMLogEntry -Value " - Failed to apply .NET Framework 3.5.1 to mounted temporary OS image. See DISM.log for more details" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
        else {
            Write-CMLogEntry -Value " - Successfully applied .NET Framework 3.5.1 to mounted temporary OS image" -Severity 1
        }
    }

    function Remove-AppxProvisioningPackages {
        Write-CMLogEntry -Value " - Remove appx provisioned packages parameter was specified, proceeding to remove all packages except those specified in white list" -Severity 1

        try {
            # Retrieve existing appx provisioned apps in the mounted OS image
            Write-CMLogEntry -Value " - Attempting to retrieve provisioned appx packages in OS image" -Severity 1
            $AppxProvisionedPackagesList = Get-AppxProvisionedPackage -Path $MountOSImage -ErrorAction Stop -Verbose:$false

            # Loop through the list of provisioned appx packages
            foreach ($App in $AppxProvisionedPackagesList) {
                # Remove provisioned appx package if name not in white list
                if (($App.DisplayName -in $WhiteListedApps)) {
                    Write-CMLogEntry -Value " - Skipping excluded provisioned appx package: $($App.DisplayName)" -Severity 1
                }
                else {
                    try {
                        # Attempt to remove AppxProvisioningPackage
                        Write-CMLogEntry -Value " - Attempting to remove provisioned appx package from OS image: $($App.PackageName)" -Severity 1
                        Remove-AppxProvisionedPackage -PackageName $App.PackageName -Path $MountOSImage -ErrorAction Stop -Verbose:$false | Out-Null
                    }
                    catch [System.Exception] {
                        Write-CMLogEntry -Value " - Failed to remove provisioned appx package '$($App.DisplayName)' in OS image. Error message: $($_.Exception.Message)" -Severity 3

                        # Throw terminating error
                        $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
                    }
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to retrieve provisioned appx package in OS image. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Add-DynamicUpdateSetupFiles {
        if ($SkipDUSUPatch -ne $true) {
            try {
                Write-CMLogEntry -Value " - Attempting to copy Dynamic Updates setup update files into OS media source file location" -Severity 1
                $OSMediaSourcesPath = Join-Path -Path $OSMediaImagePath -ChildPath "sources"
                $UpdateDUSUExtractedFolders = Get-ChildItem -Path $DUSUExtractPath -Directory -ErrorAction Stop
                foreach ($UpdateDUSUExtractedFolder in $UpdateDUSUExtractedFolders) {
                    Write-CMLogEntry -Value " - Currently processing folder: $($UpdateDUSUExtractedFolder.FullName)" -Severity 1
                    Copy-Item -Path "$($UpdateDUSUExtractedFolder.FullName)\*" -Destination $OSMediaSourcesPath -Container -Force -Recurse -ErrorAction Stop
                }
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value " - Failed to copy Dynamic Updates setup update files into OS media source files. Error message: $($_.Exception.Message)" -Severity 3
            }
        }
        else {
            Write-CMLogEntry -Value " - Skipping Dynamic Updates (DUSU) updates due to missing update files in sub-folder"-Severity 2
        }
    }

    function Copy-WinREImage {
        try {
            # Move WinRE image from mounted OS image to a temporary location
            Write-CMLogEntry -Value " - Attempting to copy winre.wim file from mounted temporary OS image to servicing location: $($OSImageWinRETempWim)" -Severity 1
            Copy-Item -Path (Join-Path -Path $MountOSImage -ChildPath "\Windows\System32\Recovery\winre.wim") -Destination $OSImageWinRETempWim -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to copy temporary WinRE image from mounted temporary OS image location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Mount-WinREImage {
        try {
            # Mount the WinRE temporary image
            Write-CMLogEntry -Value " - Attempting to mount temporary winre_temp.wim file from: $($OSImageWinRETempWim)" -Severity 1
            Mount-WindowsImage -ImagePath $OSImageWinRETempWim -Path $MountWinRE -Index 1 -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to mount temporary WinRE image from servicing location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Dismount-WinREImage {
        try {
            # Dismount the WinRE image
            Write-CMLogEntry -Value " - Attempting to dismount and save changes made to temporary WinRE image" -Severity 1
            Dismount-WindowsImage -Path $MountWinRE -Save -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to dismount and save temporary WinRE image from mount location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Export-WinREImage {
        try {
            # Remove existing WinRE image from OS media source location
            Write-CMLogEntry -Value " - Attempting to remove existing WinRE image from OS media source location" -Severity 1
            Remove-Item -Path (Join-Path -Path $MountOSImage -ChildPath "Windows\System32\Recovery\winre.wim") -Force -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to remove existing WinRE image OS media source location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        try {
            # Export temporary WinRE to back to original source location in OS image
            Write-CMLogEntry -Value " - Attempting to export temporary WinRE image to mounted temporary OS image location" -Severity 1
            Export-WindowsImage -SourceImagePath $OSImageWinRETempWim -DestinationImagePath (Join-Path -Path $MountOSImage -ChildPath "Windows\System32\Recovery\winre.wim") -SourceName "Microsoft Windows Recovery Environment (x64)" -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to export temporary WinRE image from mount location back to mounted temporary OS image location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Copy-BootImage {
        try {
            # Copy boot.wim from OS media source location to temporary location
            $OSBootWim = Join-Path -Path $OSMediaImagePath -ChildPath "sources\boot.wim"
            Write-CMLogEntry -Value " - Attempting to copy boot.wim file from OS media source files location to temporary location: $($OSBootWimTemp)" -Severity 1
            Copy-Item -Path $OSBootWim -Destination $OSBootWimTemp -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to copy boot.wim file from OS media source files location to temporary location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
        
        try {
            # Remove the read-only attribute on the temporary boot.wim file
            Write-CMLogEntry -Value " - Attempting to remove read-only attribute from boot_temp.wim file" -Severity 1
            Set-ItemProperty -Path $OSBootWimTemp -Name "IsReadOnly" -Value $false -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to remove read-only attribute from copied boot_temp.wim file. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Mount-BootImage {
        try {
            # Mount temporary boot image file
            Write-CMLogEntry -Value " - Attempting to mount temporary boot image file" -Severity 1
            Mount-WindowsImage -ImagePath $OSBootWimTemp -Index 2 -Path $MountBootImage -ErrorAction Stop | Out-Null   
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to mount temporary boot image from servicing location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Dismount-BootImage {
        try {
            # Dismount the temporary boot image
            Write-CMLogEntry -Value " - Attempting to dismount temporary boot image" -Severity 1
            Dismount-WindowsImage -Path $MountBootImage -Save -ErrorAction Stop | Out-Null
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to dismount and save temporary boot image from mount location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Update-BootImage {
        try {
            # Remove boot.wim from OS media source file location
            Write-CMLogEntry -Value " - Attempting to remove boot.wim from OS media source files location" -Severity 1
            Remove-Item -Path (Join-Path -Path $OSMediaImagePath -ChildPath "sources\boot.wim") -Force -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to remove boot.wim from OS media source files location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
        
        try {
            # Replace serviced boot image wim file with existing wim file
            Write-CMLogEntry -Value " - Attempting to move temporary boot image file to OS media source files location" -Severity 1
            Move-Item -Path $OSBootWimTemp -Destination (Join-Path -Path $OSMediaImagePath -ChildPath "sources\boot.wim") -Force -ErrorAction Stop 
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to move temporary boot image file to OS media source files location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    function Invoke-ContentRefresh {
        # Determine WMI class from parameter input
        switch ($PackageType) {
            "OperatingSystemImage" {
                $WMIClass = "SMS_ImagePackage"
            }
            "OperatingSystemUpgradePackage" {
                $WMIClass = "SMS_OperatingSystemInstallPackage"
            }
        }

        try {
            Write-CMLogEntry -Value " - Attempting to query WMI class '$($WMIClass)' for instance with PackageID: $($PackageID)" -Severity 1
            $ImagePackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class $WMIClass -ComputerName $SiteServer -Filter "PackageID = '$($PackageID)'" -ErrorAction Stop
            if ($ImagePackage -ne $null) {
                $ImagePackage.Get()
                $InvocationRefreshPackage = $ImagePackage.RefreshPkgSource()

                # Validate return value from package update
                if ($InvocationRefreshPackage.ReturnValue -eq 0) {
                    Write-CMLogEntry -Value " - Successfully refreshed Distribution Points for PackageID: $($PackageID)" -Severity 1
                }
            }
            else {
                Write-CMLogEntry -Value " - Unable to detect instance with PackageID '$($PackageID)'" -Severity 2
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to perform package refresh operation for instance with PackageID '$($PackageID)'. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
    }

    # PowerShell variables
    $ProgressPreference = "SilentlyContinue"

    # Define default values for skip variables and other functionality
    $SkipServicingStackUpdate = $false
    $SkipNETFrameworkUpdate = $false
    $SkipAdobeFlashPlayerUpdate = $false
    $SkipDUCUPatch = $false
    $SkipDUSUPatch = $false
    $SkipLanguagePack = $false
    $SkipLanguagePackLXP = $false
    $SkipLanguageFeatures = $false
    $SkipOneDriveUpdate = $false

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
    $OSMediaSourcePath = Join-Path -Path $OSMediaFilesRoot -ChildPath "Source"
    $OSMediaImagePath = Join-Path -Path $OSMediaFilesRoot -ChildPath "Image"
    $MountPathRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Mount"
    $UpdateFilesRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Updates"
    $LPFilesRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "LanguagePack"
    $BackupPathRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Backup"
    $OSInstallWim = Join-Path -Path $OSMediaImagePath -ChildPath "sources\install.wim"
    $OSBootWim = Join-Path -Path $OSMediaImagePath -ChildPath "sources\boot.wim"
    $OSImageTempWim = Join-Path -Path (Join-Path -Path $MountPathRoot -ChildPath "Temp") -ChildPath "install_temp.wim"
    $OSImageWinRETempWim = Join-Path -Path (Join-Path -Path $MountPathRoot -ChildPath "Temp") -ChildPath "winre_temp.wim"
    $OSBootWimTemp = Join-Path -Path (Join-Path -Path $MountPathRoot -ChildPath "Temp") -ChildPath "boot_temp.wim"

    Write-CMLogEntry -Value "[ServicingStart]: Initiating Windows Image Servicing process" -Severity 1
    Write-CMLogEntry -Value "[Environment]: Initiating environment requirements phase" -Severity 1

    try {
        # Determine SiteCode from WMI
        try {
            Write-CMLogEntry -Value " - Determining Site Code for Site server: '$($SiteServer)'" -Severity 1
            $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
            foreach ($SiteCodeObject in $SiteCodeObjects) {
                if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                    $SiteCode = $SiteCodeObject.SiteCode
                    Write-CMLogEntry -Value " - Using automatically detected Site Code: $($SiteCode)" -Severity 1
                }
            }
        }
        catch [System.UnauthorizedAccessException] {
            Write-CMLogEntry -Value " - Unable to determine site code, access was denied" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Unable to determine site code from specified Configuration Manager site server, specify the site server name where the SMS Provider is installed" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        # Detect if Windows ADK is installed, and determine installation location
        try {
            $ADKInstallPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots" -ErrorAction Stop | Select-Object -ExpandProperty KitsRoot*
            $DeploymentToolsDISMPath = Join-Path -Path $ADKInstallPath -ChildPath "Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe"
            Write-CMLogEntry -Value " - Windows ADK installation path: $($ADKInstallPath)" -Severity 1
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Unable to detect Windows ADK installation location. Error message: $($_.Exception.Message)" -Severity 3

            # Throw terminating error
            $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
            $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        }

        # Validate correct parameters are passed when RefreshPackage switch is used
        if ($PSBoundParameters["RefreshPackage"]) {
            if ([string]::IsNullOrEmpty($PackageID)) {
                Write-CMLogEntry -Value " - RefreshPackage switch was passed on the command line, but PackageID parameter was either null or empty. Please specify a value for PackageID parameter" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }

            # Validate existing object with specified PackageID exists in ConfigMgr
            switch ($PackageType) {
                "OperatingSystemImage" {
                    $WMIClass = "SMS_ImagePackage"
                }
                "OperatingSystemUpgradePackage" {
                    $WMIClass = "SMS_OperatingSystemInstallPackage"
                }
            }
            $ImagePackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class $WMIClass -ComputerName $SiteServer -Filter "PackageID = '$($PackageID)'"
            if ($ImagePackage -eq $null) {
                Write-CMLogEntry -Value " - Unable to detect instance in WMI class '$($WMIClass)' matching PackageID: $($PackageID)" -Severity 3

                # Throw terminating error
                $ErrorRecord = New-TerminatingErrorRecord -Message ([string]::Empty)
                $PSCmdlet.ThrowTerminatingError($ErrorRecord)
            }
        }

        # Verify that all required product categories have been subscribed to in the Software Update Point
        $ProductCategories = @("Windows 10", "Windows 10, version 1903 and later", "Windows 10 Dynamic Update")
        foreach ($ProductCategory in $ProductCategories) {
            if ($ProductCategory -like "Windows 10 Dynamic Updates") {
                if ($PSBoundParameters["IncludeDynamicUpdates"]) {
                    $ReturnValue = Test-ProductCategorySubscribedState -Product $ProductCategory
                    if ($ReturnValue -eq $true) {
                        Write-CMLogEntry -Value " - Successfully validated that the $($ProductCategory) product is enabled in the Software Update Point component configuration" -Severity 1
                    }
                    else {
                        Write-CMLogEntry -Value " - Validation for the $($ProductCategory) product failed, please enable it in the Software Update Point component configuration" -Severity 3
                    }
                }
            }
            else {
                $ReturnValue = Test-ProductCategorySubscribedState -Product $ProductCategory
                if ($ReturnValue -eq $true) {
                    Write-CMLogEntry -Value " - Successfully validated that the $($ProductCategory) product is enabled in the Software Update Point component configuration" -Severity 1
                }
                else {
                    Write-CMLogEntry -Value " - Validation for the $($ProductCategory) product failed, please enable it in the Software Update Point component configuration" -Severity 3
                }
            }
        }

        # Construct root level folders for temporary content and backups
        $RootFoldersList = @("Source", "Image", "Updates", "Mount", "Backup")
        foreach ($RootFolder in $RootFoldersList) {
            New-RootFolderRequired -Name $RootFolder
        }

        # Construct sublevel folders per root folder
        $SubRootTable = @{
            "Mount" = @("OSImage", "BootImage", "WinRE", "Temp")
        }
        foreach ($SubRootKey in $SubRootTable.Keys) {
            foreach ($SubRootValue in $SubRootTable[$SubRootKey]) {
                New-SubFolderRequired -RootFolderName $SubRootKey -Name $SubRootValue
            }
        }

        if ($PSBoundParameters["IncludeDynamicUpdates"]) {
            # Define required path variables for subfolders
            $DUSUDownloadPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUSU"
            $DUSUExtractPath = Join-Path -Path $DUSUDownloadPath -ChildPath "Extract"
            $DUCUDownloadPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUCU"

            # Construct optional sub folders
            New-SubFolderOptional -Path $DUSUDownloadPath -Name "DUSU"
            New-SubFolderOptional -Path $DUSUExtractPath -Name "Extract"
            New-SubFolderOptional -Path $DUCUDownloadPath -Name "DUCU"
        }
        
        if ($PSBoundParameters["IncludeLanguagePack"]) {
            # Define required path variables for subfolders
            $LPBaseFilesRoot = Join-Path -Path $LPFilesRoot -ChildPath "Base"
            $LPLXPFilesRoot = Join-Path -Path $LPFilesRoot -ChildPath "LXP"

            # Construct optional sub folders
            New-SubFolderOptional -Path $LPBaseFilesRoot -Name "Base"
            New-SubFolderOptional -Path $LPLXPFilesRoot -Name "LXP"
        }

        if ($PSBoundParameters["IncludeLanguageFeatures"]) {
            # Define required path variables for subfolders
            $LPFeatureFilesRoot = Join-Path -Path $LPFilesRoot -ChildPath "Features"

            # Construct optional sub folder
            New-SubFolderOptional -Path $LPFeatureFilesRoot -Name "Features"
        }

        Write-CMLogEntry -Value "[Environment]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[Content]: Initiating content requirements phase" -Severity 1

        # Perform cleanup of any existing update item content files
        Remove-UpdateContentFiles

        # Verify that given location for OSMediaFilesRoot contains install.wim and boot.wim, if required files are not present, script execution will break
        Test-SourceFiles

        # Download Cumulative Update, Servicing Stack Update, .NET Framework and Adobe Flash Player updates
        Save-UpdateContent

        if ($PSBoundParameters["IncludeLanguagePack"]) {
            # Stage Language Pack content from ISO in servicing location
            Save-LanguagePackContent

            if ($PSBoundParameters["IncludeLanguageFeatures"]) {
                # Stage Language Features from ISO in servicing location
                Save-LanguageFeaturesContent
            }

            # Validate Language Pack content was staged successfully in servicing location
            Test-LanguagePackContent

            if ($PSBoundParameters["IncludeLanguageFeatures"]) {
                # Stage Language Features from ISO in servicing location
                Test-LanguageFeaturesContent
            }            
        }

        if ($PSBoundParameters["IncludeDynamicUpdates"]) {
            # Download Dynamic Update content for DUSU/DUCU
            Save-DynamicUpdatesContent

            # Validate Dynamic Updates content files are staged successfully
            $UpdatesDUCUFilePaths = Get-DynamicUpdateComponentFiles
            $UpdatesDUSUFilePath = Get-DynamicUpdateSetupFiles
        }

        # Validate updates root folder contains required update content cabinet files, if required update files are not present, script execution will break
        $CumulativeUpdateFilePath = Get-UpdateFiles -UpdateType "CumulativeUpdate"
        $ServiceStackUpdateFilePath = Get-UpdateFiles -UpdateType "ServicingStack"
        $NETFrameworkUpdateFilePaths = Get-UpdateFiles -UpdateType "NETFramework"
        $AdobeUpdateFilePath = Get-UpdateFiles -UpdateType "AdobeFlash"

        if ($PSBoundParameters["UpdateOneDriveSetup"]) {
            # Download the latest OneDriveSetup.exe file from Microsoft download page
            Save-OneDriveSetup

            # Validate OneDriveSetup.exe was successfully downloaded
            Test-OneDriveSetup
        }

        Write-CMLogEntry -Value "[Content]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[Backup]: Initiating backup phase" -Severity 1

        # Call the Source folder backup routine
        Invoke-ImageBackup
        
        Write-CMLogEntry -Value "[Backup]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[BackupCleanup]: Initiating backup cleanup phase" -Severity 1
        
        Invoke-ImageBackupCleanup

        Write-CMLogEntry -Value "[BackupCleanup]: Successfully completed phase" -Severity 1        
        Write-CMLogEntry -Value "[OSImagePrepare]: Initiating OS image servicing preparation phase" -Severity 1

        # Perform cleanup of Image root folder
        Remove-ImageFiles

        # Copy all original OS media source files into Image folder for servicing
        Copy-SourceFiles

        # Export a temporary OS image from the OS media source files
        Export-OSImage

        Write-CMLogEntry -Value "[OSImagePrepare]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[OSImage]: Initiating OS image servicing phase" -Severity 1

        # Mount the temporary OS image and prepare for offline servicing
        Mount-OSImage

        if ($SkipServicingStackUpdate -eq $false) {
            # Add Servicing Stack Update package to mounted temporary OS image
            Add-OSImagePackage -UpdateType "Servicing Stack Update" -PackagePath $ServiceStackUpdateFilePath
        }
        else {
            Write-CMLogEntry -Value " - Update type 'Servicing Stack Update' was previously set to be skipped, will not attempt to apply package to OS image as no update package file was found" -Severity 2
        }

        if ($PSBoundParameters["IncludeLanguagePack"]) {
            # Add Language Pack base packages and if also specified Local Experience Packs to temporary OS image
            Add-OSImageLanguagePack

            if ($PSBoundParameters["IncludeLanguageFeatures"]) {
                # Add Language Feature packages to temporary OS image
                Add-OSImageLanguageFeature
            }
        }

        # Add Cumulative Update package to mounted temporary OS image
        Add-OSImagePackage -UpdateType "Cumulative Update" -PackagePath $CumulativeUpdateFilePath

        if ($SkipAdobeFlashPlayerUpdate -eq $false) {
            # Add Adobe Flash Update package to mounted temporary OS image
            Add-OSImagePackage -UpdateType "Adobe Flash" -PackagePath $AdobeUpdateFilePath
        }
        else {
            Write-CMLogEntry -Value " - Update type 'Adobe Flash Update' was previously set to be skipped, will not attempt to apply package to OS image as no update package file was found" -Severity 2
        }

        if ($PSBoundParameters["IncludeDynamicUpdates"]) {
            if ($SkipDUCUPatch -eq $false) {
                # Add Dynamic Update Component Update package to mounted temporary OS image
                Add-OSImagePackage -UpdateType "Dynamic Update Component Update" -PackagePath $UpdatesDUCUFilePaths
            }
            else {
                Write-CMLogEntry -Value " - SkipDUCUPatch variable set to True, skipping Dynamic Update Component Update servicing" -Severity 2
            }
        }

        if ($PSBoundParameters["RemoveAppxPackages"]) {
            # Remove built-in appx provisioning packages from mounted temporary OS image
            Remove-AppxProvisioningPackages
        }

        # Call OS image component cleanup routine and reset base
        Invoke-OSImageCleanup -ImageType "OS Image" -ResetBase

        if ($PSBoundParameters["IncludeNetFramework"]) {
            # Add legacy .NET Framework 3.5.1 to mounted temporary OS image
            Add-LegacyNetFramework
        }

        if ($SkipNETFrameworkUpdate -eq $false) {
            # Add .NET Framework Update packages to mounted temporary OS image
            Add-OSImagePackage -UpdateType ".NET Framework" -PackagePath $NETFrameworkUpdateFilePaths
        }
        else {
            Write-CMLogEntry -Value " - Update type '.NET Framework' was previously set to be skipped, will not attempt to apply package to OS image as no update package file was found" -Severity 2
        }

        if ($PSBoundParameters["UpdateOneDriveSetup"]) {
            # Update OneDriveSetup.exe in mounted temporary OS image
            Update-OneDriveSetup
        }
        
        Write-CMLogEntry -Value "[OSImage]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[WinREImage]: Initiating WinRE image servicing phase" -Severity 1

        # Copy WinRE.wim from mounted temporary OS image to servicing location
        Copy-WinREImage

        # Mount temporary WinRE image
        Mount-WinREImage

        # Add Servicing Stack Update package to mounted temporary WinRE image
        Add-WinREImagePackage -UpdateType "Servicing Stack Update" -PackagePath $ServiceStackUpdateFilePath

        # Add Cumulative Update package to mounted temporary WinRE image
        Add-WinREImagePackage -UpdateType "Cumulative Update" -PackagePath $CumulativeUpdateFilePath

        # Call WinRE image component cleanup routine and perform a reset base
        Invoke-OSImageCleanup -ImageType "WinRE Image"

        # Dismount mounted temporary WinRE image
        Dismount-WinREImage

        # Export mounted temporary WinRE image back to mounted temporary OS image location
        Export-WinREImage

        Write-CMLogEntry -Value "[WinREImage]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[OSImageExport]: Initiating OS image export servicing phase" -Severity 1

        # Dismount and save temporary OS image
        Dismount-OSImage

        # Export mounted temporary OS image and replace existing install.wim in Source location with exported image
        Update-OSImage

        Write-CMLogEntry -Value "[OSImageExport]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[BootImage]: Initiating boot image servicing phase" -Severity 1

        # Copy boot.wim from OS media source files location to temporary location for servicing
        Copy-BootImage

        # Mount temporary boot image from servicing location
        Mount-BootImage

        # Add Servicing Stack Update package to mounted temporary boot image
        Add-BootImagePackage -UpdateType "Servicing Stack Update" -PackagePath $ServiceStackUpdateFilePath

        # Add Cumulative Update package to mounted temporary boot image
        Add-BootImagePackage -UpdateType "Cumulative Update" -PackagePath $CumulativeUpdateFilePath

        # Dismount Boot Image
        Dismount-BootImage
    
        Write-CMLogEntry -Value "[BootImage]: Successfully completed phase" -Severity 1
        Write-CMLogEntry -Value "[BootImageExport]: Initiating boot image export servicing phase" -Severity 1

        # Remove existing boot.wim file in OS media source files location and replace with serviced boot_temp.wim from servicing location
        Update-BootImage

        Write-CMLogEntry -Value "[BootImageExport]: Successfully completed phase" -Severity 1

        if ($PSBoundParameters["IncludeDynamicUpdates"]) {
            if ($SkipDUSUPatch -eq $false) {
                Write-CMLogEntry -Value "[OSImageFinal]: Initiating OS image final servicing phase" -Severity 1
                Add-DynamicUpdateSetupFiles
                Write-CMLogEntry -Value "[OSImageFinal]: Successfully completed phase" -Severity 1
            }
            else {
                Write-CMLogEntry -Value " - SkipDUSUPatch variable set to True, skipping Dynamic Update Setup Update servicing" -Severity 1
            }
        }

        if ($PSBoundParameters["RefreshPackage"]) {
            Invoke-ContentRefresh
        }

        # Servicing completed successfully
        Write-CMLogEntry -Value "[ServicingComplete]: Windows image servicing completed successfully" -Severity 1
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "[ServicingFailed]: Windows image servicing failed, please refer to previous error or warning messages" -Severity 3
    }
}
End {
    Write-CMLogEntry -Value "[Cleanup]: Initiaing servicing cleanup process" -Severity 1
    try {
        # Cleanup any mounted images that should not be mounted
        Write-CMLogEntry -Value " - Checking for mounted images that should not be mounted at this stage" -Severity 1
        $MountedImages = Get-WindowsImage -Mounted -ErrorAction Stop

        if ($MountedImages -ne $null) {
            foreach ($MountedImage in $MountedImages) {
                Write-CMLogEntry -Value " - Attempting to dismount and discard image: $($MountedImage.Path)" -Severity 1
                Dismount-WindowsImage -Path $MountedImage.Path -Discard -ErrorAction Stop | Out-Null
                Write-CMLogEntry -Value " - Successfully dismounted image" -Severity 1
            }
        }
        else {
            Write-CMLogEntry -Value " - There were no images that was required to be dismounted" -Severity 1
        }

        Write-CMLogEntry -Value "[Cleanup]: Successfully completed mounted images cleanup process" -Severity 1
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value " - Failed to dismount mounted image. Error message: $($_.Exception.Message)" -Severity 3
    }

    Write-CMLogEntry -Value "[Cleanup]: Initiaing temporary image files cleanup process" -Severity 1
    try {
        # Remove any temporary files left after processing
        Write-CMLogEntry -Value " - Checking for temporary image files to be removed" -Severity 1
        $WimFiles = Get-ChildItem -Path $MountPathRoot -Recurse -Filter "*.wim" -ErrorAction Stop
        if ($WimFiles -ne $null) {
            foreach ($WimFile in $WimFiles) {
                Write-CMLogEntry -Value " - Attempting to remove temporary image file: $($WimFile.FullName)" -Severity 1
                Remove-Item -Path $WimFile.FullName -Force -ErrorAction Stop
                Write-CMLogEntry -Value " - Successfully removed temporary image file" -Severity 1
            }
        }
        else {
            Write-CMLogEntry -Value " - There were no image files that needs to be removed" -Severity 1
        }

        Write-CMLogEntry -Value "[Cleanup]: Successfully completed temporary servicing cleanup files" -Severity 1
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value " - Failed to remove temporary image files. Error message: $($_.Exception.Message)" -Severity 3
    }

    if ($PSBoundParameters["IncludeDynamicUpdates"]) {
        try {
            # Remove extracted Dynamic Updates setup update files
            if ($DUSUExtractPath -ne $null) {
                if (Test-Path -Path $DUSUExtractPath) {
                    Write-CMLogEntry -Value "[Cleanup]: Initiaing extracted Dynamic Update setup update files cleanup process" -Severity 1
                    Remove-Item -Path $DUSUExtractPath -Recurse -Force -ErrorAction Stop
                    Write-CMLogEntry -Value "[Cleanup]: Successfully completed extracted Dynamic Update setup update files cleanup process" -Severity 1
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value " - Failed to remove extracted Dynamic Updates setup update files. Error message: $($_.Exception.Message)" -Severity 3
        }
    }
}