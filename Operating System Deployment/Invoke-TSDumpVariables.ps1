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
        [string]$FileName = "TSVarDump.log"
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
    $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""TSVarDump"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
    
    # Add value to log file
    try {
        Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to append log entry to TSVarDump.log file. Error message: $($_.Exception.Message)"
    }
}

function Get-SensitiveVariable {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Name of a task sequence variable.")]
        [ValidateNotNullOrEmpty()]
        [string]$Variable    
    )
    $SensitiveMatch = $false
    foreach ($SensitiveVariable in @("_OSDOAF", "_SMSTSTaskSequence", "_SMSTSReserved*")) {
        if ($Variable -like $SensitiveVariable) {
            $SensitiveMatch = $true
        }
    }

    return $SensitiveMatch
}

# Load Microsoft.SMS.TSEnvironment COM object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
}

# Start task sequence variable values dumping
Write-CMLogEntry -Value "Starting Task Sequence variable values dumping" -Severity 1

# Process each variable in Microsoft.SMS.TSEnvironment and dump the values
foreach ($TSVariable in ($TSEnvironment.GetVariables())) {
    $Sensitive = Get-SensitiveVariable -Variable $TSVariable
    if ($Sensitive -eq $false) {
        Write-CMLogEntry -Value ("$($TSVariable) = $($TSEnvironment.Value($TSVariable))") -Severity 1
    }
    else {
        Write-CMLogEntry -Value ("$($TSVariable) = **** REMOVED ****") -Severity 1
    }
}

# End task sequence variable values dumping
Write-CMLogEntry -Value "Completed Task Sequence variable values dumping" -Severity 1