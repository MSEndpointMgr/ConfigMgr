<#
.SYNOPSIS
    Create IP address range boundaries in ConfigMgr specified in a CSV file

.DESCRIPTION
    This script will create new IP address range boundaries, from data specified in a CSV, file in ConfigMgr.
    Both IP address range and CIDR notation entries in the CSV are supported in the CSV file, like in the example shown below.

    Part of the conversion from CIDR to start and end IP addresses (and partially re-written in this script) was originally posted by Tao Yang:
    http://blog.tyang.org/2011/05/01/powershell-functions-get-ipv4-network-start-and-end-address/

    Below is a CSV example with valid boundary data types for IP address range and CIDR notation:

    Boundary,DisplayName
    192.168.1.0/24,Internal Network 1
    192.168.2.1-192.168.2.254, Internal Network 2

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER Path
    Specify a path to the CSV file containing boundary data to be imported.

.PARAMETER ShowProgress
    Show a progressbar displaying the current operation.

.EXAMPLE
    Create new IP address range boundaries specified in a CSV file located at C:\Temp\Boundary.csv, on a Primary Site server called 'CM01':
    .\New-CMIPAddressRangeBoundary.ps1 -SiteServer CM01 -Path "C:\Temp\Boundary.csv" -ShowProgress -Verbose

.NOTES
    FileName:    New-CMIPAddressRangeBoundary.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2016-05-16
    Updated:     2016-05-16
    Version:     1.0.0
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify a path to the CSV file containing boundary data to be imported.")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^(?:[\w]\:|\\)(\\[a-z_\-\s0-9\.]+)+\.(csv)$")]
    [ValidateScript({
	    # Check if path contains any invalid characters
	    if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
		    Write-Warning -Message "$(Split-Path -Path $_ -Leaf) contains invalid characters" ; break
	    }
	    else {
		    # Check if the whole directory path exists
		    if (-not(Test-Path -Path (Split-Path -Path $_) -PathType Container -ErrorAction SilentlyContinue)) {
			    Write-Warning -Message "Unable to locate part of or the whole specified path" ; break
		    }
		    elseif (Test-Path -Path (Split-Path -Path $_) -PathType Container -ErrorAction SilentlyContinue) {
			    return $true
		    }
		    else {
			    Write-Warning -Message "Unhandled error" ; break
		    }
	    }
    })]
    [string]$Path,

    [parameter(Mandatory=$false, HelpMessage="Re-encode specified CSV file in UTF8.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("UTF8")]
    [string]$Encoding,

    [parameter(Mandatory=$false, HelpMessage="Show a progressbar displaying the current operation.")]
    [switch]$ShowProgress
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining Site Code for Site server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Verbose -Message "Site Code: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Site Code" ; break
    }

    # Re-encode CSV file as UTF8
    if ($Encoding -like "UTF8") {
        (Get-Content -Path $Path) | Set-Content -Path $Path -Encoding UTF8
    }

    # Get CSV data from specified file
    $BoundaryData = Import-Csv -Path $Path -Delimiter "," -Encoding UTF8
    if ($BoundaryData -eq $null) {
        Write-Warning -Message "Specified CSV file does not contain any data" ; break
    }

    # Validate CSV headers
    $CSVHeaders = (Get-Content -Path $Path | Select-Object -First 1).Split(",")
    if (($CSVHeaders -notcontains "Boundary") -or ($CSVHeaders -notcontains "DisplayName")) {
        Write-Warning -Message "Specified CSV file does not contain the required headers" ; break
    }

    # Count of IP address range boundaries
    $BoundaryCount = ($BoundaryData | Measure-Object).Count
}
Process {
    if ($PSBoundParameters["ShowProgress"]) {
        $ProgressCount = 0
    }

    # Functions
    function ConvertFrom-CIDRNotation {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidatePattern("^(([01]?\d?\d|2[0-4]\d|25[0-5])\.){3}([01]?\d?\d|2[0-4]\d|25[0-5])\/(\d{1}|[0-2]{1}\d{1}|3[0-2])$")]
            [string]$CIDRNotation
        )
        Begin {
            # Determine IP address part from CIDR notation
            $IPAddress = $CIDRNotation.Split("/")[0]
            $NetworkLength = $CIDRNotation.Split("/")[1]
        }
        Process {
            # Determine the start IP address
            try {
                # Get address bytes from IP address
                $StartIPAddressBytes = ([System.Net.IPAddress]$IPAddress).GetAddressBytes()

                # Reverse the order of the address bytes
                [array]::Reverse($StartIPAddressBytes)

                # Reconstruct reversed address bytes and increment address property
                $Address = ([System.Net.IPAddress]($StartIPAddressBytes -join ".")).Address + 1

                # Convert incremented address value to double precision floating point number
                if (($Address.GetType()).Name -ne "Double") {
                    $Address = [System.Convert]::ToDouble($Address)
                }

                # Construct IPAddress object
                $StartIPAddress = [System.Net.IPAddress]$Address
            }
            catch [System.Exception] {
                Write-Warning -Message $_.Exception.Message ; break
            }

            # Determine the end IP address
            try {
                # Get IP address length
                $IPAddressLength = (32 - $NetworkLength)

                # Determine number of IP addresses
                $IPAddressAmount = [System.Math]::Pow(2, $IPAddressLength) - 1

                # Get address bytes from IP address
                $EndIPAddressBytes = ([System.Net.IPAddress]$IPAddress).GetAddressBytes()

                # Reverse the order of the address bytes
                [array]::Reverse($EndIPAddressBytes)

                # Reconstruct reversed address bytes
                $Address = ([System.Net.IPAddress]($EndIPAddressBytes -join ".")).Address - 1

                # Add address and amount
                $EndAddress = $Address + $IPAddressAmount

                # Convert incremented address value to double precision floating point number
                if (($EndAddress.GetType()).Name -ne "Double") {
                    $EndAddress = [System.Convert]::ToDouble($EndAddress)
                }

                # Construct IPAddress object
                $EndIPAddress = [System.Net.IPAddress]$EndAddress
            }
            catch [System.Exception] {
                Write-Warning -Message $_.Exception.Message ; break
            }

            # Construct custom PowerShell object and output to pipeline
            $PSObject = [PSCustomObject]@{
                CIDRNotation = $CIDRNotation
                StartIPv4Address = $StartIPAddress.IPAddressToString
                EndIPv4Address = $EndIPAddress.IPAddressToString
            }
            return $PSObject
        }
    }

    function New-CMBoundaryIPAddressRange {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidatePattern("^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\-[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$")]
            [string]$IPAddressRange,

            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$DisplayName
        )
        Process {
            try {
                $ValidateIPAddressRange = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Boundary -ComputerName $SiteServer -Filter "Value like '$($IPAddressRange)'" -ErrorAction Stop
                if ($ValidateIPAddressRange -eq $null) {
                    if ($PSCmdlet.ShouldProcess($IPAddressRange, "New IP range address boundary")) {
                        # Declare instance arguments
                        $IPAddressRangeArgs = @{
                            DisplayName = $DisplayName
                            BoundaryType = 3
                            Value = $IPAddressRange
                        }
                    
                        # Create new WMI instance in SMS_Boundary class
                        Write-Verbose -Message "Attempting to create IP address range boundary '$($IPAddressRange)' with display name '$($DisplayName)'"
                        Set-WmiInstance -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Boundary -ComputerName $SiteServer -Arguments $IPAddressRangeArgs -ErrorAction Stop -Verbose:$false | Out-Null

                        # Validate IP address range boundary was created successfully
                        $ValidateIPAddressRange = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Boundary -ComputerName $SiteServer -Filter "Value like '$($IPAddressRange)'" -ErrorAction Stop
                        if ($ValidateIPAddressRange -ne $null) {
                            Write-Verbose -Message "Successfully created IP address range boundary '$($IPAddressRange)' with display name '$($DisplayName)'"
                        }
                        else {
                            Write-Warning -Message "Failed to created IP address range boundary '$($IPAddressRange)' with display name '$($DisplayName)'"
                        }
                    }
                }
                else {
                    Write-Warning -Message "Boundary with IP address range '$($IPAddressRange)' already exists"
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create IP address range boundary: '$($IPAddressRange)'"
            }
        }
    }

    # Process all Boundaries specified in CSV file
    foreach ($Boundary in $BoundaryData) {
        Write-Verbose -Message "Processing current boundary data: $($Boundary.Boundary)"

        # Write progress bar output
        if ($PSBoundParameters["ShowProgress"]) {
            $ProgressCount++
            Write-Progress -Activity "Importing IP address range boundaries" -Id 1 -Status "Boundary $($ProgressCount) / $($BoundaryCount)" -CurrentOperation "Current boundary: $($Boundary.Boundary)" -PercentComplete (($ProgressCount / $BoundaryCount) * 100)
        }

        # Determine current Boundary type
        if ($Boundary.Boundary -match "^(([01]?\d?\d|2[0-4]\d|25[0-5])\.){3}([01]?\d?\d|2[0-4]\d|25[0-5])\/(\d{1}|[0-2]{1}\d{1}|3[0-2])$") {
            Write-Verbose -Message "Current boundary data type was determined as CIDR notation"

            # Convert from CIDR notation to IP address range
            $IPAddressRangeObject = ConvertFrom-CIDRNotation -CIDRNotation $Boundary.Boundary
            $IPAddressRange = -join @($IPAddressRangeObject.StartIPv4Address, "-", $IPAddressRangeObject.EndIPv4Address)
            Write-Verbose -Message "Converted CIDR notation '$($Boundary.Boundary)' to IP address range '$($IPAddressRange)'"
            
            # Create Boundary
            New-CMBoundaryIPAddressRange -IPAddressRange $IPAddressRange -DisplayName $Boundary.DisplayName

        }
        elseif ($Boundary.Boundary -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\-[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {
            Write-Verbose -Message "Current boundary data type was determined as IP address range"

            # Create Boundary
            New-CMBoundaryIPAddressRange -IPAddressRange $Boundary.Boundary -DisplayName $Boundary.DisplayName
        }
        else {
            Write-Warning -Message "Unable to determine the boundary data type for object: $($Boundary.Boundary)"
        }
    }   
}