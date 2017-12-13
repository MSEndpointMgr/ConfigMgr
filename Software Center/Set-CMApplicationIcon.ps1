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
-- Version 2.0 - 2017 Dec.13. Use a dummy icon file if there is no icon assgined earlier for applications, then set the new icon file again.
-- Version.1.0 2017 Dec.04. Created script. by Zeng Yinghua


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
	[parameter(Mandatory = $true, ValueFromPipeline = $true, HelpMessage = "Specify Icon file name")]
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

function Set-CMLocation
{ 
	$global:CurrentLocation = (Get-Location).Path
	#Import ConfigMgr module, you need to have Admin Console installed
	Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" -Verbose:$false
	
	# Set the current location to be the site code.
	Set-Location "$($SiteCode):\" -Verbose:$false
}

function Get-CMApplicationsIconDetails
{
	#Correct Icon folder name
	$IconFolder = Join-Path (Split-Path $IconFolder -Parent)  (Split-Path $IconFolder -Leaf)
	write-host "Icon folder is $IconFolder"
	
	#Query Application information
	$Query = "LocalizedDisplayName='$ApplicationName' and IsExpired='False' and IsLatest='True'"
	$global:application = Get-WmiObject -ComputerName $SiteServer -Class SMS_Application -Namespace root/sms/site_$sitecode -Filter $Query
	
	if ($application)
	{
		#Get Application dirty information, so that we can use SDMPackageXML
		$Application.Get()
		
		#Application Display Name
		$global:DisplayName = $Application.LocalizedDisplayName
		Write-Host "Found Application $DisplayName" -ForegroundColor Green
		
		#Deserialize SDMPackageXML
		$global:ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($Application.SDMPackageXML, $true)
		
		#Get original icon information from Application
		$SDMPackageXML = $Application.SDMPackageXML
		$lines = [Regex]::Split($SDMPackageXML, "<Data>")
		$iconxml = [Regex]::Split($lines[1], "</Data></Icon>")
		if ($iconxml)
		{
			$iconbase64 = $iconxml[0]
			$iconStream = [System.IO.MemoryStream][System.Convert]::FromBase64String($iconbase64)
			$global:iconBmp = [System.Drawing.Bitmap][System.Drawing.Image]::FromStream($iconStream)
			Write-Host "Icon original size is $($iconBmp.Size)" -ForegroundColor Yellow
		}
		else
		{
			Write-Host "There is no custom icon assigned to $DisplayName" -ForegroundColor Red
		}
	}
	else
	{
		write-host "Cannot find any match application" -ForegroundColor Red
	}
}

function Resize-Icon
{
	#If a new Icon file is selected, convert that to bitmap.
	if ($IconFileName)
	{
		$iconBmp = [System.Drawing.Bitmap]::FromFile($IconFileName)
		Write-Host "New Icon file original size is $($iconBmp.size)"
	}
	
	#resize icon
	$newbmp = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $iconBmp, $IconSize, $IconSize
	write-host "Resizing icon file as $($IconSize) x $($IconSize) pixel"
	#Save it as png format in a folder
	$global:NewIconPath = "$IconFolder\$($DisplayName)_$($IconSize).png"
	$newbmp.Save($NewIconPath, "png")
	$newbmp.Dispose()
	try
	{
		Test-Path $NewIconPath
		Write-Host "New icon file $NewIconPath created" -ForegroundColor Green
	}
	catch
	{
		Write-Host "Cannot find new icon file.Error message: $($_.Exception.Message)" -ForegroundColor red
	}
}


#Set CM location
Set-CMLocation

#Get application icon details
Get-CMApplicationsIconDetails

#Set a dummy icon if there is no custom icon assigned earlier
if (!$iconBmp)
{
	#create a dummy icon file
	$dummyiconStream = [System.IO.MemoryStream][System.Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAJTSURBVDhPbVPPS6JRFP3+wMCW7kR02TLcKBESJBEE4kaCohBDso2UgZmYv9FSs8xKK8sKU0NRUVP0DOfG1wwz8+D6fI977j3nfPc
ps9kMjL/X/+641PzpdCpnhT/qgXuj0UAul8Pp6SmOjo4QCASQTqdRrVYxGAx+ctUGwkC9JNDhcODw8BCXl5d4fHyUu4ODA6yvr8Pv96PX6/3LYDKZIJFI4Pj4GE9PT3h5eZH9/v4e5XIZt7e3uLi4wN7eHlwuF2q12o8UKXB9fY2dnR18fHwI8OHhQYLgm5sbFItF5PN5YWW32+HxeNButw
mFMh6P4fP5cHV1JZ3v7u5QqVSkK8GMbDaL19dXKRgKhWCz2ZDJZDAajaD0+33s7+/j7e1NmLALQaVSSc704Pn5WTQzksmk+LG5uYlWqwWl2WwKJepiZyaRBSkz6L6ql/f0ijKsVquwUqjb7XZLIotxMfn8/Fw6q4vMCI7H49jY2IDJZBKM8vn5id3dXXGc1EmLBf5c7ExgJBJBOBzGysoKz
GazeKZ0u104nU6hWygUZFeZcNEDdj47O5M4OTnBwsICVldX8f7+DoUz4PV6pQjdJnUGq5NRLBb76RwMBrG8vAyj0SjGdzqd7zlgssViES9SqZSAotGoAPmfQH4+atfr9VhaWhLJbC4Fvr6+xCRqYwdOG6mq72FrawuLi4vQ6XRiHqUMh8Pfk8hPx3lgVWpjl/n5eczNzUGj0UCr1cJgMGBt
bU0eFn1TcVJAdZ1TWa/XxTQ+IH6d7e1tmRPK4HjzRTL/O2b4BUErcBXsnNaeAAAAAElFTkSuQmCC')
	$dummyiconBmp = [System.Drawing.Bitmap][System.Drawing.Image]::FromStream($dummyiconStream)
	$dummyiconHandle = $dummyiconBmp.GetHicon()
	$dummyappicon = [System.Drawing.Icon]::FromHandle($dummyiconHandle)
	$dummynewIcon = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $dummyappicon, 16, 16
	#Save it as png format in a folder
	$dummyIconPath = "$IconFolder\dummyicon.png"
	$dummynewIcon.Save($dummyIconPath, "png")
	$dummynewIcon.Dispose()
	#
	#Set a dummy icon file to application
	Set-CMApplication -Name $ApplicationName -IconLocationFile $dummyIconPath
	#get application icon details again.
	Get-CMApplicationsIconDetails
}

#In ConfigMgr CB 1710, it supports use 512 x 512 pixel icon files, how ever Set-CMApplication CmdLet supports maximum size of an icon is 250x250 pixel. As I tested, use Set-CMApplication set icon is quite slow.
try
{
	
	$ConfigMgrIcon = New-Object Microsoft.ConfigurationManagement.ApplicationManagement.Icon
	$ConfigMgrIcon.data = [System.IO.File]::ReadAllBytes($NewIconPath)
	
	if ($ApplicationXML.DisplayInfo.Icon.Data)
	{
		$ApplicationXML.DisplayInfo.Icon.Data = $ConfigMgrIcon.Data
		$ApplicationXML.DisplayInfo.Icon.Id = $ConfigMgrIcon.Id
		
		#Update SDMPackageXML
		$UpdatedXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($ApplicationXML, $true)
		$Application.SDMPackageXML = $UpdatedXML
		$Application.Put()
		Write-Host "Set new icon for application $DisplayName succeeded" -ForegroundColor Green
		Set-Location $CurrentLocation -ErrorAction SilentlyContinue
	}
	else
	{
		Set-CMApplication -Name $ApplicationName -IconLocationFile $NewIconPath -Verbose
		Write-Host "Set new icon for application $DisplayName succeeded" -ForegroundColor Green
		Set-Location $CurrentLocation -ErrorAction SilentlyContinue
	}
}
catch
{
	Write-Host "An error occured while setting icon. Error message: $($_.Exception.Message)"
	Set-Location $CurrentLocation -ErrorAction SilentlyContinue
	
}

Set-Location $CurrentLocation -ErrorAction SilentlyContinue
