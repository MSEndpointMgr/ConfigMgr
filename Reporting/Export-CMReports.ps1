<#
.SYNOPSIS
    Export all reports in a specific folder on Reporting Service point
.DESCRIPTION
    Use this script to export all the reports available in the specified folder on a Reporting Service point in ConfigMgr 2012
    Method to download the reports are borrow from this blog post:
    http://www.sqlmusings.com/2011/03/28/how-to-download-all-your-ssrs-report-definitions-rdl-files-using-powershell/
.PARAMETER ReportServer
    Site Server where SQL Server Reporting Services are installed
.PARAMETER WebServiceURL
    The SSRS Web Service URL, if other than the default value "ReportServer". Only use this if the URL is not http://<servername>/ReportServer
.PARAMETER SiteCode
    SiteCode of the Reporting Service point
.PARAMETER RootFolderName
    Should only be specified if the default 'ConfigMgr_<sitecode>' folder is not used and a custom folder was created
.PARAMETER FolderName
    If specified, search is restricted to within this folder if it exists
.PARAMETER ExportPath
    Path to where the reports will be exported
.PARAMETER Credential
    PSCredential object created with Get-Credential or specify an username
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    .\Export-CMReports.ps1 -ReportServer CM01 -SiteCode PS1 -FolderName "Custom Reports" -ExportPath "C:\Export"
    Export all the reports in a folder called 'Custom Reports' to 'C:\Export' on a report server called 'CM01'
.EXAMPLE
    .\Export-CMReports.ps1 -ReportServer CM01 -WebServiceURL ReportServer_SCCM -RootFolderName CM_PS1 -FolderName "Custom Reports" -ExportPath "C:\Export"
    Export all the reports in a folder called 'Custom Reports' to 'C:\Export' on a report server called 'CM01', with custom URL http://CM01/ReportServer_SCCM and root folder CM_PS1
.NOTES
    Script name: Export-CMReports.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-11-24
    Updated:     2021-03-02

    Contributors: @merlinfrombelgium

    Version history:
    1.0 - (2014-11-24) Script created
    1.1 - (2021-03-02) Updated script with support for custom Web Service URL
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true,HelpMessage="Site Server where SQL Server Reporting Services are installed")]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1})]
    [string]$ReportServer,
    [parameter(Mandatory=$true,HelpMessage="SiteCode of the Reporting Service point")]
    [string]$SiteCode,
    [parameter(Mandatory=$false,HelpMessage="Should only be specified if the default 'ConfigMgr_<sitecode>' folder is not used and a custom folder was created")]
    [string]$RootFolderName = "ConfigMgr",
    [parameter(Mandatory=$false,HelpMessage="If specified, ReportServer URL is set to http://<servername>/`$ReportsUrl")]
    [string]$WebServiceURL = "ReportServer",
    [parameter(Mandatory=$false,HelpMessage="If specified, search is restricted to within this folder if it exists")]
    [string]$FolderName,
    [parameter(Mandatory=$true,HelpMessage="Path to where the reports will be exported")]
    [string]$ExportPath,
    [Parameter(Mandatory=$false,HelpMessage="PSCredential object created with Get-Credential or specify an username")]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,
    [parameter(Mandatory=$false,HelpMessage="Show a progressbar displaying the current operation")]
    [switch]$ShowProgress
)
Begin {
    # Build the Uri
    $SSRSUri = "http://$($ReportServer)/$($WebServiceURL)/ReportService2010.asmx"
    # Build the default or custom ConfigMgr path for a Reporting Service point
    if ($RootFolderName -like "ConfigMgr") {
        $SSRSRootFolderName = -join ("/","$($RootFolderName)","_",$($SiteCode))
    }
    else {
        $SSRSRootFolderName = -join ("/","$($RootFolderName)")
    }
    # Configure arguments being passed to the New-WebServiceProxy cmdlet by splatting
    $ProxyArgs = [ordered]@{
        "Uri" = $SSRSUri
        "Namespace" = "SSRS.ReportingServices2010"
        "UseDefaultCredential" = $true
    }
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $ProxyArgs.Remove("UseDefaultCredential")
        $ProxyArgs.Add("Credential", $Credential)
    }
    else {
        Write-Verbose -Message "Credentials was not provided, using default"
    }
    # Trim ExportPath
    if ($ExportPath.EndsWith("\")) {
        Write-Verbose -Message "Trimmed export path"
        $ExportPath = $ExportPath.TrimEnd("\")
    }
    # Determine ShowProgress count
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
}
Process {
    try {
        # Set up a WebServiceProxy
        $WebServiceProxy = New-WebServiceProxy @ProxyArgs -ErrorAction Stop
        if ($PSBoundParameters["FolderName"]) {
            Write-Verbose -Message "FolderName parameter was specified, matching results"
            $WebItems = $WebServiceProxy.ListChildren($SSRSRootFolderName, $true) | Select-Object ID, Name, Path, TypeName | Where-Object { $_.Path -match "$($FolderName)" } | Where-Object { $_.TypeName -eq "Report" }
        }
        else {
            Write-Verbose -Message "Gathering objects from Report Server"
            $WebItems = $WebServiceProxy.ListChildren($SSRSRootFolderName, $true) | Select-Object ID, Name, Path, TypeName | Where-Object { $_.TypeName -eq "Report" }
        }
        $WebItemsCount = ($WebItems | Measure-Object).Count
        # For each report
        foreach ($Item in $WebItems) {
            # Get Report name
            $SubPath = (Split-Path -Path $Item.Path).TrimStart("\")
            $ReportName = Split-Path -Path $Item.Path -Leaf
            $File = New-Object -TypeName System.Xml.XmlDocument
            # Show progress
            if ($PSBoundParameters["ShowProgress"]) {
                $ProgressCount++
                Write-Progress -Activity "Exporting Reports" -Id 1 -Status "$($ProgressCount) / $($WebItemsCount)" -CurrentOperation "$($ReportName)" -PercentComplete (($ProgressCount / $WebItemsCount) * 100)
            }
            # Create an empty byte array
            [byte[]]$ReportDefinition = $null
            # Get the definition and store it as a byte array
            $ReportDefinition = $WebServiceProxy.GetItemDefinition($Item.Path)
            [System.IO.MemoryStream]$MemoryStream = New-Object -TypeName System.IO.MemoryStream(@(,$ReportDefinition))
            $File.Load($MemoryStream)
            # Build the report file name and path
            $ReportFileName = -join ($ExportPath,"\",$SubPath,"\",$ReportName,".rdl")
            # Create additional directories under the export path
            if (-not(Test-Path -Path (-join ($ExportPath,"\",$SubPath)))) {
                New-Item -Path (-join ($ExportPath,"\",$SubPath)) -ItemType Directory -Force -Verbose:$false | Out-Null
            }
            # Save the report
            if ($PSCmdlet.ShouldProcess("Report: $($ReportName)","Save")) {
                if (-not(Test-Path -Path $ReportFileName -PathType Leaf)) {
                    $File.Save($ReportFileName)
                }
                else {
                    Write-Warning -Message "Existing file found with name '$($ReportName).rdl', skipping download"
                }
            }
        }
    }
    catch [Exception] {
        Throw $_.Exception.Message
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Exporting Reports" -Completed -ErrorAction SilentlyContinue
    }
}