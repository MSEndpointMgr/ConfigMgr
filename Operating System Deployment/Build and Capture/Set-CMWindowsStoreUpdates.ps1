<#
.SYNOPSIS
    Disable or Enable Windows Store updates during reference image creation using Configuration Manager.

.DESCRIPTION
    This script disables or enables Windows Store updates to occur during a reference image creation operation with Configuration Manager.
    Put this script right after the Apply Operating System step and run the script with the parameter State set with a value of Disable. At the end of
    the task sequence before the Prepare Configuration Manager Client step, run the script with the parameter State set with a value of Enable.

.PARAMETER State
    Enable or disable Windows Store updates state.

.EXAMPLE
    # Disable Windows Store updates:
    .\Set-CMWindowsStoreUpdates.ps1 -State Disable

    # Enable Windows Store updates:
    .\Set-CMWindowsStoreUpdates.ps1 -State Enable

.NOTES
    FileName:    Set-CMWindowsStoreUpdates.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-04-16
    Updated:     2017-04-16
    
    Version history:
    1.0.0 - (2017-04-16) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Enable or disable Windows Store updates state.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Enable", "Disable")]
    [string]$State
)
Begin {
    # Load Microsoft.SMS.TSEnvironment COM object
    try {
        $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
    }
}
Process {
    # Functions
    function Write-MDTLogEntry {
	    param(
		    [parameter(Mandatory=$true, HelpMessage="Value added to the log file.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$Value,

		    [parameter(Mandatory=$true, HelpMessage="Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		    [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
		    [string]$Severity,

		    [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
		    [ValidateNotNullOrEmpty()]
		    [string]$FileName = "WindowsStoreUpdates.log"
	    )
	    # Determine log file location
        $LogFilePath = Join-Path -Path $Script:TSEnvironment.Value("_SMSTSLogPath") -ChildPath $FileName

        # Construct time stamp for log entry
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))

        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")

        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)

        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""WindowsStoreUpdates"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
	
	    # Add value to log file
        try {
	        Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to WindowsStoreUpdates.log file. Error message: $($_.Exception.Message)"
        }
    }

    # Enable or disable depending on parameter input
    switch ($State) {
        "Enable" {
            try {
                Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsStore\WindowsUpdate" -Name "AutoDownload" -Force -ErrorAction Stop
                Write-MDTLogEntry -Value "Successfully removed AutoDownload value, enabling Windows Store updates" -Severity 1
            }
            catch [System.Exception] {
                Write-MDTLogEntry -Value "Unable to remove AutoDownload value. Error message: $($_.Exception.Message)" -Severity 3
            }
        }
        "Disable" {
            # Load system registry hive
            try {
                $OSDrive = $TSEnvironment.Value("OSDisk")
                $LoadArguments = "load HKLM\Temp $($OSDrive)\Windows\system32\config\SOFTWARE"
                Write-MDTLogEntry -Value "Attempting to load SOFTWARE registry hive from: $($OSDrive)\Windows\system32\config\SOFTWARE" -Severity 1
                Start-Process -FilePath "reg.exe" -ArgumentList $LoadArguments -ErrorAction Stop
                Write-MDTLogEntry -Value "Successfully loaded default software registry hive to HKLM:\Temp" -Severity 1
            }
            catch [System.Exception] {
                Write-MDTLogEntry -Value "Unable to load default software registry hive. Error message: $($_.Exception.Message)" -Severity 3 ; break
            }

            # Wait for registry load
            Write-MDTLogEntry -Value "Waiting for registry hive to be accessible" -Severity 1
            do {
                Start-Sleep -Seconds 1
            }
            until (Test-Path -Path "HKLM:\Temp")

            # Create AutoDownload value
            try {
                New-Item -Path "HKLM:\Temp\Policies\Microsoft\WindowsStore" -ItemType Directory -Force -ErrorAction Stop
                New-ItemProperty -Path "HKLM:\Temp\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -Value 2 -PropertyType "Dword" -Force -ErrorAction Stop
                Write-MDTLogEntry -Value "Successfully changed AutoDownload value to 2 (always off)" -Severity 1
            }
            catch [System.Exception] {
                Write-MDTLogEntry -Value "Unable to create AutoDownload value. Error message: $($_.Exception.Message)" -Severity 3
            }
        }
    }
}
End {
    do {
        try {
            # Clean inactive handles
            [gc]::Collect()

            # Unload system registry hive
            $UnloadArguments = "unload HKLM\Temp"
            Start-Process -FilePath "reg.exe" -ArgumentList $UnloadArguments -Wait -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-MDTLogEntry -Value "Unable to unload default software registry hive. Error message: $($_.Exception.Message)" -Severity 3
        }
    }
    until ((Test-Path -Path HKLM:\Temp) -eq $false)
    Write-MDTLogEntry -Value "Successfully unloaded default software registry hive" -Severity 1
}