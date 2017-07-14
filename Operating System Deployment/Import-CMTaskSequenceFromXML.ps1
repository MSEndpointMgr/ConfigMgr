<#
.SYNOPSIS
    Import a specific Task Sequence from a XML file, or multiple Task Sequences from XML files located in a specific folder into ConfigMgr

.DESCRIPTION
    This script allows for import of a specific Task Sequence from a XML file, or multiple Task Sequences from XML files located in a specific folder into ConfigMgr.
    The XML files needs to have been exported by the Export-CMTaskSequenceToXML.ps1 script, since the native import function in ConfigMgr relies on
    a completely different file and XML Document structure.

    Note: References for Applications are not supported when using this import method. Packages and other types are however supported.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER File
    Specify a local path to a XML file that contains the required sequence data.

.PARAMETER Path
    Specify a local path to a folder that contains XML files with required sequence data.

.PARAMETER BootImageID
    Specify the Boot Image PackageID that will be associated with the imported Task Sequence.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    Import a Task Sequence from a XML file called 'Windows 10 Enterprise 1511 x64.xml' in 'C:\Import' and associate a Boot Image with PackageID 'P0100012', on a Primary Site server called 'CM01':
    .\Import-CMTaskSequenceFromXML.ps1 -SiteServer CM01 -File "C:\Import\Windows 10 Enterprise 1511 x64.xml" -BootImageID P0100012

    Import multiple Task Sequences from 'C:\Import' and associate a Boot Image with PackageID 'P0100012', on a Primary Site server called 'CM01':
    .\Import-CMTaskSequenceFromXML.ps1 -SiteServer CM01 -Path "C:\Import" -BootImageID P0100012 -ShowProgress

.NOTES
    FileName:    Import-CMTaskSequenceFromXML.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2016-05-25
    Updated:     2016-05-25
    Version:     1.0.0
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.", ParameterSetName="SingleInstance")]
    [parameter(Mandatory=$true, ParameterSetName="Recursive")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify a local path to a XML file that contains the required sequence data.", ParameterSetName="SingleInstance")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
	    # Check if path contains any invalid characters
	    if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
		    Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters" ; break
	    }
	    else {
            # Check if file exists
		    if (-not(Test-Path -Path $_ -ErrorAction SilentlyContinue)) {
			    Write-Warning -Message "Unable to locate specified file" ; break
            }
            else {
	            # Check if file extension is XML
		        if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".xml") {
			        return $true
		        }
		        else {
			        Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains unsupported file extension. Supported extension is '.xml'" ; break
		        }
            }
	    }
    })]
    [string]$File,

    [parameter(Mandatory=$true, HelpMessage="Specify a local path to a folder that contains XML files with required sequence data.", ParameterSetName="Recursive")]
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

    [parameter(Mandatory=$false, HelpMessage="Specify the Boot Image PackageID that will be associated with the imported Task Sequence.", ParameterSetName="SingleInstance")]
    [parameter(Mandatory=$false, ParameterSetName="Recursive")]
    [ValidateNotNullOrEmpty()]
    [string]$BootImageID = $null,

    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation.", ParameterSetName="Recursive")]
    [switch]$ShowProgress
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
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Site Code" ; break
    }

    # Validate BootImageID
    if ($BootImageID -ne $null) {
        try {
            $BootImage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_BootImagePackage -ComputerName $SiteServer -Filter "PackageID like '$($BootImageID)'" -ErrorAction Stop
            if ($BootImage -ne $null) {
                $BootImageID = $BootImage.PackageID
            }
            else {
                Write-Warning -Message "Unable to determine Boot Image ID, please verify that you've specified an existing Boot Image" ; break
            }
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message ; break
        }
    }
}
Process {
    # Functions
    function Import-TaskSequence {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlNode]$XML,

            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$TaskSequenceName
        )
        Process {
            # Validate Task Sequence Name is unique
            $TaskSequenceValidate = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Filter "Name like '$($TaskSequenceName)'"
            if ($TaskSequenceValidate -eq $null) {
                # Convert XML Document to SMS_TaskSequencePackage WMI object
                try {
                    Write-Verbose -Message "Attempting to convert XML Document for '$($TaskSequenceName)' to Task Sequence Package WMI object"
                    $TaskSequence = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "ImportSequence" -ArgumentList $XML.OuterXml -ErrorAction Stop
                }
                catch [System.Exception] {
                    Write-Warning -Message "Unable to convert XML Document for '$($TaskSequenceName)' to Task Sequence Package WMI object" ; break
                }

                # Create new SMS_TaskSequencePackage WMI object
                try {
                    Write-Verbose -Message "Attempting to create new Task Sequence Package instance for '$($TaskSequenceName)'"
                    $ErrorActionPreference = "Stop"
                    $TaskSequencePackageInstance = ([WmiClass]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_TaskSequencePackage").CreateInstance()
                    $TaskSequencePackageInstance.Name = $TaskSequenceName
                    $TaskSequencePackageInstance.BootImageID = $Script:BootImageID
                    $ErrorActionPreference = "Continue"
                }
                catch [System.Exception] {
                    Write-Warning -Message "Unable to create new Task Sequence Package instance for '$($TaskSequenceName)'" ; break
                }

                # Set Task Sequence
                try {
                    Write-Verbose -Message "Attempting to import '$($TaskSequenceName)' Task Sequence"
                    $TaskSequenceImport = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "SetSequence" -ArgumentList @($TaskSequence.TaskSequence, $TaskSequencePackageInstance) -ErrorAction Stop
                }
                catch [System.Exception] {
                    Write-Warning -Message "Unable to set $($TaskSequenceName) Task Sequence" ; break
                }
            }
            else {
                Write-Warning -Message "Duplicate Task Sequence name detected. Existing Task Sequence with name '$($TaskSequenceName)' PackageID '$($TaskSequenceValidate.PackageID)' already exists"
            }
        }
    }

    # Set ProgressCount for ShowProgress
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }

    switch ($PSCmdlet.ParameterSetName) {
        "SingleInstance" {
            # Determine Task Sequence name
            try {
                $TaskSequenceName = Get-Item -LiteralPath $File -ErrorAction Stop | Select-Object -ExpandProperty BaseName
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to determine Task Sequence name from '$($File)'" ; break
            }

            # Load XML from file
            try {
                Write-Verbose -Message "Loading XML Document from '$($File)'"
                $TaskSequenceXML = [xml](Get-Content -LiteralPath $File -Encoding UTF8 -ErrorAction Stop)
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to load XML Document from '$($File)'" ; break
            }

            # Import Task Sequence from file if validated
            if ($TaskSequenceXML.Sequence.HasChildNodes) {
                Import-TaskSequence -XML $TaskSequenceXML -TaskSequenceName $TaskSequenceName
            }
            else {
                Write-Warning -Message "XML file '$($File)', could not be validated successfully" ; break
            }
        }
        "Recursive" {
            # Gather all XML files in specified path
            try {
                Write-Verbose -Message "Gathering XML files from '$($Path)'"
                $XMLFiles = Get-ChildItem -LiteralPath $Path -Filter *.xml -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to gather XML files in '$($Path)'" ; break
            }

            # Import Task Sequences from XML files
            if ($XMLFiles -ne $null) {
                # Determine count of XML files
                $XMLFilesCount = ($XMLFiles | Measure-Object).Count

                # Process each XML file
                foreach ($XMLFile in $XMLFiles) {
                    # Determine Task Sequence name
                    try {
                        $TaskSequenceName = Get-Item -LiteralPath $XMLFile.FullName -ErrorAction Stop | Select-Object -ExpandProperty BaseName
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Unable to determine Task Sequence name from '$($XMLFile.FullName)'" ; break
                    }

                    # Show progress
                    if ($PSBoundParameters["ShowProgress"]) {
                        $ProgressCount++
                        Write-Progress -Activity "Importing Task Sequences" -Id 1 -Status "$($ProgressCount) / $($XMLFilesCount)" -CurrentOperation "Current Task Sequence: $($TaskSequenceName)" -PercentComplete (($ProgressCount / $XMLFilesCount) * 100)
                    }

                    # Load XML from file
                    try {
                        Write-Verbose -Message "Loading XML Document from '$($XMLFile.FullName)'"
                        $TaskSequenceXML = [xml](Get-Content -LiteralPath $XMLFile.FullName -Encoding UTF8 -ErrorAction Stop)
                    }
                    catch [System.Exception] {
                        Write-Warning -Message "Unable to load XML Document from '$($File)'" ; break
                    }

                    # Import Task Sequence from file if validated
                    if ($TaskSequenceXML.Sequence.HasChildNodes) {
                        Import-TaskSequence -XML $TaskSequenceXML -TaskSequenceName $TaskSequenceName
                    }
                    else {
                        Write-Warning -Message "XML file '$($XMLFile.FullName)', could not be validated successfully" ; break
                    }
                }
            }
        }
    }
}