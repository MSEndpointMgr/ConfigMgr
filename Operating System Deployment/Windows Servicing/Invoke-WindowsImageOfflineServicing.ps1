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

    Original servicing logic is using the same as published here:
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

    This script has been tested on the following platforms:
    - Windows Server 2012 R2
    - Windows Server 2016

.PARAMETER OSMediaFilesPath
    Specify the full path for the location of the Windows 10 installation media files. Should be an existing folder.

.PARAMETER MountPathRoot
    Specify the full path for a temporary mount location. Should be an existing empty folder.

.PARAMETER UpdateFilesRoot
    Specify the full path for the updates folder structure.

.PARAMETER OSEdition
    Specify the image edition property to be extracted from the OS image.

.PARAMETER IncludeNetFramework
    Include .NET Framework 3.5.1 when servicing the OS image.

.PARAMETER RemoveAppxPackages
    Remove built-in provisioned appx packages when servicing the OS image.

.EXAMPLE
    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageOfflineServicing.ps1 -OSMediaFilesPath "C:\Temp\OSSourceFiles" -MountPathRoot "C:\Temp\MountPath" -UpdateFilesRoot "C:\Temp\Updates"

    # Service a Windows Education image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player:
    .\Invoke-WindowsImageOfflineServicing.ps1 -OSMediaFilesPath "C:\Temp\OSSourceFiles" -MountPathRoot "C:\Temp\MountPath" -UpdateFilesRoot "C:\Temp\Updates" -OSEdition "Education"

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1:
    .\Invoke-WindowsImageOfflineServicing.ps1 -OSMediaFilesPath "C:\Temp\OSSourceFiles" -MountPathRoot "C:\Temp\MountPath" -UpdateFilesRoot "C:\Temp\Updates" -IncludeNetFramework

    # Service a Windows Enterprise image from source files location with latest Cumulative Update, Service Stack Update and e.g. Adobe Flash Player and include .NET Framework 3.5.1 and remove provisioned Appx packages:
    .\Invoke-WindowsImageOfflineServicing.ps1 -OSMediaFilesPath "C:\Temp\OSSourceFiles" -MountPathRoot "C:\Temp\MountPath" -UpdateFilesRoot "C:\Temp\Updates" -IncludeNetFramework -RemoveAppxPackages

.NOTES
    FileName:    Invoke-WindowsImageOfflineServicing.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2019-09-12
    Updated:     2019-09-16
    
    Version history:
    1.0.0 - (2019-09-12) Script created
    1.0.1 - (2019-09-16) Added support to remove appx packages from OS image
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Specify the full path for the location of the Windows 10 installation media files. Should be an existing folder.")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
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
    [string]$OSMediaFilesPath,

    [parameter(Mandatory=$true, HelpMessage="Specify the full path for a temporary mount location. Should be an existing empty folder.")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
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
    [string]$MountPathRoot,

    [parameter(Mandatory=$true, HelpMessage="Specify the full path for the updates folder structure.")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
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
    [string]$UpdateFilesRoot,

    [parameter(Mandatory=$false, HelpMessage="Specify the image edition property to be extracted from the OS image.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Enterprise", "Education")]
    [string]$OSEdition = "Enterprise",

    [parameter(Mandatory=$false, HelpMessage="Include .NET Framework 3.5.1 when servicing the OS image.")]
    [switch]$IncludeNetFramework,

    [parameter(Mandatory=$false, HelpMessage="Remove built-in provisioned appx packages when servicing the OS image.")]
    [switch]$RemoveAppxPackages    
)
Begin {
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
            [parameter(Mandatory=$true, HelpMessage="Specify the file name or path of the executable to be invoked, including the extension")]
            [ValidateNotNullOrEmpty()]
            [string]$FilePath,
    
            [parameter(Mandatory=$false, HelpMessage="Specify arguments that will be passed to the executable")]
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
            Write-Warning -Message $_.Exception.Message ; break
        }
    
        return $Invocation.ExitCode
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

    Write-Verbose -Message " - Windows image offline servicing is starting"

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
                    Write-Verbose -Message " - Found the following updates in the 'Other' folder: $($OtherUpdateFilePath)"
                }
            }
        }
    }
    else {
        Write-Warning -Message "Unable to locate required 'Other' subfolder in the update files root location. Please create it manually and add the latest Adobe Flash update inside the folder"; break
    }

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
        # Export selected OS image edition from OS media files location to a temporary image
        $OSImageTempWim = Join-Path -Path $ImagePathTemp -ChildPath "install_temp.wim"
        Export-WindowsImage -SourceImagePath $OSInstallWim -DestinationImagePath $OSImageTempWim -SourceName "Windows 10 $($OSEdition)" -ErrorAction Stop | Out-Null

        try {
            Write-Verbose -Message "[Backup]: Initiating backup phase"
            # Backup existing OS image install.wim file to temporary location
            Write-Verbose -Message " - Backing up install.wim from OS media source files location: $($OSMediaFilesPath)"
            Copy-Item -Path (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\install.wim") -Destination (Join-Path -Path $ImagePathTemp -ChildPath "install_$((Get-Date).ToShortDateString()).wim.bak") -Force -ErrorAction Stop

            # Backup existing OS image boot.wim file to temporary location
            Write-Verbose -Message " - Backing up boot.wim from OS media source files location: $($OSMediaFilesPath)"
            Copy-Item -Path (Join-Path -Path $OSMediaFilesPath -ChildPath "sources\boot.wim") -Destination (Join-Path -Path $ImagePathTemp -ChildPath "boot_$((Get-Date).ToShortDateString()).wim.bak") -Force -ErrorAction Stop
            Write-Verbose -Message "[Backup]: Successfully completed phase"

            try {
                Write-Verbose -Message "[OSImage]: Initiating OS image servicing phase"

                # Mount the temporary OS image
                Write-Verbose -Message " - Mounting temporary OS image file: $($OSImageTempWim)"
                Mount-WindowsImage -ImagePath $OSImageTempWim -Index 1 -Path $MountPathOSImage -Optimize -ErrorAction Stop | Out-Null
    
                try {
                    # Attempt to apply required updates for OS image: Service Stack Update
                    Write-Verbose -Message " - Attempting to apply required patch in OS image for: Service Stack Update"
                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
    
                    if ($ReturnValue -eq 0) {
                        # Attempt to apply required updates for OS image: Cumulative Update
                        Write-Verbose -Message " - Attempting to apply required patch in OS image for: Cumulative Update"
                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
    
                        if ($ReturnValue -eq 0) {
                            if ($SkipOtherPatch -ne $true) {
                                # Attempt to apply required updates for OS image: Other
                                Write-Verbose -Message " - Attempting to apply required patch in OS image for: Other"
                                foreach ($OtherUpdateFilePath in $OtherUpdateFilePaths) {
                                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($OtherUpdateFilePath)"""
                                    if ($ReturnValue -ne 0) {
                                        Write-Warning -Message "Failed to apply required patch in OS image for: $($OtherUpdateFilePath)"
                                    }
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
                                        $OSMediaSourcesPath = Join-Path -Path $OSMediaFilesPath -ChildPath "sources\sxs"
                                        Write-Verbose -Message " - Attempting to apply .NET Framework 3.5.1 in OS image"
                                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess /Source:""$($OSMediaSourcesPath)"""
    
                                        if ($ReturnValue -eq 0) {
                                            # Attempt to re-apply (because of .NET Framework requirements) required updates for OS image: Cumulative Update
                                            Write-Verbose -Message " - Attempting to re-apply Cumulative Update after .NET Framework 3.5.1 injection"
                                            $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathOSImage)"" /Add-Package /PackagePath:""$($CumulativeUpdateFilePath)"""
    
                                            if ($ReturnValue -eq 0) {
                                                Write-Verbose -Message " - Successfully re-applied the Cumulative Update patch to OS image"
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
                                                Write-LogEntry -Value "Failed to remove provisioned appx package '$($App.DisplayName)' in OS image. Error message: $($_.Exception.Message)"
                                            }
                                        }
                                        catch [System.Exception] {
                                            Write-LogEntry -Value "Failed to retrieve provisioned appx package in OS image. Error message: $($_.Exception.Message)"
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
                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathWinRE)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
                                            }
                                            else {
                                                $ReturnValue = 0
                                            }
                                            
                                            if ($ReturnValue -eq 0) {
                                                # Attempt to apply required updates for WinRE image: Cumulative Update
                                                Write-Verbose -Message " - Attempting to apply required patch in temporary WinRE image for: Cumulative Update"
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
                                                                Write-Verbose -Message " - Attempting to export temporary WinRE image to OS media source files location"
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
                                                                                                $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPathBootImage)"" /Add-Package /PackagePath:""$($ServiceStackUpdateFilePath)"""
                                                                                            }
                                                                                            else {
                                                                                                $ReturnValue = 0
                                                                                            }

                                                                                            if ($ReturnValue -eq 0) {
                                                                                                # Attempt to apply required updates for boot image: Cumulative Update
                                                                                                Write-Verbose -Message " - Attempting to apply required patch in temporary boot image for: Cumulative Update"
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

            Write-Verbose -Message "[Cleanup]: Successfully completed temporary servicing cleanup files"
        }
        else {
            Write-Verbose -Message " - There were no image files that needs to be removed"
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Failed to remove temporary image files. Error message: $($_.Exception.Message)"
    }
}