<#
.SYNOPSIS
    This Script is used to build a WiFi XML Template for WPAPSK

.DESCRIPTION
    This is set up using basic connection rules for WPA-PSK and accepts parameters. The idea of this is to allow you to quickly
    deploy wireless profiles to machines using the run-scripts module in ConfigMgr. Please note that doing this WILL cause a network password to 
    temporarily be stored in PLAIN TEXT. 

.PARAMETER ProfileName
    This parameter is used to submit the SSID of the network you will be connecting too. This parameter is CASE SENSITIVE. This is because the content
    is converted into a hex string value. Currently this is only for SSID's that ARE being broadcasted. 
    

.PARAMETER Key
   This paramter is used to submit the passsword for the SSID network. This password is stored temporarily in plain text on the machine when the VM is generated.
   The password is NOT stored in the script repository for the client. 

.NOTES
    FileName:    Set-WiFiProfile.ps1
    Author:      Jordan Benzing
    Contact:     @JordanTheItGuy
    Created:     2018-09-10
    Updated:     2018-09-10

    Version history:
	1.0.8 - (2018-09-10) Script created
	
	This is NOT an extremely secure method for creating profiles however if you read the information in my post you'll notice that in reality wireless profiles aren't stored securely on computers anyways.
	

#>

#region ConfigurationBlock
<#
This section is currently commented out if you want to remove the parameterization out comment out the parameter region of the script and uncommnet the configuration region.
Note if you elect to use this code block you will be storing information in plain text within the script and will also likely want to un-comment the scheduledtask region to clean the scripts store.
$ProfileName = YourSSIDHere
$Key= YourWirelessKeyHere
#>
#endregion ConfigurationBlock

#region ParameterBlock
#If you elect to hardcode the profiles comment this section of code out and use the configuration block region instead.
[CmdletBinding(SupportsShouldProcess=$true)]
param
(
    [parameter(Mandatory = $true)]
    [string]$ProfileName,
    [parameter(Mandatory = $true)]
    [String]$Key
)
#endregion ParameterBlock

Begin {}
Process {
$conversionValue = $ProfileName.ToCharArray()
#Converts the Provided profile to a char array that is then used to convert to Hex.
foreach($letter in $conversionValue){$HexKey = $HexKey + " " + [System.String]::Format("{0:X}", [System.Convert]::ToUInt32($letter))}
#Converts the string into a HEX value
$HexKey = $HexKey.ToSTring()
#Converts the bytecollection object to a String
$HexKey = $HexKey.replace(' ','')
#removes spaces from the string.
$data = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
	<name>$ProfileName</name>
	<SSIDConfig>
		<SSID>
			<hex>$HexKey</hex>
			<name>$ProfileName</name>
		</SSID>
	</SSIDConfig>
	<connectionType>ESS</connectionType>
	<connectionMode>auto</connectionMode>
	<MSM>
		<security>
			<authEncryption>
				<authentication>WPA2PSK</authentication>
				<encryption>AES</encryption>
				<useOneX>false</useOneX>
			</authEncryption>
			<sharedKey>
				<keyType>passPhrase</keyType>
				<protected>false</protected>
				<keyMaterial>$Key</keyMaterial>
			</sharedKey>
		</security>
	</MSM>
	<MacRandomization xmlns="http://www.microsoft.com/networking/WLAN/profile/v3">
		<enableRandomization>false</enableRandomization>
		<randomizationSeed>3386856935</randomizationSeed>
	</MacRandomization>
</WLANProfile>
"@
#Generates the Here string for a common wifi profile type.
New-Item C:\Windows\Temp\WLANProfile.xml -ItemType file -Force -Value $data | Out-Null
#Creates the .XML file that will be used to import the profile temporarily.
<#
This block will create a scheduled task that will remove all scripts stored in the script store repostory
This script section is useful if you decided to hardcode the SSID tag and the wifi password parameter

**DEVNOTE** - I may later develop this to parse the 'Scripts' log to find the GUID of the script and then instead only remove the script that ran this
if(Get-ScheduledTask -TaskName 'Clean ScriptStore'){Unregister-ScheduledTask -TaskName 'Clean ScriptStore' -Confirm:$false}	
$Command = "if(test-path -path C:\Windows\ccm\scriptstore){Get-ChildItem -Path C:\Windows\CCM\ScriptStore\ -Filter *.ps1 | ForEach-Object {Remove-Item -Path `$_.FullName -Force}}"
& schtasks /create /ru "System" /sc ONCE /ST (Get-Date).AddMinutes(2).ToString('HH:mm:ss') /tn "Remove Scripts log" /TR "PowerShell.Exe -Command $Command"
#>

#Generates the XML file locally in the TEMP directory this can be changed to use a different location.
netsh wlan add profile filename="C:\Windows\Temp\WLANProfile.xml"
#imports the .XML file from the temp directory to install the WLAN Profile
Remove-Item C:\Windows\Temp\WLANProfile.xml
#Removes the XML file that was created and used from the machine
}
