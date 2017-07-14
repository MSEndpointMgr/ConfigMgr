<#
.SYNOPSIS
    Export all or a specific Task Sequence in ConfigMgr to a XML file

.DESCRIPTION
    This script allows for exporting of all or a specific Task Sequence determined by Package ID to a XML file. The exported Task Sequences
    can only be imported again by using the Import-CMTaskSequenceFromXML.ps1 script file, since the native import function in ConfigMgr relies on
    a completely different file and XML Document structure. The XML Document export with this script is the actual sequence of a Task Sequence.

    Note: References for Applications are not supported when using this export method. Packages and other types are however supported.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER PackageID
    Specify a PackageID for a Task Sequence that will be exported.

.PARAMETER All
    Export all Task Sequences.

.PARAMETER Path
    Specify an existing valid path to where the file will be stored.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    Export a specific Task Sequence with PackageID 'P01000CF' to 'C:\Export', on a Primary Site server called 'CM01':
    .\Export-CMTaskSequenceToXML.ps1 -SiteServer CM01 -PackageID P01000CF -Path C:\Export

    Export all Task Sequences to 'C:\Export' and show the current progress, on a Primary Site server called 'CM01':
    .\Export-CMTaskSequenceToXML.ps1 -SiteServer CM01 -All -Path C:\Export -ShowProgress

.NOTES
    FileName:    Export-CMTaskSequenceToXML.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2016-05-25
    Updated:     2016-05-25
    Version:     1.0.0
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.", ParameterSetName="SingleInstance")]
    [parameter(Mandatory=$true, ParameterSetName="AllInstances")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify a PackageID for a Task Sequence that will be exported.", ParameterSetName="SingleInstance")]
    [ValidateNotNullOrEmpty()]
    [string]$PackageID,

    [parameter(Mandatory=$true, HelpMessage="Export all Task Sequences.", ParameterSetName="AllInstances")]
    [ValidateNotNull()]
    [switch]$All,

    [parameter(Mandatory=$true, HelpMessage="Specify an existing valid path to where the file will be stored.", ParameterSetName="SingleInstance")]
    [parameter(Mandatory=$true, ParameterSetName="AllInstances")]
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

    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation.", ParameterSetName="AllInstances")]
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
}
Process {
    # Functions
    function Export-TaskSequence {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [System.Management.ManagementBaseObject]$TaskSequencePackage
        )
        Process {
            # Determine Task Sequence name that will be used for the name of the XML file
            $XMLFileName = ($TaskSequencePackage | Select-Object -ExpandProperty Name) + ".xml"

            # Get deserialized sequence as SMS_TaskSequence WMI object from SMS_TaskSequencePackage object
            try {
                Write-Verbose -Message "Attempting to deserialize sequence for Task Sequence Package '$($TaskSequencePackage.Name)'"
                $TaskSequence = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Name "GetSequence" -ArgumentList $TaskSequencePackage -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to deserialize sequence for Task Sequence Package: '$($TaskSequencePackage.Name)'" ; break
            }

            # Convert deserialized sequence to a XML Document
            try {
                Write-Verbose -Message "Attempting to convert sequence for Task Sequence Package '$($TaskSequencePackage.Name)' to XML Document"
                $TaskSequenceResult = Invoke-WmiMethod -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequence -ComputerName $SiteServer -Name "SaveToXml" -ArgumentList $TaskSequence.TaskSequence -ErrorAction Stop
                $TaskSequenceXML = [xml]$TaskSequenceResult.ReturnValue
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to convert sequence for Task Sequence Package '$($TaskSequencePackage.Name)' to XML Document" ; break
            }

            # Convert deserialized sequence to a XML Document
            try {
                Write-Verbose -Message "Attempting to save '$($XMLFileName)' to '$($Script:Path)"
                $TaskSequenceXML.Save((Join-Path -Path $Script:Path -ChildPath $XMLFileName -ErrorAction Stop))
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to save XML Document to: '$($Script:Path)" ; break
            }
        }
    }

    # Set ProgressCount for ShowProgress
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }

    switch ($PSCmdlet.ParameterSetName) {
        "SingleInstance" {
            # Get specific SMS_TaskSequencePackage WMI object determined by PackageID
            try {
                Write-Verbose -Message "Querying the SMS Provider for Task Sequence Package with PackageID of '$($PackageID)'"
                $TaskSequencePackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -Filter "PackageID like '$($PackageID)'" -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message $_.Exception.Message ; break
            }

            # Export Task Sequence to a XML file
            if ($TaskSequencePackage -ne $null) {
                $TaskSequencePackage.Get()
                Export-TaskSequence -TaskSequencePackage $TaskSequencePackage
            }
            else {
                Write-Warning -Message "Query for Task Sequence Package with PackageID '$($PackageID)' did not return any objects"
            }
        }
        "AllInstances" {
            # Get all SMS_TaskSequencePackage WMI objects
            try {
                Write-Verbose -Message "Querying the SMS Provider for all Task Sequence Packages"
                $TaskSequencePackages = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_TaskSequencePackage -ComputerName $SiteServer -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message $_.Exception.Message ; break
            }

            # Export Task Sequence to a XML file
            if ($TaskSequencePackages -ne $null) {
                # Determine count of Task Sequence Packages
                $TaskSequencePackagesCount = ($TaskSequencePackages | Measure-Object).Count

                # Process each Task Sequence Package
                foreach ($TaskSequencePackage in $TaskSequencePackages) {
                    # Show progress
                    if ($PSBoundParameters["ShowProgress"]) {
                        $ProgressCount++
                        Write-Progress -Activity "Exporting Task Sequences" -Id 1 -Status "$($ProgressCount) / $($TaskSequencePackagesCount)" -CurrentOperation "Current Task Sequence: $($TaskSequencePackage.Name)" -PercentComplete (($ProgressCount / $TaskSequencePackagesCount) * 100)
                    }

                    # Export current Task Sequence
                    $TaskSequencePackage.Get()
                    Export-TaskSequence -TaskSequencePackage $TaskSequencePackage
                }
            }
            else {
                Write-Warning -Message "Query for all Task Sequence Packages did not return any objects"
            }
        }
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Exporting Task Sequences" -Id 1 -Completed
    }
}