<#
.SYNOPSIS
    Import all reports (.rdl files) in a specific folder to a Reporting Service point
.DESCRIPTION
    Use this script to import all the reports (.rdl files) in the specified source path folder to a Reporting Service point in ConfigMgr 2012
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
.PARAMETER SourcePath
    Path to where .rdl files eligible for import are located
.PARAMETER Credential
    PSCredential object created with Get-Credential or specify an username
.PARAMETER Force
    Will create a folder named what's specified in the FolderName parameter if an existing folder is not present. Will be created in the ConfigMgr_<sitecode> root, unless RootFolderName overrides the default.
.PARAMETER ShowProgress
    Show a progressbar displaying the current operation
.EXAMPLE
    .\Import-CMReports.ps1 -ReportServer CM01 -SiteCode PS1 -FolderName "Custom Reports" -SourcePath "C:\Import\RDL" -Force
    Import all the reports in 'C:\Import\RDL' to a folder called 'Custom Reports' on a report server called 'CM01'. 
    If the folder doesn't exist, it will be created in the root path:
.EXAMPLE
    .\Import-CMReports.ps1 -ReportServer CM01 -WebServiceURL ReportServer_SCCM -RootFolderName CM_PS1 -FolderName "Custom Reports" -SourcePath "C:\Import\RDL"
    Import all the reports from 'C:\Import\RDL' to a folder called 'Custom Reports' on a report server called 'CM01', with custom URL http://CM01/ReportServer_SCCM and root folder CM_PS1
.NOTES
    Script name: Import-CMReports.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2014-11-26
    Updated:     2021-03-03

    Contributors: @merlinfrombelgium

    Version history:
    1.0 - (2014-11-24) Script created
    1.1 - (2021-03-03) Updated script with support for custom Web Service URL
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
    [parameter(Mandatory=$true,HelpMessage="Path to where .rdl files eligible for import are located")]
    [ValidateScript({Test-Path -Path $_ -PathType Container})]
    [string]$SourcePath,
    [Parameter(Mandatory=$false,HelpMessage="PSCredential object created with Get-Credential or specify an username")]
    [ValidateNotNull()]
    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty,
    [parameter(Mandatory=$false,HelpMessage="Will create a folder named what's specified in the FolderName parameter if an existing folder is not present. Will be created in the ConfigMgr_<sitecode> root, unless RootFolderName overrides the default")]
    [switch]$Force,
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
    # Build Server path
    if ($PSBoundParameters["FolderName"]) {
        $SSRSRootPath = -join ($SSRSRootFolderName,"/",$FolderName)
    }
    else {
        $SSRSRootPath = $SSRSRootFolderName
    }
    # Configure arguments being passed to the New-WebServiceProxy cmdlet by splatting
    $ProxyArgs = [ordered]@{
        "Uri" = $SSRSUri
        "UseDefaultCredential" = $true
    }
    if ($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
        $ProxyArgs.Remove("UseDefaultCredential")
        $ProxyArgs.Add("Credential", $Credential)
    }
    else {
        Write-Verbose -Message "Credentials was not provided, using default"
    }
    # Determine ShowProgress count
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }
}
Process {
    try {
        # Functions
        function Create-Report {
            param(
            [parameter(Mandatory=$true)]
            [string]$FilePath,
            [parameter(Mandatory=$true)]
            [string]$ServerPath,
            [parameter(Mandatory=$true)]
            [bool]$ShowProgress
            )
            $RDLFiles = Get-ChildItem -Path $FilePath -Filter "*.rdl"
            $RDLFilesCount = ($RDLFiles | Measure-Object).Count
            if (($RDLFiles | Measure-Object).Count -ge 1) {
                foreach ($RDLFile in $RDLFiles) {
                    # Show progress
                    if ($PSBoundParameters["ShowProgress"]) {
                        $ProgressCount++
                        Write-Progress -Activity "Importing Reports" -Id 1 -Status "$($ProgressCount) / $($RDLFilesCount)" -CurrentOperation "$($RDLFile.Name)" -PercentComplete (($ProgressCount / $RDLFilesCount) * 100)
                    }
                    if ($PSCmdlet.ShouldProcess("Report: $($RDLFile.BaseName)","Validate")) {
                        $ValidateReportName = $WebServiceProxy.ListChildren($SSRSRootPath, $true) | Where-Object { ($_.TypeName -like "Report") -and ($_.Name -like "$($RDLFile.BaseName)") }
                    }
                    if ($ValidateReportName -eq $null) {
                        if ($PSCmdlet.ShouldProcess("Report: $($RDLFile.BaseName)","Create")) {
                            # Get the file name without the extension
                            $RDLFileName = [System.IO.Path]::GetFileNameWithoutExtension($RDLFile.Name)
                            # Read the content of the file as a byte stream
                            $ByteStream = Get-Content -Path $RDLFile.FullName -Encoding Byte
                            # Create an array that will contain any warning returned by the webservice
                            $Warnings = @()
                            # Create the Report
                            Write-Verbose -Message "Importing report '$($RDLFileName)'"
                            $WebServiceProxy.CreateCatalogItem("Report",$RDLFileName,$SSRSRootPath,$true,$ByteStream,$null,[ref]$Warnings) | Out-Null
                        }
                        # Get name of default ConfigMgr data source
                        $DefaultCMDataSource = $WebServiceProxy.ListChildren($SSRSRootFolderName, $true) | Where-Object { $_.TypeName -like "DataSource" } | Select-Object -First 1
                        if ($DefaultCMDataSource -ne $null) {
                            if ($PSCmdlet.ShouldProcess("DataSource: $($DefaultCMDataSource.Name)","Set")) {
                                # Get current Report that we recently created
                                $CurrentReport = $WebServiceProxy.ListChildren($SSRSRootFolderName, $true) | Where-Object { ($_.TypeName -like "Report") -and ($_.Name -like "$($RDLFileName)") -and ($_.CreationDate -ge (Get-Date).AddMinutes(-5)) }
                                # Get DataSource items
                                $CurrentReportDataSource = $WebServiceProxy.GetItemDataSources($CurrentReport.Path)
                                # Determine namespace
                                $DataSourceType = $WebServiceProxy.GetType().Namespace
                                # Create a new DataSource object
                                $ArrayItems = 1 # Means how many objects should be in the array
                                $DataSourceArray = New-Object -TypeName (-join ($DataSourceType,".DataSource","[]")) $ArrayItems
                                $DataSourceArray[0] = New-Object -TypeName (-join ($DataSourceType,".DataSource"))
                                $DataSourceArray[0].Name = $CurrentReportDataSource.Name
                                $DataSourceArray[0].Item = New-Object -TypeName (-join ($DataSourceType,".DataSourceReference"))
                                $DataSourceArray[0].Item.Reference = $DefaultCMDataSource.Path
                                # Set new data source for current report
                                Write-Verbose -Message "Changing data source for report '$($RDLFileName)'"
                                $WebServiceProxy.SetItemDataSources($CurrentReport.Path, $DataSourceArray)
                            }
                        }
                        else {
                            Write-Warning -Message "Unable to determine default ConfigMgr data source, will not edit data source for report '$($RDLFileName)'"
                        }
                    }
                    else {
                        Write-Warning -Message "A report with the name '$($RDLFile.BaseName)' already exists, skipping import"
                    }
                }
            }
            else {
                Write-Warning -Message "No .rdl files was found in the specified path"
            }
        }
        # Set up a WebServiceProxy
        $WebServiceProxy = New-WebServiceProxy @ProxyArgs -ErrorAction Stop
        if ($PSBoundParameters["FolderName"]) {
            Write-Verbose -Message "FolderName was specified"
            if ($WebServiceProxy.ListChildren($SSRSRootFolderName, $true) | Select-Object ID, Name, Path, TypeName | Where-Object { ($_.TypeName -eq "Folder") -and ($_.Name -like "$($FolderName)") }) {
                Create-Report -FilePath $SourcePath -ServerPath $SSRSRootPath -ShowProgress $ShowProgress
            }
            else {
                if ($PSBoundParameters["Force"]) {
                    if ($PSCmdlet.ShouldProcess("Folder: $($FolderName)","Create")) {
                        Write-Verbose -Message "Creating folder '$($FolderName)'"
                        # Get the namespace of the webservice
                        $TypeName = $WebServiceProxy.GetType().Namespace
                        # Create a property object and add some properties
                        $Property = New-Object -TypeName (-join ($TypeName,".Property"))
                        $Property.Name = "$($FolderName)"
                        $Property.Value = "$($FolderName)"
                        # We also need a Property array object defining the property object created earlier
                        $Properties = New-Object -TypeName (-join ($TypeName,".Property","[]")) 1
                        $Properties[0] = $Property
                        # Create the folder in SSRS
                        $WebServiceProxy.CreateFolder($FolderName,"$($SSRSRootFolderName)",$Properties) | Out-Null
                    }
                    Create-Report -FilePath $SourcePath -ServerPath $SSRSRootPath -ShowProgress $ShowProgress
                }
                else {
                    Write-Warning -Message "Unable to find a folder matching '$($FolderName)'"
                }
            }
        }
        else {
            Create-Report -FilePath $SourcePath -ServerPath $SSRSRootPath -ShowProgress $ShowProgress
        }
    }
    catch [Exception] {
        Throw $_.Exception.Message
    }
}
End {
    if ($PSBoundParameters["ShowProgress"]) {
        Write-Progress -Activity "Importing Reports" -Completed -ErrorAction SilentlyContinue
    }
}