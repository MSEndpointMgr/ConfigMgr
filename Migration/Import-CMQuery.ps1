<#
.SYNOPSIS
    Import a set of exported custom Queries to ConfigMgr 2012
.DESCRIPTION
    When you've exported a set of custom Queries with Export-CMQuery, you can use this script import them back into ConfigMgr 2012
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER Path
    Specify a valid path to where the XML file containing the exported Queries is located
.EXAMPLE
    .\Export-CMQuery.ps1 -SiteServer CM01 -Path "C:\Export\Query.xml" -Verbose
    Import all Queries from the file 'C:\Export\Query.xml' on a Primary Site server called 'CM01':
.NOTES
    Script name: Import-CMQuery.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-05-17
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,
    [parameter(Mandatory=$true, HelpMessage="Specify a valid path to where the XML file containing the Queries will be stored")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Throw "$(Split-Path -Path $_ -Leaf) contains invalid characters"
        }
        else {
            # Check if file extension is XML
            if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".xml") {
                # Check if the whole path exists
                if (Test-Path -Path $_ -PathType Leaf) {
                        return $true
                }
                else {
                    Throw "Unable to locate part of or the whole specified path, specify a valid path to an exported XML file"
                }
            }
            else {
                Throw "$(Split-Path -Path $_ -Leaf) contains an unsupported file extension. Supported extension is '.xml'"
            }
        }
    })]
    [string]$Path
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Debug "SiteCode: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }
}
Process {
    # Get XML file and construct XML document
    [xml]$XMLData = Get-Content -Path $Path
    # Get all custom Queries
    try {
        if ($XMLData.ConfigurationManager.Description -like "Export of Queries") {
            Write-Verbose -Message "Successfully validated XML document"
        }
        else {
            Write-Warning -Message "Invalid XML document loaded" ; break
        }
        foreach ($Query in ($XMLData.ConfigurationManager.Query)) {
            $NewInstance = ([WmiClass]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_Query").CreateInstance()
            $NewInstance.Name = $Query.Name
            $NewInstance.Expression = $Query.Expression
            $NewInstance.TargetClassName = $Query.TargetClassName
            $NewInstance.Put() | Out-Null
            Write-Verbose -Message "Imported query '$($Query.Name)' successfully"
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message ; break
    }
}