# Load Microsoft.SMS.TSEnvironment COM object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
}

# Determine current OS version
$BuildNumber = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber

# Set task sequence variable
try {
    $TSEnvironment.Value("OSDCurrentOSVersion") = "$($BuildNumber)"
}
catch [System.Exception] {
    Write-Warning -Message "An error occured while setting task sequence variable. Error message: $($_.Exception.Message)" ; exit 1
}