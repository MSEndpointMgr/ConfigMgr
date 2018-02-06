<#
.SYNOPSIS
    Add DaRT components to a Boot Image in Configuration Manager.

.DESCRIPTION
    Add DaRT components to a Boot Image in Configuration Manager. This script requires to be executed
    on a system with Windows ADK, MDT and DaRT installed.

.PARAMETER SiteServer
    Site Server where the SMS Provider is installed.

.PARAMETER PackageID
    Specify the PackageID property of a Boot Image.

.PARAMETER MountPath
    Specify the full path for a temporary mount location. Should be an existing empty folder.

.PARAMETER RefreshPackage
    Invoke a package source update of the affected Boot Image(s).

.EXAMPLE
    # Add the DaRT components to a Boot Image with PackageID P01000AB:
    .\Add-CMBootImageDaRTComponent.ps1 -SiteServer CM01 -PackageID "P01000AB" -MountPath "C:\Temp\Mount" -Verbose

.NOTES
    FileName:    Add-CMBootImageDaRTComponent.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-02-06
    Updated:     2018-02-06
    
    Version history:
    1.0.0 - (2018-02-06) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site Server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify the PackageID property of a Boot Image.")]
    [ValidatePattern("^[A-Z0-9]{3}[A-F0-9]{5}$")]
    [ValidateNotNullOrEmpty()]
    [string]$PackageID,

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
    [string]$MountPath,    

    [parameter(Mandatory=$false, HelpMessage="Invoke a package source update of the affected Boot Image(s).")]
    [switch]$UpdatePackage
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining Site Code for Site server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Verbose -Message "Site Code: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch {
        Write-Warning -Message "Unable to determine Site Code" ; break
    }

    # Detect if Windows ADK is installed, and determine installation location
    try {
        $ADKInstallPath = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots" -ErrorAction Stop | Select-Object -ExpandProperty KitsRoot*
        $DeploymentToolsDISMPath = Join-Path -Path $ADKInstallPath -ChildPath "Assessment and Deployment Kit\Deployment Tools\amd64\DISM\dism.exe"
        Write-Verbose -Message "Windows ADK installation path: $($ADKInstallPath)"
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to detect Windows ADK installation location. Error message: $($_.Exception.Message)" ; break
    }

    # Detect if MDT is installed, and determine installation location
    try {
        $MDTInstallPath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Deployment 4" -ErrorAction Stop | Select-Object -ExpandProperty "Install_Dir").TrimEnd("\")
        Write-Verbose -Message "MDT installation path: $($MDTInstallPath)"
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to detect MDT installation location. Error message: $($_.Exception.Message)" ; break
    }

    # Detect if DaRT is installed, and determine installation location
    try {
        $DaRTInstallPath = (Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\DaRT" -ErrorAction Stop | Get-ItemProperty -ErrorAction Stop | Select-Object -ExpandProperty "InstallPath").TrimEnd("\")
        Write-Verbose -Message "DaRT installation path: $($DaRTInstallPath)"
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to detect MDT installation location. Error message: $($_.Exception.Message)" ; break
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
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message ; break
        }

        return $Invocation.ExitCode
    }

    # Process each passed PackageID object from parameter input
    try {
        # Get Boot Image instance
        Write-Verbose -Message "Attempting to locate Boot Image with PackageID: $($PackageID)"
        $BootImagePackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_BootImagePackage -ComputerName $SiteServer -Filter "PackageID = '$($PackageID)'" -ErrorAction Stop
        if ($BootImagePackage -ne $null) {
            Write-Verbose -Message "Successfully located Boot Image with PackageID: $($PackageID)"

            # Get package source location for Boot Image
            $BootImagePath = $BootImagePackage.ImagePath
            Write-Verbose -Message "Current image path: $($BootImagePath)"

            # Determine Boot Image architecture for DaRT component file association
            switch ($BootImagePackage.Architecture) {
                9 {
                    $FileName = "Toolsx64.cab"
                }
                0 {
                    $FileName = "Toolsx86.cab"
                }
            }

            try {
                # Backup existing Boot Image baseline file (boot.wim)
                $CurrentBootImageLocation = Split-Path -Path $BootImagePath -Parent
                $CurrentBootImageFileName = Split-Path -Path $BootImagePath -Leaf
                $BackupFileName = -join($CurrentBootImageFileName, ".", (Get-Date -format "yyyyMMdd"), ".bak")
                Copy-Item -Path $BootImagePath -Destination (Join-Path -Path $CurrentBootImageLocation -ChildPath $BackupFileName) -Force -ErrorAction Stop -Verbose:$false
                Write-Verbose -Message "Successfully backed up existing Boot Image baseline file"

                # Validate mount folder exist, if not create it
                if (-not(Test-Path -Path $MountPath -PathType Container)) {
                    try {
                        New-Item -Path $MountPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "An error occurred while creating the mount folder. Error message: $($_.Exception.Message)" ; break
                    }
                }

                try {
                    # Mount Boot Image to mount directory
                    Write-Verbose -Message "Attempting to mount '$($BootImagePackage.Name)' from: $($BootImagePath)"

                    $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Mount-Image /ImageFile:""$($BootImagePath)"" /Index:1 /MountDir:""$($MountPath)"""
                    if ($ReturnValue -eq 0) {
                        Write-Verbose -Message "Successfully mounted '$($BootImagePackage.Name)'"

                        try {
                            # Build DaRT component path
                            $DaRTComponent = Join-Path -Path $DaRTInstallPath -ChildPath $FileName
                            Write-Verbose -Message "Path to DaRT component to be injected: $($DaRTComponent)"

                            # Validate path to DaRT component exist
                            if (Test-Path -Path $DaRTComponent) {
                                # Inject DaRT component into offline image
                                Write-Verbose -Message "Attempting to inject DaRT component into Boot Image mount location: $($MountPath)"
                                $ExpandComponent = Invoke-Executable -FilePath "expand.exe" -Arguments """$($DaRTComponent)"" -F:*.* ""$($MountPath)"""
                                if ($ExpandComponent -eq 0) {
                                    Write-Verbose -Message "Successfully injected DaRT component into mounted Boot Image"
                                }
                                else {
                                    Write-Warning -Message "An error occurred while expanding DaRT components into mounted Boot Image. Exit code: $($ExpandComponent)"
                                }
                            }
                            else {
                                Write-Warning -Message "Unable to locate DaRT component cabinet file"; break
                            }
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "An error occurred while injecting DaRT component for Boot Image: $($BootImagePath). Error message: $($_.Exception.Message)"
                        }

                        try {
                            # Copy DartConfig.dat to mounted boot image path
                            Write-Verbose -Message "Attempting to copy DartConfig.dat into Boot Image mount location: $($MountPath)"

                            Copy-Item -Path (Join-Path -Path $MDTInstallPath -ChildPath "\Templates\DartConfig8.dat") -Destination (Join-Path -Path $MountPath -ChildPath "\Windows\System32\DartConfig.dat") -ErrorAction Stop
                            Write-Verbose -Message "Succssfully copied DartConfig.dat into Boot Image mount location"
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "An error occurred while injecting optional component for Boot Image: $($BootImagePath). Error message: $($_.Exception.Message)"
                        }                        

                        # Dismount boot image
                        Write-Verbose -Message "Attempting to dismount '$($BootImagePackage.Name)' from: $($MountPath)"
                        $ReturnValue = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Unmount-Image /MountDir:""$($MountPath)"" /Commit"
                        if ($ReturnValue -eq 0) {
                            Write-Verbose -Message "Successfully dismounted the Boot Image from mount directory"
                        }

                        # Refresh package source (re-creates the Boot Image)
                        if ($PSBoundParameters["UpdatePackage"]) {
                            Write-Verbose -Message "Attempting to refresh the Boot Image package, this operation will take some time"
                            $BootImagePackage.Get()
                            $InvocationUpdatePackage = $BootImagePackage.RefreshPkgSource()

                            # Validate return value from package update
                            if ($InvocationUpdatePackage.ReturnValue -eq 0) {
                                Write-Verbose -Message "Successfully refreshed the Boot Image package"
                            }
                        }
                    }
                    else {
                        Write-Warning -Message "Failed to mount the Boot Image"
                    }
                }
                catch {
                    Write-Warning -Message "An error occured while attempting to mount the Boot Image. Error message: $($_.Exception.Message)"
                }                    
            }
            catch [System.Exception] {
                Write-Warning -Message "An error occurred while backing up Boot Image baseline file. Error message: $($_.Exception.Message)"
            }
        }
        else {
            Write-Verbose -Message "Unable to locate a Boot Image with given PackageID, please enter a valid PackageID as identification of an existing Boot Image"
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "An unauthorized access exception occurred. Error message: $($_.Exception.Message)"
    }
    catch {
        Write-Warning -Message "An error occurred. Error message: $($_.Exception.Message)"
    }
}