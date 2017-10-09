# Load Microsoft.SMS.TSEnvironment COM object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
}

# Detect amount of partitions for system drive
$DriveLetter = $env:SystemDrive.Substring(0,1)
$SystemDrivePartitionCount = (Get-Partition -DriveLetter $DriveLetter | Measure-Object).Count

# Set task sequence variable
try {
    if ($SystemDrivePartitionCount -le 3) {
        $TSEnvironment.Value("OSDConvertToGPT") = "True"
    }
    else {
        $TSEnvironment.Value("OSDConvertToGPT") = "False"
    }
}
catch [System.Exception] {
    Write-Warning -Message "An error occured while setting task sequence variable. Error message: $($_.Exception.Message)" ; exit 1
}