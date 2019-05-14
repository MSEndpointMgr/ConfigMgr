<#
.SYNOPSIS
	Detect architecture and build version number for operating system upgrade package that's used within the running task sequence.
	
.DESCRIPTION
    Detect architecture and build version number for operating system upgrade package that's used within the running task sequence.
    This script cannot be executed outside of a task sequence. It needs to be running before the Upgrade Operating System step in an In-Place Upgrade task sequence.

.PARAMETER URI
	Set the URI for the ConfigMgr WebService.
	
.PARAMETER SecretKey
	Specify the known secret key for the ConfigMgr WebService.

.EXAMPLE
	# Detect architecture and build version number for operating system upgrade package used executing running task sequence:
	.\Invoke-CMDetectOSUpgradeImageDetails.ps1 -URI "http://CM01.domain.com/ConfigMgrWebService/ConfigMgr.asmx" -SecretKey "12345"

.NOTES
    FileName:    Invoke-CMDetectOSUpgradeImageDetails.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2019-05-09
    Updated:     2019-05-09

    Version history:
	1.0.0 - (2019-05-09) Script created
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $true, HelpMessage = "Set the URI for the ConfigMgr WebService.")]
	[ValidateNotNullOrEmpty()]
	[string]$URI,
	
	[parameter(Mandatory = $true, HelpMessage = "Specify the known secret key for the ConfigMgr WebService.")]
	[ValidateNotNullOrEmpty()]
	[string]$SecretKey
)
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	try {
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"; break
    }
    
    # Set logging path
    $LogsDirectory = $Script:TSEnvironment.Value("_SMSTSLogPath")
}
Process {
    # Functions
    function Write-CMLogEntry {
        param (
            [parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
            [ValidateNotNullOrEmpty()]
            [string]$Value,
    
            [parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
            [string]$Severity,
    
            [parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
            [ValidateNotNullOrEmpty()]
            [string]$FileName = "OSUpgradeImageDetails.log"
        )
        # Determine log file location
        $LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
        
        # Construct time stamp for log entry
        if (-not(Test-Path -Path 'variable:global:TimezoneBias')) {
            [string]$global:TimezoneBias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
            if ($TimezoneBias -match "^-") {
                $TimezoneBias = $TimezoneBias.Replace('-', '+')
            }
            else {
                $TimezoneBias = '-' + $TimezoneBias
            }
        }
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), $TimezoneBias)
        
        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")
        
        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        
        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""OSUpgradeImageDetails"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
        
        # Add value to log file
        try {
            Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to OSUpgradeImageDetails.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
        }
    }
    
    function Get-OSImageData {
        param (
            [parameter(Mandatory = $true, HelpMessage = "Task sequence package ID.")]
            [ValidateNotNullOrEmpty()]
            [string]$TSPackageID
        )    
        try {
            # Determine OS Image information for running task sequence from web service
            Write-CMLogEntry -Value "Attempting to detect OS Image data from task sequence XML data" -Severity 1
            $OSImages = $WebService.GetCMOSImageForTaskSequence($SecretKey, $SMSTSPackageID)
            if ($OSImages -ne $null) {
                if (($OSImages | Measure-Object).Count -ge 2) {
                    # Select the first object returned from web service call
                    Write-CMLogEntry -Value "Multiple OS Image objects detected selecting the first OS Image object from web service call" -Severity 1
                    $OSImage = $OSImages | Sort-Object -Descending | Select-Object -First 1
                    
                    # Create custom object for return value
                    $PSObject = [PSCustomObject]@{
                        OSVersion  = $OSImage.Version
                        OSArchitecture = $OSImage.Architecture
                    }
    
                    # Handle return value
                    return $PSObject
                }
                else {
                    # Create custom object for return value
                    $PSObject = [PSCustomObject]@{
                        OSVersion  = $OSImages.Version
                        OSArchitecture = $OSImages.Architecture
                    }
    
                    # Handle return value
                    return $PSObject
                }
            }
            else {
                Write-CMLogEntry -Value "Call to ConfigMgr WebService returned empty OS Image data. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 4
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "An error occured while calling ConfigMgr WebService to get OS Image data. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 3
        }
    }
    
    function Get-OSArchitecture {
        param (
            [parameter(Mandatory = $true, HelpMessage = "OS architecture data to be translated.")]
            [ValidateNotNullOrEmpty()]
            [string]$InputObject
        )
        switch ($InputObject) {
            "9" {
                $OSImageArchitecture = "x64"
            }
            "0" {
                $OSImageArchitecture = "x86"
            }
            "64-bit" {
                $OSImageArchitecture = "x64"
            }
            "32-bit" {
                $OSImageArchitecture = "x86"
            }
        }
       
        # Handle return value from function
        return $OSImageArchitecture
    }
    
    # Get the SMSTSPackageID value from TS Environment
    try {
        $SMSTSPackageID = $TSEnvironment.Value("_SMSTSPackageID")
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Unable to read _SMSTSPackageID value from TS Environment" -Severity 3; exit 1
    }
    
    # Construct new web service proxy
    try {
        $WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Unable to establish a connection to ConfigMgr WebService. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 1
    }
    
    # Get OS Image data
    $OSImageData = Get-OSImageData -TSPackageID $SMSTSPackageID
    if ($OSImageData -ne $null) {
        # Translate operating system build version from web service response
        $OSImageBuildVersion = [System.Version]::Parse($OSImageData.OSVersion).Build
        Write-CMLogEntry -Value "Operating system build version detected as: $($OSImageBuildVersion)" -Severity 1
        
        # Set TS Environment variable for operating system build version
        $TSEnvironment.Value("OSUpgradeBuildVersion") = $OSImageBuildVersion
        Write-CMLogEntry -Value "Setting TSEnvironment variable 'OSUpgradeBuildVersion' with value: $($OSImageBuildVersion)" -Severity 1
        
        # Translate operating system architecture from web service response
        $OSImageArchitecture = Get-OSArchitecture -InputObject $OSImageData.OSArchitecture
        if ($OSImageArchitecture -ne $null) {
            Write-CMLogEntry -Value "Operating system architecture detected as: $($OSImageArchitecture)" -Severity 1

            # Set TS Environment variables
            $TSEnvironment.Value("OSUpgradeArchitecture") = $OSImageArchitecture
            Write-CMLogEntry -Value "Setting TSEnvironment variable 'OSUpgradeArchitecture' with value: $($OSImageArchitecture)" -Severity 1
        }
    }
}