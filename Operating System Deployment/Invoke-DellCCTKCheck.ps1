<#
.SYNOPSIS
    Detect the version of CCTK compatible with your Dell system during OS deployment tasks calling the CCTK BIOS application.

.DESCRIPTION
    Detect the version of CCTK compatible with your Dell system during OS deployment tasks calling the CCTK BIOS application.

.EXAMPLE
    .\Invoke-DellCCTKCheck.ps1

.NOTES
    FileName:    Invoke-DellCCTKCheck.ps1
    Author:      Maurice Daly
    Contact:     @MoDaly_IT
    Created:     2019-03-11
    Updated:     2019-03-11

    Version history:
    1.0.0 - (2019-03-11) Script created
#>
Begin {
	# Load Microsoft.SMS.TSEnvironment COM object
	try {
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object"; break
	}
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
			[string]$FileName = "ApplyDriverPackage.log"
		)
        # Determine log file location
        $LogsDirectory = Join-Path -Path $TSEnvironment.Value("_SMSTSLogPath") -ChildPath "Temp"
		$LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
		
		# Construct time stamp for log entry
		$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
		# Construct date for log entry
		$Date = (Get-Date -Format "MM-dd-yyyy")
		
		# Construct context for log entry
		$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
		# Construct final log entry
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""ApplyDriverPackage"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
		# Add value to log file
		try {
			Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to ApplyDriverPackage.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
		}
    }
    
    # Determine the CCTK version
    Write-CMLogEntry -Value "Starting Dell CCTK compatibility check" -Severity 1
    $CCTKVersion = (Get-ItemProperty -Path ".\CCTK.exe" | Select-Object -ExpandProperty VersionInfo).ProductVersion
    
    # Call CCTK application to determine the exit code
	Write-CMLogEntry -Value "Running Dell CCTK version $($CCTKVersion) on host system" -Severity 1
	$CCTKExitCode = (Start-Process -Path "CCTK.exe" -Wait -PassThru -WindowStyle Minimized).ExitCode
    
    # Determine the CCTK application path based on exit code
    Write-CMLogEntry -Value "Reading Dell CCTK running output" -Severity 1
	if (($CCTKExitCode -like "141") -or ($CCTKExitCode -like "140")) {
		Write-CMLogEntry -Value "Non WMI-ACPI BIOS detected, setting CCTK legacy mode" -Severity 2
		$CCTKPath = Join-Path -Path $((Get-Location).Path) -ChildPath "Legacy"
		$TSEnvironment.Value("DellNewCCTKCmds") = $false
	}
	else {
		Write-CMLogEntry -Value "WMI-ACPI BIOS detected" -Severity 1
		$CCTKPath = (Get-Location).Path
		$TSEnvironment.Value("DellNewCCTKCmds") = $true
    }
    
    # Set task sequence variable with path for CCTK application
	Write-CMLogEntry -Value "Setting DellCCTKPath task sequence variable with the following value: $($CCTKPath)" -Severity 1
	$TSEnvironment.Value("DellCCTKPath") = $CCTKPath
}