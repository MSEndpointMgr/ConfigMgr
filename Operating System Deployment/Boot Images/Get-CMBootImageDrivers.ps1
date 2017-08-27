<#
.SYNOPSIS
    List all drivers that has been added to a specific Boot Image in ConfigMgr 2012
.DESCRIPTION
    This script will list all the drivers added to a Boot Image in ConfigMgr 2012. It's also possible to list
    Microsoft standard drivers by specifying the All parameter.
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER BootImageName
    Specify the Boot Image name as a string or an array of strings
.PARAMETER MountPath
    Default path to where the script will temporarly mount the Boot Image
.PARAMETER All
    When specified all drivers will be listed, including default Microsoft drivers
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    .\Get-CMBootImageDrivers.ps1 -SiteServer CM01 -BootImageName "Boot Image (x64)" -MounthPath C:\Temp\MountFolder
    List all drivers in a Boot Image named 'Boot Image (x64)' on a Primary Site server called CM01:
.NOTES
    Script name: Get-CMBootImageDrivers.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-05-06
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, ParameterSetName="ConfigMgr", HelpMessage="Site server where the SMS Provider is installed")]
    [parameter(ParameterSetName="WIM")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,
    [parameter(Mandatory=$true, ParameterSetName="ConfigMgr", HelpMessage="Specify the Boot Image name as a string or an array of strings")]
    [ValidateNotNullOrEmpty()]
    [string[]]$BootImageName,
    [parameter(Mandatory=$true, ParameterSetName="WIM", HelpMessage="Specify the path to a WIM file")]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters" ; break
        }
        else {
            # Check if file extension is WIM
            if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".wim") {
                # Check if the whole directory path exists
                if (-not(Test-Path -Path (Split-Path -Path $_) -PathType Container -ErrorAction SilentlyContinue)) {
                    if ($PSBoundParameters["Force"]) {
                        New-Item -Path (Split-Path -Path $_) -ItemType Directory | Out-Null
                        return $true
                    }
                    else {
                        Write-Warning -Message "Unable to locate part of the specified path" ; break
                    }
                }
                elseif (Test-Path -Path (Split-Path -Path $_) -PathType Container -ErrorAction SilentlyContinue) {
                    return $true
                }
                else {
                    Write-Warning -Message "Unhandled error" ; break
                }
            }
            else {
                Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains unsupported file extension. Supported extension is '.wim'" ; break
            }
        }
    })]
    [ValidateNotNullOrEmpty()]
    [string]$WimFile,
    [parameter(Mandatory=$true, ParameterSetName="ConfigMgr", HelpMessage="Default path to where the script will temporarly mount the Boot Image")]
    [parameter(ParameterSetName="WIM")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+")]
    [string]$MountPath,
    [parameter(Mandatory=$false, ParameterSetName="ConfigMgr", HelpMessage="When specified all drivers will be listed, including default Microsoft drivers")]
    [parameter(ParameterSetName="WIM")]
    [switch]$All,
    [parameter(Mandatory=$false, ParameterSetName="ConfigMgr", HelpMessage="Show a progressbar displaying the current operation")]
    [parameter(ParameterSetName="WIM")]
    [switch]$ShowProgress
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Debug -Message "SiteCode: $($SiteCode)"
            }
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine SiteCode" ; break
    }
    # Determine if we need to load the Dism PowerShell module
    if (-not(Get-Module -Name Dism)) {
        try {
            Import-Module -Name Dism -ErrorAction Stop -Verbose:$false
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to load the Dism PowerShell module" ; break
        }
    }
    # Determine if temporary mount folder is accessible, if not create it
    if (-not(Test-Path -Path $MountPath -PathType Container -ErrorAction SilentlyContinue -Verbose:$false)) {
        New-Item -Path $MountPath -ItemType Directory -Force -Verbose:$false | Out-Null
    }
}
Process {
    # Functions
    function Get-BootImageDrivers {
        [CmdletBinding(SupportsShouldProcess=$true)]
        param(
            [parameter(Mandatory=$true)]
            $BootImage
        )
        # Get all drivers in the mounted Boot Image
        $WindowsDriverArguments = @{
            Path = $MountPath
            ErrorAction = "Stop"
            Verbose = $false
        }
        if ($Script:PSBoundParameters["All"]) {
            $WindowsDriverArguments.Add("All", $true)
        }
        if ($Script:PSCmdlet.ShouldProcess($MountPath, "ListDrivers")) {
            $Drivers = Get-WindowsDriver @WindowsDriverArguments
            if ($Drivers -ne $null) {
                $DriverCount = ($Drivers | Measure-Object).Count
                foreach ($Driver in $Drivers) {
                    if ($Script:PSBoundParameters["ShowProgress"]) {
                        $ProgressCount++
                        Write-Progress -Activity "Enumerating drivers in '$($BootImage)'" -Id 1 -Status "Processing $($ProgressCount) / $($DriverCount)" -PercentComplete (($ProgressCount / $DriverCount) * 100)
                    }
                    $PSObject = [PSCustomObject]@{
                        Driver = $Driver.Driver
                        Version = $Driver.Version
                        Manufacturer = $Driver.ProviderName
                        ClassName = $Driver.ClassName
                        Date = $Driver.Date
                        BootImageName = $BootImage.Name
                    }
                    Write-Output -InputObject $PSObject
                }
                if ($Script:PSBoundParameters["ShowProgress"]) {
                    Write-Progress -Activity "Enumerating drivers in '$($BootImage)'" -Id 1 -Completed
                }
            }
            else {
                Write-Warning -Message "No drivers was found"
            }
        }
    }
    # ProgressCount
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
    # Enumerate trough all specified boot image names
    if ($PSBoundParameters["BootImageName"]) {
        foreach ($BootImageItem in $BootImageName) {
            try {
                Write-Verbose -Message "Querying for boot image: $($BootImageItem)"
                $BootImage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_BootImagePackage -ComputerName $SiteServer -Filter "Name like '$($BootImageItem)'" -ErrorAction Stop
                if ($BootImage -ne $null) {
                    $BootImagePath = $BootImage.PkgSourcePath
                    Write-Verbose -Message "Located boot image wim file: $($BootImagePath)"
                    # Mount Boot Image to temporary mount folder
                    if ($PSCmdlet.ShouldProcess($BootImagePath, "Mount")) {
                        Mount-WindowsImage -ImagePath $BootImagePath -Path $MountPath -Index 1 -ErrorAction Stop -Verbose:$false | Out-Null
                    }
                    # List drivers in Boot Image
                    Get-BootImageDrivers -BootImage $BootImage.Name
                }
                else {
                    Write-Warning -Message "Unable to locate a boot image called '$($BootImageName)'"
                }
            }
            catch [System.UnauthorizedAccessException] {
                Write-Warning -Message "Access denied" ; break
            }
            catch [System.Exception] {
                Write-Warning -Message $_.Exception.Message ; break
            }
            # Dismount the boot image
            if ($PSCmdlet.ShouldProcess($BootImagePath, "Dismount")) {
                Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop -Verbose:$false | Out-Null
            }
        }
    }
    # Enumerate through the specified wim file
    if ($PSBoundParameters["WimFile"]) {
        # Mount Boot Image to temporary mount folder
        try {
            if ($PSCmdlet.ShouldProcess($WimFile, "Mount")) {
                Mount-WindowsImage -ImagePath $WimFile -Path $MountPath -Index 1 -ErrorAction Stop -Verbose:$false | Out-Null
            }
            # List drivers in Boot Image
            Get-BootImageDrivers -BootImage (Split-Path -Path $WimFile -Leaf)
        }
        catch [System.UnauthorizedAccessException] {
            Write-Warning -Message "Access denied" ; break
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message ; break
        }
        # Dismount the boot image
        if ($PSCmdlet.ShouldProcess($WimFile, "Dismount")) {
            Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction Stop -Verbose:$false | Out-Null
        }
    }
}
End {
    # Clean up mount folder
    try {
        Remove-Item -Path $MountPath -Force -ErrorAction Stop -Verbose:$false
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied"
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    }
}