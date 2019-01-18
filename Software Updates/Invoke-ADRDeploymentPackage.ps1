<#
.SYNOPSIS

This script is for using when you have set the 'No deployment package' setting in ConfigMgr ADRS - and cannot uncheck the box in

.EXAMPLE

    .\invoke-ADRDeploymentPackage.ps1 -SiteCode PR1 -ADRName "Example"  -Verbose -PackageID "PR10000D"

.NOTES
    FileName:    invoke-ADRDeploymentPackageFix.ps1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2019-01-18
    Updated:     2019-01-18

    Version history:
    1.0.0 - (2019-01-18) Script created
#>
[cmdletBinding()]
param(
    [Parameter(Mandatory = $True,HelpMessage = "Enter the Site Code for your SCCM Server")]
    [string]$SiteCode,
    [Parameter(Mandatory = $True,HelpMessage = "Enter the name of the ADR")]
    [string]$ADRName,
    [Parameter(Mandatory = $False,HelpMessage = "Enter the package ID you would like to set it to.")]
    [string]$PackageID
    )
Begin {}
Process{
try{
$SiteCode = "PR1"
$ADRName = "Example"
[wmi]$ADR = (Get-WmiObject -Class SMS_AutoDeployment -Namespace "root/sms/site_$($SiteCode)" | Where-Object -FilterScript {$_.Name -eq $ADRName}).__Path
Write-Verbose -Message "Got the ADR $($ADR.Name)"
#GEt the ADR WMIObject that represents the automatic deployment rule
[XML]$ContentXML = $ADR.ContentTemplate
Write-Verbose -Message "Converted the template to XML"
#Convert the content stored in the WMI object into the XML it should be treated as
$CreateContent = $MissingElement = $ContentXML.CreateElement("PackageID")
Write-Verbose -Message "Created the element for PackageID"
$AppendStep = $ContentXML.ContentActionXML.AppendChild($MissingElement)
Write-Verbose -Message "Appended the child"
#Add the missing PackageID element back to the content XML
#Create the missing PackageID element
if($PackageID){
$ContentXML.ContentActionXML.PackageID = $PackageID
Write-Verbose -Message "Succesfully added the packageID to the attribute"
}
#The above step is optional - if you don't use a package ID it will default to forcing you to simply select one of the three radio buttons.
$SwapStep = $Adr.ContentTemplate = $ContentXML.ContentActionXML.OuterXml
Write-Verbose -Message "Now adding the content XML back to the original ADR XMl"
#Swap the contenttemplate stored in the ADR with the XML that has been updated.
$ADR.Put() | Out-Null
Write-Verbose -Message "Completed putting the management object back"
#Put the WMI object you've been editing back.
}
catch{ 
    Write-Error $_.Exception.Message
}
}