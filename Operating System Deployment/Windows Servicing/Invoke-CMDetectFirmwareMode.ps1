# Load Microsoft.SMS.TSEnvironment COM object
try {
    $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object" ; exit 1
}

# Load firmware type from kernel32.dll
Add-Type -Language CSharp -TypeDefinition @"

    using System;
    using System.Runtime.InteropServices;

    public class FirmwareType
    {
        [DllImport("kernel32.dll")]
        static extern bool GetFirmwareType(ref uint FirmwareType);

        public static uint GetFirmwareType()
        {
            uint firmwaretype = 0;
            if (GetFirmwareType(ref firmwaretype))
                return firmwaretype;
            else
                return 0;
        }
    }
"@

# Determine firmware type
switch ([FirmwareType]::GetFirmwareType()) {
    1 { $FirmwareType = "BIOS" }
    2 { $FirmwareType = "UEFI" }
    0 { $FirmwareType = "Unknown" }
}

# Set task sequence variable
try {
    $TSEnvironment.Value("OSDFirmwareType") = "$($FirmwareType)"
}
catch [System.Exception] {
    Write-Warning -Message "An error occured while setting task sequence variable. Error message: $($_.Exception.Message)" ; exit 1
}