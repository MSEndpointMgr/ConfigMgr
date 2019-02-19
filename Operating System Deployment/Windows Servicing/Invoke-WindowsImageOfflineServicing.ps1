<#
.SYNOPSIS
    Service a Windows image from a source files location with the latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player.

.DESCRIPTION
    This script will service Windows image from a source files location with the latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player.
    There are three types of updates the script handles, Cumulative Updates, Service Stack Updates and Other updates. A Cumulative Update is required for the script
    to continue with the servicing of the Windows image. Service Stack Updates and Other updates are not required, however for a Cumulative Update to 
    successfully be applied, the latest Service Stack Update is required (either already applied to the image, or added in the SSU folder). There can be 
    more than one Other updates, but for the Cumulative Update and Service Stack Updates, the latest file in the CU and SSU folder will automatically be selected
    by the script.

    Original servicing logic is using the same as published here, with a few modifications:
    https://deploymentresearch.com/Research/Post/672/Windows-10-Servicing-Script-Creating-the-better-In-Place-upgrade-image

    Requirements for running this script:
    - Access to Windows ADK locally installed on the machine where executed
    - It's not supported to run this script with UNC paths
    - Supported operating system editions: Enterprise, Education
    - A folder containing the Windows source files extracted from an ISO

    Required folder structure for location specified for UpdateFilesRoot:
    - .\CU (place latest Cumulative Update msu file here)
    - .\SSU (place latest Service Stack Update msu file here)
    - .\Other (place latest e.g. Adobe Flash Player msu file here)

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

.PARAMETER IncludeNetFramework
    Include .NET Framework 3.5.1 when servicing the OS image.

.PARAMETER RemoveAppxPackages
    Remove built-in provisioned appx packages when servicing the OS image.

.EXAMPLE
    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1803X64"

    # Service a Windows Education image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1803X64" -OSEdition "Education"

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1803X64" -IncludeNetFramework

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1 and remove provisioned Appx packages:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1803X64" -IncludeNetFramework -RemoveAppxPackages

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update, Adobe Flash Player and Dynamic Updates:
    .\Invoke-WindowsImageOfflineServicing.ps1 -SiteServer CM01 -OSMediaFilesRoot "C:\CMSource\OSD\W10E1803X64" -IncludeDynamicUpdates -OSVersion 1803 -OSArchitecture x64

.NOTES
    FileName:    Invoke-WindowsImageOfflineServicing.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-09-12
    Updated:     2019-02-13
    
    Version history:
    1.0.0 - (2018-09-12) Script created
    1.0.1 - (2018-09-16) Added support to remove appx packages from OS image
    1.0.2 - (2018-10-23) Added support for detecting and applying Dynamic Updates, both Setup Updates (DUSU) and Component Updates (DUCU). 
                         Simplified script parameters, OSMediaFilesPath, MountPathRoot and UpdateFilesRoot are now all replaced with OSMediaFilesRoot parameter.
    1.0.3 - (2018-11-28) Fixed an issue where the output would show the wrong backup paths for install.wim and boot.wim
    1.0.4 - (2018-11-30) Removed -Optimize parameter for Mount-WindowsImage cmdlets to support 1809 (and perhaps above). From 1803 and above it's actually slower according to test performed by David Segura
    1.0.5 - (2019-02-13) Fixed an issue where WinRE would not be exported correctly after servicing
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Site server where the SMS Provider is installed.")]
    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, ParameterSetName="ImageServicing", HelpMessage="Specify the full path for the root location containing a folder named Source with the Windows 10 installation media files.")]
    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates")]
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
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Enterprise", "Education")]
    [string]$OSEdition = "Enterprise",

    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates", HelpMessage="Apply Dynamic Updates to serviced Windows image source files.")]
    [switch]$IncludeDynamicUpdates,   

    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates", HelpMessage="Specify the operating system version being serviced.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("1703", "1709", "1803", "1809", "1903", "1909", "2003", "2009", "2103", "2109")]
    [string]$OSVersion,

    [parameter(Mandatory=$true, ParameterSetName="DynamicUpdates", HelpMessage="Specify the operating system architecture being serviced.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("x64", "x86")]
    [string]$OSArchitecture = "x64",    

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Include .NET Framework 3.5.1 when servicing the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [switch]$IncludeNetFramework,

    [parameter(Mandatory=$false, ParameterSetName="ImageServicing", HelpMessage="Remove built-in provisioned appx packages when servicing the OS image.")]
    [parameter(Mandatory=$false, ParameterSetName="DynamicUpdates")]
    [switch]$RemoveAppxPackages
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
        [CmdletBinding(SupportsShouldProcess=$true)]
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

    # PowerShell variables
    $ProgressPreference = "SilentlyContinue"

    # Define skip section variables
    $SkipOtherPatch = $false
    $SkipServiceStackUpdatePatch = $false

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
        "Microsoft.WindowsStore"
    )

    # Construct required variables for content location
    $OSMediaFilesPath = Join-Path -Path $OSMediaFilesRoot -ChildPath "Source"
    $MountPathRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Mount"
    $UpdateFilesRoot = Join-Path -Path $OSMediaFilesRoot -ChildPath "Updates"

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

    if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
        Write-Verbose -Message "[DynamicUpdateContent]: Initiating dynamic update content download phase"

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
    
        Write-Verbose -Message "[DynamicUpdateContent]: Successfully completed phase"
    }

    Write-Verbose -Message "[Content]: Initiating content requirements phase"

    # Validate Source subfolder exist
    if (-not(Test-Path -Path $OSMediaFilesPath)) {
        Write-Warning -Message "Failed to locate required Source subfolder in: $($OSMediaFilesRoot)"; break
    }

    # Validate Source subfolder exist
    if (-not(Test-Path -Path $UpdateFilesRoot)) {
        Write-Warning -Message "Failed to locate required Updates subfolder in: $($OSMediaFilesRoot)"; break
    }    

    # Create Mount subfolder
    if (-not(Test-Path -Path $MountPathRoot)) {
        New-Item -Path $OSMediaFilesRoot -Name "Mount" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the Mount subfolder in: $($OSMediaFilesRoot)"
    }

    # Create OS image mount path subfolder
    $MountPathOSImage = Join-Path -Path $MountPathRoot -ChildPath "OSImage"
    if (-not(Test-Path -Path $MountPathOSImage)) {
        New-Item -Path $MountPathRoot -Name "OSImage" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the OS image mount subfolder"
    }

    # Create boot image mount path sub folder
    $MountPathBootImage = Join-Path -Path $MountPathRoot -ChildPath "BootImage"
    if (-not(Test-Path -Path $MountPathBootImage)) {
        New-Item -Path $MountPathRoot -Name "BootImage" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the boot image mount subfolder"
    }

    # Create boot image mount path sub folder
    $MountPathWinRE = Join-Path -Path $MountPathRoot -ChildPath "WinRE"
    if (-not(Test-Path -Path $MountPathWinRE)) {
        New-Item -Path $MountPathRoot -Name "WinRE" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the WinRE mount subfolder"
    }

    # Create temp mount path sub folder
    $ImagePathTemp = Join-Path -Path $MountPathRoot -ChildPath "Temp"
    if (-not(Test-Path -Path $ImagePathTemp)) {
        New-Item -Path $MountPathRoot -Name "Temp" -ItemType Directory -Force | Out-Null
        Write-Verbose -Message " - Successfully created the temp image subfolder"
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

    # Validate updates root folder contains required CU subfolder
    $UpdateCUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "CU"
    if (Test-Path -Path $UpdateCUFolderPath) {
        Write-Verbose -Message " - Located the required 'CU' folder"
        if (-not((Get-ChildItem -Path $UpdateCUFolderPath -Recurse -Filter "*.msu").Count -ge 1)) {
            Write-Warning -Message "Required 'CU' folder is empty, breaking operation"; break
        }
        else {
            # Determine Cumulative Update file to be applied
            $CumulativeUpdateFilePath = Get-ChildItem -Path $UpdateCUFolderPath -Recurse -Filter "*.msu" | Where-Object { $_.Length -ge 30720000 } | Sort-Object -Descending -Property $_.CreationTime | Select-Object -First 1 -ExpandProperty FullName
            if ($CumulativeUpdateFilePath -eq $null) {
                Write-Warning -Message "Failed to locate required Cumulative Update file in 'CU' folder, breaking operation"; break
            }
            else {
                Write-Verbose -Message " - Selected the most recent Service Stack Update file: $($CumulativeUpdateFilePath)"
            }
        }
    }
    else {
        Write-Warning -Message "Unable to locate required 'CU' subfolder in the update files root location. Please create it manually and add the latest Cumulative Update inside the folder"; break
    }

    # Validate updates root folder contains required SSU subfolder
    $UpdateSSUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "SSU"
    if (Test-Path -Path $UpdateSSUFolderPath) {
        Write-Verbose -Message " - Located the required 'SSU' folder"
        if (-not((Get-ChildItem -Path $UpdateSSUFolderPath -Recurse -Filter "*.msu").Count -ge 1)) {
            Write-Warning -Message "Required 'SSU' folder is empty, setting variable to skip processing of other files"
            $SkipServiceStackUpdatePatch = $true
        }
        else {
            # Determine Service Stack Update file to be applied
            $ServiceStackUpdateFilePath = Get-ChildItem -Path $UpdateSSUFolderPath -Recurse -Filter "*.msu" | Sort-Object -Descending -Property $_.CreationTime | Select-Object -First 1 -ExpandProperty FullName
            if ($ServiceStackUpdateFilePath -eq $null) {
                Write-Warning -Message "Failed to locate a Service Stack Update file in 'SSU' folder"
            }
            else {
                Write-Verbose -Message " - Selected the most recent Service Stack Update file: $($ServiceStackUpdateFilePath)"
            }
        }
    }
    else {
        Write-Warning -Message "Unable to locate required 'SSU' subfolder in the update files root location. Please create it manually and add the latest Service Stack Update inside the folder"; break
    }

    # Validate updates root folder contains required other subfolder
    $UpdateOtherFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "Other"
    if (Test-Path -Path $UpdateOtherFolderPath) {
        Write-Verbose -Message " - Located the required 'Other' folder"
        if (-not((Get-ChildItem -Path $UpdateOtherFolderPath -Recurse -Filter "*.msu").Count -ge 1)) {
            Write-Warning -Message "Required 'Other' folder is empty, setting variable to skip processing of other files"
            $SkipOtherPatch = $true
        }
        else {
            # Determine Service Stack Update file to be applied
            $OtherUpdateFilePaths = Get-ChildItem -Path $UpdateOtherFolderPath -Recurse -Filter "*.msu" | Sort-Object -Descending -Property $_.CreationTime | Select-Object -ExpandProperty FullName
            if ($OtherUpdateFilePaths -eq $null) {
                Write-Warning -Message "Failed to locate any update files in 'Other' folder"
            }
            else {
                foreach ($OtherUpdateFilePath in $OtherUpdateFilePaths) {
                    Write-Verbose -Message " - Found the following update in the 'Other' folder: $($OtherUpdateFilePath)"
                }
            }
        }
    }
    else {
        Write-Warning -Message "Unable to locate required 'Other' subfolder in the update files root location. Please create it manually and add the latest Adobe Flash update inside the folder"; break
    }

    if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
        # Validate Dynamic Updates DUCU folder contains required files
        $UpdatesDUCUFolderPath = Join-Path -Path $UpdateFilesRoot -ChildPath "DUCU"
        if (Test-Path -Path $UpdatesDUCUFolderPath) {
            Write-Verbose -Message " - Located the Dynamic Updates required 'DUCU' folder"
            if (-not((Get-ChildItem -Path $UpdatesDUCUFolderPath -Recurse -Filter "*.cab").Count -ge 1)) {
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
            if (-not((Get-ChildItem -Path $UpdatesDUSUFolderPath -Recurse -Filter "*.cab").Count -ge 1)) {
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
            
            if ($PSCmdlet.ParameterSetName -like "DynamicUpdates") {
                # Backup complete set of OS media source files
                $OSMediaFilesBackupPath = Join-Path -Path (Split-Path -Path $OSMediaFilesPath -Parent) -ChildPath "SourceBackup_$((Get-Date).ToString("yyyy-MM-dd"))"
                Write-Verbose -Message " - Backing up complete set of OS media source files into: $($OSMediaFilesBackupPath)"
                Copy-Item -Path $OSMediaFilesPath -Destination $OSMediaFilesBackupPath -Container -Recurse -Force -ErrorAction Stop
            }

            if ($PSCmdlet.ParameterSetName -like "ImageServicing") {
                # Backup existing OS image install.wim file to temporary location
                $OSImageTempBackupPath = (Join-Path -Path $ImagePathTemp -ChildPath "install_$((Get-Date).ToString("yyyy-MM-dd")).wim.bak")
                Write-Verbose -Message " - Backing up install.wim from OS media source files location: $($OSImageTempBackupPath)"
                Copy-Item -Path (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\install.wim") -Destination $OSImageTempBackupPath -Force -ErrorAction Stop

                # Backup existing OS image boot.wim file to temporary location
                $BootImageTempBackupPath = (Join-Path -Path $ImagePathTemp -ChildPath "boot_$((Get-Date).ToString("yyyy-MM-dd")).wim.bak")
                Write-Verbose -Message " - Backing up boot.wim from OS media source files location: $($BootImageTempBackupPath)"
                Copy-Item -Path (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\boot.wim") -Destination $BootImageTempBackupPath -Force -ErrorAction Stop
            }

            Write-Verbose -Message "[Backup]: Successfully completed phase"

            try {
                Write-Verbose -Message "[OSImage]: Initiating OS image servicing phase"

                # Mount the temporary OS image
                Write-Verbose -Message " - Mounting temporary OS image file: $($OSImageTempWim)"
                Mount-WindowsImage -ImagePath $OSImageTempWim -Index 1 -Path $MountPathOSImage -ErrorAction Stop | Out-Null
    
                try {
                    if ($SkipServiceStackUpdatePatch -ne $true) {
                        # Attempt to apply required updates for OS image: Service Stack Update
                        Write-Verbose -Message " - Attempting to apply required patch in OS image for: Service Stack Update"
                        Write-Verbose -Message " - Currently processing: $($ServiceStackUpdateFilePath)"
                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
                    }
                    else {
                        Write-Verbose -Message " - Skipping Service Stack Update due to missing update file in sub-folder"
                        $ReturnValue = 0
                    }
    
                    if ($ReturnValue -eq 0) {
                        # Attempt to apply required updates for OS image: Cumulative Update
                        Write-Verbose -Message " - Attempting to apply required patch in OS image for: Cumulative Update"
                        Write-Verbose -Message " - Currently processing: $($CumulativeUpdateFilePath)"
                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
    
                        if ($ReturnValue -eq 0) {
                            if ($SkipOtherPatch -ne $true) {
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
                            else {
                                Write-Verbose -Message " - Skipping Other updates due to missing update files in sub-folder"
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
                                Write-Verbose -Message " - Attempting to perform a component cleanup and reset base of OS image"
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

                                            try {
                                                # Loop through the list of provisioned appx packages
                                                foreach ($App in $AppxProvisionedPackagesList) {
                                                    # Remove provisioned appx package if name not in white list
                                                    if (($App.DisplayName -in $WhiteListedApps)) {
                                                        Write-Verbose -Message " - Skipping excluded provisioned appx package: $($App.DisplayName)"
                                                    }
                                                    else {
                                                        # Attempt to remove AppxProvisioningPackage
                                                        Write-Verbose -Message " - Attempting to remove provisioned appx package from OS image: $($App.DisplayName)"
                                                        Remove-AppxProvisionedPackage -PackageName $App.DisplayName -Path $MountPathOSImage -ErrorAction Stop | Out-Null
                                                    }
                                                }
                                            }
                                            catch [System.Exception] {
                                                Write-Verbose -Message "Failed to remove provisioned appx package '$($App.DisplayName)' in OS image. Error message: $($_.Exception.Message)"
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
                                            
                                            if ($SkipServiceStackUpdatePatch -ne $true) {
                                                # Attempt to apply required updates for WinRE image: Service Stack Update
                                                Write-Verbose -Message " - Attempting to apply required patch in temporary WinRE image for: Service Stack Update"
                                                Write-Verbose -Message " - Currently processing: $($ServiceStackUpdateFilePath)"
                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathWinRE)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
                                            }
                                            else {
                                                Write-Verbose -Message " - Skipping Service Stack Update due to missing update file in sub-folder"
                                                $ReturnValue = 0
                                            }
                                            
                                            if ($ReturnValue -eq 0) {
                                                # Attempt to apply required updates for WinRE image: Cumulative Update
                                                Write-Verbose -Message " - Attempting to apply required patch in temporary WinRE image for: Cumulative Update"
                                                Write-Verbose -Message " - Currently processing: $($CumulativeUpdateFilePath)"
                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathWinRE)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
                                                
                                                if ($ReturnValue -eq 0) {
                                                    # Cleanup WinRE image
                                                    Write-Verbose -Message " - Attempting to perform a component cleanup and reset base of temporary WinRE image"
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

                                                                                            if ($SkipServiceStackUpdatePatch -ne $true) {
                                                                                                # Attempt to apply required updates for boot image: Service Stack Update
                                                                                                Write-Verbose -Message " - Attempting to apply required patch in temporary boot image for: Service Stack Update"
                                                                                                Write-Verbose -Message " - Currently processing: $($ServiceStackUpdateFilePath)"
                                                                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathBootImage)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
                                                                                            }
                                                                                            else {
                                                                                                $ReturnValue = 0
                                                                                            }

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
                                                                                                                Write-Verbose -Message "[OSImageFinal]: Initiating OS image final servicing phase"

                                                                                                                try {
                                                                                                                    Write-Verbose -Message " - Attempting to copy Dynamic Updates setup update files into OS media source file location"
                                                                                                                    $OSMediaSourcesPath = Join-Path -Path $OSMediaFilesPath -ChildPath "sources"
                                                                                                                    $UpdateDUSUExtractedFolders = Get-ChildItem -Path $DUSUExtractPath -Directory -ErrorAction Stop
                                                                                                                    foreach ($UpdateDUSUExtractedFolder in $UpdateDUSUExtractedFolders) {
                                                                                                                        Write-Verbose -Message " - Currently processing folder: $($UpdateDUSUExtractedFolder.FullName)"
                                                                                                                        Copy-Item -Path "$($UpdateDUSUExtractedFolder.FullName)\*" -Destination $OSMediaSourcesPath -Container -Force -Recurse -ErrorAction Stop
                                                                                                                    }
                                                                                                                }
                                                                                                                catch [System.Exception] {
                                                                                                                    Write-Warning -Message "Failed to copy Dynamic Updates setup update files into OS media source files. Error message: $($_.Exception.Message)"
                                                                                                                }

                                                                                                                Write-Verbose -Message "[OSImageFinal]: Successfully completed phase"

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
                            Write-Warning -Message "Failed to apply the Cumulative Update patch to OS image"
                        }
                    }
                    else {
                        Write-Warning -Message "Failed to apply the Service Stack Update patch to OS image"
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