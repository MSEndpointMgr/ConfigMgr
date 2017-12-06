<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.145
	 Created on:   	12/4/2017 9:02 PM
	 Created by:   	Zeng Yinghua
	 Organization: 	
	 Filename:     	Set-CMApplicationIcon.ps1
	===========================================================================
	.DESCRIPTION
		This funtion can set icon for applications
    - 
History:

- 2017 Dec.04, Created script by Zeng Yinghua

Example:
1.	Resize application icon size with 110 x 110 pixel
	.\Set-CMApplicationIcon.ps1 -SiteServer "Your Site Server" -SiteCode "Your Site Code" -ApplicationName "7-zip"
	
2.	Resize application icon with specified size between 16 to 512 pixel
	.\Set-CMApplicationIcon.ps1 -SiteServer "Your Site Server" -SiteCode "Your Site Code" -ApplicationName "7-zip" -IconSize 400

3.	Resize application icon with 110 x 110 pixel, and export the resized icon file to a specified folder
	.\Set-CMApplicationIcon.ps1 -SiteServer "Your Site Server" -SiteCode "Your Site Code" -ApplicationName "7-zip" -IconFolder "D:\Icons"

4.	Set a new icon file for application with 110 x 110 pixel
	This will resize the new image size as 110 x 110 pixel, then set it as icon.
	.\Set-CMApplicationIcon.ps1 -SiteServer "Your Site Server" -SiteCode "Your Site Code" -ApplicationName "7-zip" -IconFileName "D:\Icons\SCConfigMgr2.bmp"
	
5.	Set a new icon file for application with specified size
	This will resize the new image size as you specified, then set it as icon
	.\Set-CMApplicationIcon.ps1 -SiteServer "Your Site Server" -SiteCode "Your Site Code" -ApplicationName "7-zip" -IconSize 400 -IconFileName "D:\Icons\SCConfigMgr2.bmp"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
	#Site Server
	[parameter(Mandatory = $true, HelpMessage = "Specify Site Server Name")]
	[ValidateNotNullOrEmpty()]
	[string]$SiteServer,
	#Site Code

	[parameter(Mandatory = $true, HelpMessage = "Specify SiteCode")]
	[ValidateNotNullOrEmpty()]
	[string]$SiteCode,
	#Site Code

	[parameter(Mandatory = $true, HelpMessage = "Specify ApplicationName")]
	[ValidateNotNullOrEmpty()]
	[string]$ApplicationName,
	#Icon size

	[parameter(Mandatory = $false, ValueFromPipeline = $true, HelpMessage = "Specify Icon Size, recommanded 108")]
	[ValidateRange(16, 512)]
	[int]$IconSize = 110,
	#Icon folder

	[parameter(Mandatory = $false, ValueFromPipeline = $true, HelpMessage = "Specify Icon folder name")]
	[ValidateScript({
			if (-Not ($_ | Test-Path))
			{
				throw "File or folder does not exist"
			}
			if ($_ | Test-Path -PathType Leaf)
			{
				throw "The Path argument must be a folder. File paths are not allowed."
			}
			return $true
		})]
	[System.IO.FileInfo]$IconFolder = $Env:temp,
	[parameter(Mandatory = $false, ValueFromPipeline = $true, HelpMessage = "Specify Icon file name")]
	[ValidateScript({
			if (-Not ($_ | Test-Path))
			{
				throw "File or folder does not exist"
			}
			if (-Not ($_ | Test-Path -PathType Leaf))
			{
				throw "The Path argument must be a file. Folder paths are not allowed."
			}
			return $true
		})]
	[System.IO.FileInfo]$IconFileName
)


$CurrentLocation = (Get-Location).Path
#Import ConfigMgr module, you need to have Admin Console installed
Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" -Verbose:$false

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" -Verbose:$false

#Correct Icon folder name
$IconFolder = Join-Path (Split-Path $IconFolder -Parent)  (Split-Path $IconFolder -Leaf)
write-host "Icon folder is $IconFolder"

#Query Application information
$Query = "LocalizedDisplayName='$ApplicationName' and IsExpired='False' and IsLatest='True'"
$application = Get-WmiObject -ComputerName $SiteServer -Class SMS_Application -Namespace root/sms/site_$sitecode -Filter $Query

if ($application)
{
	#Get Application dirty information, so that we can use SDMPackageXML
	$Application.Get()
	
	#Application Display Name
	$DisplayName = $Application.LocalizedDisplayName
	Write-Host "Found Application $DisplayName" -ForegroundColor Green
	
	#Deserialize SDMPackageXML
	$ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($Application.SDMPackageXML, $true)
	
	if ($IconFileName -eq $null)
	{
		#Get original icon information from Application
		$SDMPackageXML = $Application.SDMPackageXML
		$lines = [Regex]::Split($SDMPackageXML, "<Data>")
		$iconxml = [Regex]::Split($lines[1], "</Data></Icon>")
		$iconbase64 = $iconxml[0]
		$iconStream = [System.IO.MemoryStream][System.Convert]::FromBase64String($iconbase64)
		$iconBmp = [System.Drawing.Bitmap][System.Drawing.Image]::FromStream($iconStream)
		Write-Host "Icon original size is $($iconBmp.Size)" -ForegroundColor Yellow
	}
	else
	{
		Write-Host "Getting $IconFileName information"
		$iconBmp = [System.Drawing.Bitmap]::FromFile($IconFileName)
		Write-Host "Icon original size is $($iconBmp.size)"
	}
	
	try
	{
		#Resize Icon.
		$newbmp = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $iconBmp, $IconSize, $IconSize
		write-host "Resizing icon file as $($IconSize) x $($IconSize) pixel"
		#Save it as png format in a folder
		$NewIconPath = "$IconFolder\$($DisplayName)_$($IconSize).png"
		$newbmp.Save($NewIconPath, "png")
		$newbmp.Dispose()
		if (Test-Path $NewIconPath)
		{
			Write-Host "New icon file $NewIconPath created" -ForegroundColor Green
		}
		else
		{
			Write-Host "Cannot find new icon file." -ForegroundColor Green; exit 1
			
		}
	}
	catch
	{
		Write-Host "An error occured while saving new icon file. Error message: $($_.Exception.Message)"; exit 1
	}
	
	#If Icon size is not bigger than 250, variable of "$NewResolution"
	#In ConfigMgr CB 1710, it supports use 512 x 512 pixel icon files, how ever Set-CMApplication CmdLet supports maximum size of an icon is 250x250 pixel. As I tested, use Set-CMApplication set icon is quite slow.
	try
	{
		
		$ConfigMgrIcon = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.Icon
		$ConfigMgrIcon.data = [System.IO.File]::ReadAllBytes($NewIconPath)
		
		$ApplicationXML.DisplayInfo.Icon.Data = $ConfigMgrIcon.Data
		$ApplicationXML.DisplayInfo.Icon.Id = $ConfigMgrIcon.Id
		
		
		#Update SDMPackageXML
		$UpdatedXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($ApplicationXML, $true)
		$Application.SDMPackageXML = $UpdatedXML
		$Application.Put()
		Write-Host "Set new icon for application $DisplayName succeeded" -ForegroundColor Green
		Set-Location $CurrentLocation -ErrorAction SilentlyContinue
	}
	catch
	{
		Write-Host "An error occured while setting icon. Error message: $($_.Exception.Message)"
		Set-Location $CurrentLocation -ErrorAction SilentlyContinue
		exit 1
	}
	
}
else
{
	write-host "Cannot find any match application" -ForegroundColor Red
	Set-Location $CurrentLocation -ErrorAction SilentlyContinue
	exit 1
}
