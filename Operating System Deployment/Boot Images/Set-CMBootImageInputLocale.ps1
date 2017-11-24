<#
.SYNOPSIS
    Set the InputLocale property for a Boot Image in Configuration Manager.

.DESCRIPTION
    Set the InputLocale property for a Boot Image in Configuration Manager.

.PARAMETER SiteServer
    Site Server where the SMS Provider is installed.

.PARAMETER PackageID
    Specify the PackageID property of a Boot Image.

.PARAMETER Locale
    Specify the input locales that should be configured for this selected Boot Image, e.g. 'en-US' and 'sv-SE'.

.PARAMETER MountPath
    Specify the full path for a temporary mount location. Should be an existing empty folder.

.PARAMETER RefreshPackage
    Invoke a package source update of the affected Boot Image(s).

.EXAMPLE
    # Set the input locale to 'sv-SE' and 'en-US' for a Boot Image with PackageID 'P01000AB':
    .\Set-CMBootImageInputLocale.ps1 -SiteServer CM01 -PackageID "P01000AB" -Locale "sv-SE","en-US" -MountPath "C:\Temp\Mount" -Verbose

.NOTES
    FileName:    Set-CMBootImageInputLocale.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-11-13
    Updated:     2017-11-13
    
    Version history:
    1.0.0 - (2017-11-13) Script created
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

    [parameter(Mandatory=$true, HelpMessage="Specify the input locales that should be configured for this selected Boot Image, e.g. 'en-US' and 'sv-SE'.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("ar-sa", "bg-bg", "cs-cz", "da-dk", "de-de", "el-gr", "en-gb", "en-us", "es-es", "es-mx", "et-ee", "fi-fi", "fr-ca", "fr-fr", "he-il", "hr-hr", "hu-hu", "it-it", "ja-jp", "ko-kr", "lt-lt", "lv-lv", "nb-no", "nl-nl", "pl-pl", "pt-br", "pt-pt", "ro-ro", "ru-ru", "sk-sk", "sl-si", "sr-latn-rs", "sv-se", "th-th", "tr-tr", "uk-ua", "zh-cn", "zh-tw")]
    [string[]]$Locale,

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
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to detect Windows ADK installation location. Error message: $($_.Exception.Message)" ; break
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
                                # Combine list of locales
                                if ($Locale.Count -ge 2) {
                                    $Locales = $Locale -join ";"
                                }

                                # Set InputLocale for Boot Image
                                Write-Verbose -Message "Attempting to set input locale for mounted Boot Image: $($BootImagePath)"
                                $LocaleInvocation = Invoke-Executable -FilePath $DeploymentToolsDISMPath -Arguments "/Image:""$($MountPath)"" /Set-InputLocale:$($Locales)"
                                if ($LocaleInvocation -eq 0) {
                                    Write-Verbose -Message "Successfully set input locale for mounted Boot Image: $($BootImagePath)"
                                }
                            }
                            catch [System.Exception] {
                                Write-Warning -Message "An error occurred while configuring input locale for Boot Image: $($BootImagePath). Error message: $($_.Exception.Message)"
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
}