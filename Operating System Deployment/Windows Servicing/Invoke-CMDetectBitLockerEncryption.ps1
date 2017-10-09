# Load Microsoft.SMS.TSEnvironment COM object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
}

# Detect encrypted drives
$OSDriveEncrypted = $false
$EncryptedVolumes = Get-WmiObject -Namespace "root\cimv2\Security\MicrosoftVolumeEncryption" -Class "Win32_EncryptableVolume"
foreach ($Volume in $EncryptedVolumes) {
    if ($Volume.DriveLetter -like $env:SystemDrive) {
        if ($Volume.EncryptionMethod -ge 1) {
            $OSDriveEncrypted = $true
        }
    }
}

# Set task sequence variable
try {
    $TSEnvironment.Value("OSDBitLockerEncrypted") = "$($OSDriveEncrypted)"
}
catch [System.Exception] {
    Write-Warning -Message "An error occured while setting task sequence variable. Error message: $($_.Exception.Message)" ; exit 1
}