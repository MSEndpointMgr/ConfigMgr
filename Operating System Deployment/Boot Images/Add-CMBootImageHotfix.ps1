<#
.SYNOPSIS
    Add a hotfix to Boot Images in Configuration Manager.

.DESCRIPTION
    This script will apply a hotfix (.msu file) to any number of given Boot Images in Configuration identified by their PackageID property.
    
    When running this script, it's important that the Windows operating system the script is executed from has a version of DISM.exe that supports 
    servicing the version of the Boot Images. Each Windows version has a corresponding Windows ADK release the Boot Images are created from. 
    Remember that DISM.exe is backwards compatible.

.PARAMETER SiteServer
    Site Server where the SMS Provider is installed.

.PARAMETER PackageID
    Specify a string or a string array of Boot Image PackageID's.

.PARAMETER Path
    Specify the full path to the hotfix that should be applied to the given Boot Image.

.PARAMETER MountPath
    Specify the full path for a temporary mount location. Should be an existing empty folder.

.PARAMETER RefreshPackage
    Invoke a package source update of the affected Boot Image(s).

.EXAMPLE
    # Apply a hotfix called 'windows10.0-kb4025632-x64.msu' to a Boot Image with PackageID 'P01000AB':
    .\Add-CMBootImageHotfix.ps1 -SiteServer CM01 -PackageID "P01000AB" -Path "C:\Temp\windows10.0-kb4025632-x64.msu" -MountPath "C:\Temp\Mount" -Verbose

    # Apply a hotfix called 'windows10.0-kb4025632-x64.msu' to multiple Boot Images with PackageID's 'P01000AB' and 'P01000BA':
    .\Add-CMBootImageHotfix.ps1 -SiteServer CM01 -PackageID "P01000AB", "P01000BA" -Path "C:\Temp\windows10.0-kb4025632-x64.msu" -MountPath "C:\Temp\Mount" -Verbose

    # Apply a hotfix called 'windows10.0-kb4025632-x64.msu' to a Boot Image with PackageID 'P01000AB' and refresh the Boot Image package with the changes made:
    .\Add-CMBootImageHotfix.ps1 -SiteServer CM01 -PackageID "P01000AB" -Path "C:\Temp\windows10.0-kb4025632-x64.msu" -MountPath "C:\Temp\Mount" -RefreshPackage -Verbose    

.NOTES
    FileName:    Add-CMBootImageHotfix.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-08-27
    Updated:     2017-08-27
    
    Version history:
    1.0.0 - (2017-08-27) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site Server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify a string or a string array of Boot Image PackageID's.")]
    [ValidatePattern("^[A-Z0-9]{3}[A-F0-9]{5}$")]
    [ValidateNotNullOrEmpty()]
    [string[]]$PackageID,

    [parameter(Mandatory=$true, HelpMessage="Specify the full path to the hotfix (.msu file) that should be applied to the given Boot Image.")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
	    # Check if path contains any invalid characters
	    if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
		    Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters" ; break
	    }
	    else {
	        # Check if file extension is MSU
		    if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".msu") {
			    return $true
		    }
		    else {
			    Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains unsupported file extension. Supported extension is '.msu'" ; break
		    }
	    }
    })]
    [string]$Path,

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
}
Process {
    # Process each passed PackageID object from parameter input
    foreach ($Package in $PackageID) {
        try {
            # Get Boot Image instance
            Write-Verbose -Message "Attempting to locate Boot Image with PackageID: $($Package)"
            $BootImagePackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_BootImagePackage -ComputerName $SiteServer -Filter "PackageID = '$($Package)'" -ErrorAction Stop
            if ($BootImagePackage -ne $null) {
                Write-Verbose -Message "Successfully located Boot Image with PackageID: $($Package)"

                # Get package source location for Boot Image
                $BootImagePath = $BootImagePackage.ImagePath
                Write-Verbose -Message "Current image path: $($BootImagePath)"

                try {
                    # Backup existing Boot Image baseline file (boot.wim)
                    $CurrentBootImageLocation = Split-Path -Path $BootImagePath -Parent
                    $CurrentBootImageFileName = Split-Path -Path $BootImagePath -Leaf
                    $BackupFileName = -join($CurrentBootImageFileName, ".", (Get-Date -format "yyyyMMdd"), ".bak")
                    Copy-Item -Path $BootImagePath -Destination (Join-Path -Path $CurrentBootImageLocation -ChildPath $BackupFileName) -Force -ErrorAction Stop -Verbose:$false
                    Write-Verbose -Message "Successfully backed up existing Boot Image baseline file"

                    # Validate mount folder exist, if not create it
                    if (-not(Test-Path -Path $MountPath -PathType Container)) {

                    }

                    try {
                        # Mount Boot Image to mount directory
                        Write-Verbose -Message "Attempting to mount '$($BootImagePackage.Name)' from: $($BootImagePath)"
                        $MountedImage = Mount-WindowsImage -ImagePath $BootImagePath -Path $MountPath -Index 1 -ErrorAction Stop -Verbose:$false
                        if (($MountedImage -ne $null) -and ($MountedImage.GetType().FullName -eq "Microsoft.Dism.Commands.ImageObject")) {
                            Write-Verbose -Message "Successfully mounted '$($BootImagePackage.Name)'"
                            
                            try {
                                # Inject hotfix into offline image
                                Write-Verbose -Message "Attempting to inject hotfix into Boot Image mount location: $($MountPath)"
                                $InjectPackage = Add-WindowsPackage -PackagePath $Path -Path $MountPath -ErrorAction Stop -Verbose:$false
                                if ($InjectPackage -ne $null) {
                                    Write-Verbose -Message "Successfully injected hotfix into mounted Boot Image"
                                }
                            }
                            catch [System.Exception] {
                                Write-Warning -Message "An error occurred while backing up Boot Image baseline file. Error message: $($_.Exception.Message)"
                            }

                            # Dismount boot image
                            $DismountedImage = Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop -Verbose:$false
                            if (($DismountedImage -ne $null) -and ($DismountedImage.GetType().FullName -eq "Microsoft.Dism.Commands.BaseDismObject")) {
                                Write-Verbose -Message "Successfully dismounted the Boot Image from mount directory"
                            }

                            # Refresh package source (re-creates the Boot Image)
                            if ($PSBoundParameters["RefreshPackage"]) {
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
}