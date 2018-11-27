<#  
.SYNOPSIS  
    This function can be run against a server to set the 'Max MIF Size' registry value.
.DESCRIPTION
    This function can be run against a server to set the 'Max MIF Size' registry value.
.PARAMETER ComputerName
    The NetBIOS name of the computer to run the script against.
.PARAMETER Size
    Integer value of the maximum size for MIF size that the system will handle. Specified in hex, e.g. 3200000 = 50MB.
.NOTES  
    Name: Set-MaxMIFSize
    Author: Nickolaj Andersen
    DateCreated: 2014-01-07
        
.LINK  
    http://www.scconfigmgr.com
.EXAMPLE  
Set-CMMaxMIFSize -ComputerName 'SRV001' -Size 3200000

Description
-----------
This command will set the 'Max MIF Size' DWORD value in 'HKLM\SOFTWARE\Microsoft\SMS\Components\SMS_INVENTORY_DATA_LOADER'.
        
#>
[CmdletBinding()]
param(
[ValidateScript({Test-Connection -ComputerName $_ -Count 1})]
[ValidateNotNull()]
[parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)]
$ComputerName,
[ValidateNotNull()]
[parameter(Mandatory=$true)]
[int]$Size
)
Process {
    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param(
            $Size,
            $ComputerName
            )
            $Key = "SOFTWARE\Microsoft\SMS\Components\SMS_INVENTORY_DATA_LOADER"
            $BaseKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $ComputerName)
            $SubKey = $BaseKey.OpenSubkey($Key,$true)
            $SubKey.SetValue('Max MIF Size',$Size,[Microsoft.Win32.RegistryValueKind]::DWORD)
        } -ArgumentList ($Size,$ComputerName)
    }
    catch {
        Write-Output $_.Exception.Message
    }
}