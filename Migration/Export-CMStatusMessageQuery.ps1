<#
.SYNOPSIS
    Export a single or all custom Status Message Queries to a XML file
.DESCRIPTION
    Export a single or all custom Status Message Queries to a XML file. This file can later be used to import the Status Message Queries again.
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER Name
    Name of a Status Message Query
.PARAMETER Path
    Specify a valid path to where the XML file containing the Status Message Queries will be stored
.PARAMETER Recurse
    Export all custom Status Message Queries
.PARAMETER Force
    Will overwrite any existing XML files specified in the Path parameter
.EXAMPLE
    .\Export-CMStatusMessageQuery.ps1 -SiteServer CM01 -Name "OSD - Windows 8.1 Enterprise 64-bit" -Path "C:\Export\SMQuery.xml" -Force
    Export a Status Message Query called 'OSD - Windows 8.1 Enterprise 64-bit' to 'C:\Export\SMQuery.xml' and overwrite if file already exists, on a Primary Site server called 'CM01':

    .\Export-CMStatusMessageQuery.ps1 -SiteServer CM01 -Recurse -Path "C:\Export\SMQuery.xml" -Force
    Export all custom Status Message Queries to 'C:\Export\SMQuery.xml' and overwrite if file already exists, on a Primary Site server called 'CM01':
.NOTES
    Script name: Export-CMStatusMessageQuery.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-12-30
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, ParameterSetName="Multiple", HelpMessage="Site server where the SMS Provider is installed")]
    [parameter(ParameterSetName="Single")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,
    [parameter(Mandatory=$false, ParameterSetName="Single", HelpMessage="Name of a Status Message Query")]
    [ValidateNotNullOrEmpty()]
    [string]$Name,
    [parameter(Mandatory=$true, ParameterSetName="Multiple", HelpMessage="Specify a valid path to where the XML file containing the Status Message Queries will be stored")]
    [parameter(ParameterSetName="Single")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+\\\w+")]
    [ValidateScript({
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            Throw "$(Split-Path -Path $_ -Leaf) contains invalid characters"
        }
        else {
            if ([System.IO.Path]::GetExtension((Split-Path -Path $_ -Leaf)) -like ".xml") {
                return $true
            }
            else {
                Throw "$(Split-Path -Path $_ -Leaf) contains unsupported file extension. Supported extensions are '.xml'"
            }
        }
    })]
    [string]$Path,
    [parameter(Mandatory=$false, ParameterSetName="Multiple", HelpMessage="Export all custom Status Message Queries")]
    [switch]$Recurse,
    [parameter(Mandatory=$false, ParameterSetName="Multiple", HelpMessage="Will overwrite any existing XML files specified in the Path parameter")]
    [parameter(ParameterSetName="Single")]
    [switch]$Force
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
    catch [Exception] {
        Throw "Unable to determine SiteCode"
    }
    # See if XML file exists
    if ([System.IO.File]::Exists($Path)) {
        if (-not($PSBoundParameters["Force"])) {
            Throw "Error creating '$($Path)', file already exists"
        }
    }
}
Process {
    # Construct XML document
    $XMLData = New-Object -TypeName System.Xml.XmlDocument
    $XMLRoot = $XMLData.CreateElement("ConfigurationManager")
    $XMLData.AppendChild($XMLRoot) | Out-Null
    $XMLRoot.SetAttribute("Description", "Export of Status Message Queries")
    # Get custom Status Message Queries
    try {
        if ($PSBoundParameters["Recurse"]) {
            Write-Verbose -Message "Query: SELECT * FROM SMS_Query WHERE (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
            $StatusMessageQueries = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Query -ComputerName $SiteServer -Filter "(QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')" -ErrorAction Stop
            $WmiFilter = "(QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
        }
        elseif ($PSBoundParameters["Name"]) {
            if (($Name.StartsWith("*")) -and ($Name.EndsWith("*"))) {
                Write-Verbose -Message "Query: SELECT * FROM SMS_Query WHERE (Name like '%$($Name.Replace('*',''))%') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
                $WmiFilter = "(Name like '%$($Name)%') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
            }
            elseif ($Name.StartsWith("*")) {
                Write-Verbose -Message "Query: SELECT * FROM SMS_Query WHERE (Name like '%$($Name.Replace('*',''))') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
                $WmiFilter = "(Name like '%$($Name)') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
            }
            elseif ($Name.EndsWith("*")) {
                Write-Verbose -Message "Query: SELECT * FROM SMS_Query WHERE (Name like '$($Name.Replace('*',''))%') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
                $WmiFilter = "(Name like '$($Name)%') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
            }
            else {
                Write-Verbose -Message "Query: SELECT * FROM SMS_Query WHERE (Name like '$($Name)') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
                $WmiFilter = "(Name like '$($Name)') AND (QueryID not like 'SMS%') AND (TargetClassName like 'SMS_StatusMessage')"
            }
            if ($Name -match "\*") {
                $Name = $Name.Replace("*","")
                $WmiFilter = $WmiFilter.Replace("*","")
            }
        }
        $StatusMessageQueries = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Query -ComputerName $SiteServer -Filter $WmiFilter -ErrorAction Stop
        $QueryResultCount = ($StatusMessageQueries | Measure-Object).Count
        if ($QueryResultCount -gt 1) {
            Write-Verbose -Message "Query returned $($QueryResultCount) results"
        }
        else {
            Write-Verbose -Message "Query returned $($QueryResultCount) result"
        }
        if ($StatusMessageQueries -ne $null) {
            foreach ($StatusMessageQuery in $StatusMessageQueries) {
                $XMLQuery = $XMLData.CreateElement("Query")
                $XMLData.ConfigurationManager.AppendChild($XMLQuery) | Out-Null
                $XMLQueryName = $XMLData.CreateElement("Name")
                $XMLQueryName.InnerText = ($StatusMessageQuery | Select-Object -ExpandProperty Name)
                $XMLQueryExpression = $XMLData.CreateElement("Expression")
                $XMLQueryExpression.InnerText = ($StatusMessageQuery | Select-Object -ExpandProperty Expression)
                $XMLQueryLimitToCollectionID = $XMLData.CreateElement("LimitToCollectionID")
                $XMLQueryLimitToCollectionID.InnerText = ($StatusMessageQuery | Select-Object -ExpandProperty LimitToCollectionID)
                $XMLQueryTargetClassName = $XMLData.CreateElement("TargetClassName")
                $XMLQueryTargetClassName.InnerText = ($StatusMessageQuery | Select-Object -ExpandProperty TargetClassName)
                $XMLQuery.AppendChild($XMLQueryName) | Out-Null
                $XMLQuery.AppendChild($XMLQueryExpression) | Out-Null
                $XMLQuery.AppendChild($XMLQueryLimitToCollectionID) | Out-Null
                $XMLQuery.AppendChild($XMLQueryTargetClassName) | Out-Null
                Write-Verbose -Message "Exported '$($XMLQueryName.InnerText)' to '$($Path)'"
            }
        }
        else {
            Write-Verbose -Message "Query did not return any objects"
        }
    }
    catch [Exception] {
        Throw $_.Exception.Message
    }
}
End {
    # Save XML data to file specified in $Path parameter
    $XMLData.Save($Path) | Out-Null
}