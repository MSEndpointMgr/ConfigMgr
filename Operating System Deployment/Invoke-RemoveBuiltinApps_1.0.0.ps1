<#
.SYNOPSIS
    Remove built-in apps (modern apps) from Windows 10.

.DESCRIPTION
    This script will remove all built-in apps with a provisioning package that's not specified in the 'white-list' in this script.
    It supports MDT and ConfigMgr usage, but only for online scenarios, meaning it can't be executed during the WinPE phase.

    For a more detailed list of applications available in each version of Windows 10, refer to the documentation here:
    https://docs.microsoft.com/en-us/windows/application-management/apps-in-windows-10

.EXAMPLE
    .\Invoke-RemoveBuiltinApps.ps1

.NOTES
    FileName:    Invoke-RemoveBuiltinApps.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2019-03-10
    Updated:     2019-03-10

    Version history:
    1.0.0 - (2019-03-10) Initial script updated with help section
    1.0.1 - (2019-03-11) Added code to disable/enable the AppReadiness service
    1.0.2 - (2019-03-12) Added code to wait for 3 seconds before attempting to remove appx provisioning package
#>
Begin {
    # White list of Features On Demand V2 packages
    $WhiteListOnDemand = "NetFX3|Tools.Graphics.DirectX|Tools.DeveloperMode.Core|Language|Browser.InternetExplorer|ContactSupport|OneCoreUAP|Media.WindowsMediaPlayer"

    # White list of appx packages to keep installed
    $WhiteListedApps = New-Object -TypeName System.Collections.ArrayList
    $WhiteListedApps.AddRange(@(
        "Microsoft.DesktopAppInstaller",
        "Microsoft.Messaging", 
        "Microsoft.MSPaint",
        "Microsoft.Windows.Photos",
        "Microsoft.StorePurchaseApp",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.WindowsAlarms",
        "Microsoft.WindowsCalculator", 
        "Microsoft.WindowsCommunicationsApps", # Mail, Calendar etc
        "Microsoft.WindowsSoundRecorder", 
        "Microsoft.WindowsStore"
    ))

    # Windows 10 version 1809
    $WhiteListedApps.AddRange(@(
        "Microsoft.ScreenSketch",
        "Microsoft.HEIFImageExtension",
        "Microsoft.VP9VideoExtensions",
        "Microsoft.WebMediaExtensions",
        "Microsoft.WebpImageExtension"
    ))
}
Process {
    # Functions
    function Write-LogEntry {
        param(
            [parameter(Mandatory=$true, HelpMessage="Value added to the RemovedApps.log file.")]
            [ValidateNotNullOrEmpty()]
            [string]$Value,

            [parameter(Mandatory=$false, HelpMessage="Name of the log file that the entry will written to.")]
            [ValidateNotNullOrEmpty()]
            [string]$FileName = "RemovedApps.log"
        )
        # Determine log file location
        $LogFilePath = Join-Path -Path $env:windir -ChildPath "Temp\$($FileName)"

        # Add value to log file
        try {
            Out-File -InputObject $Value -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to RemovedApps.log file"
        }
    }

    function Set-RegistryValue {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,

            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Value,

            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("DWORD", "String")]
            [string]$Type
        )
        try {
            $RegistryValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
            if ($RegistryValue -ne $null) {
                Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force -ErrorAction Stop
            }
            else {
                New-ItemProperty -Path $Path -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "Failed to create or update registry value '$($Name)' in '$($Path)'. Error message: $($_.Exception.Message)"
        }
    }

	function Invoke-Executable {
		param (
			[parameter(Mandatory = $true, HelpMessage = "Specify the file name or path of the executable to be invoked, including the extension")]
			[ValidateNotNullOrEmpty()]
			[string]$FilePath,
			[parameter(Mandatory = $false, HelpMessage = "Specify arguments that will be passed to the executable")]
			[ValidateNotNull()]
			[string]$Arguments
		)
		
		# Construct a hash-table for default parameter splatting
		$SplatArgs = @{
			FilePath	 = $FilePath
			NoNewWindow  = $true
			Passthru	 = $true
			ErrorAction  = "Stop"
		}
		
		# Add ArgumentList param if present
		if (-not ([System.String]::IsNullOrEmpty($Arguments))) {
			$SplatArgs.Add("ArgumentList", $Arguments)
		}
		
		# Invoke executable and wait for process to exit
		try {
			$Invocation = Start-Process @SplatArgs
			$Handle = $Invocation.Handle
			$Invocation.WaitForExit()
		}
		catch [System.Exception] {
			Write-Warning -Message $_.Exception.Message; break
		}
		
		return $Invocation.ExitCode
	}    

    # Initial logging
    Write-LogEntry -Value "Starting built-in AppxPackage, AppxProvisioningPackage and Feature on Demand V2 removal process"

    # Disable automatic store updates, consumer experience and disable InstallService
    try {
        # Disable auto-download of store apps
        Write-LogEntry -Value "Adding registry value to disable automatic store updates"
        $RegistryWindowsStorePath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
        if (-not(Test-Path -Path $RegistryWindowsStorePath)) {
            New-Item -Path $RegistryWindowsStorePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Set-RegistryValue -Path $RegistryWindowsStorePath -Name "AutoDownload" -Value "2" -Type "DWORD"

        # Disable Windows consumer features
        Write-LogEntry -Value "Adding registry value to disable consumer features"
        $RegistryCloudContent = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        if (-not(Test-Path -Path $RegistryCloudContent)) {
            New-Item -Path $RegistryCloudContent -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
        Set-RegistryValue -Path $RegistryCloudContent -Name "DisableWindowsConsumerFeatures" -Value "1" -Type "DWORD"

        # Disable the InstallService service
        Write-LogEntry -Value "Attempting to stop the InstallService service for automatic store updates"
        Stop-Service -Name "InstallService" -Force -ErrorAction Stop
        Write-LogEntry -Value "Attempting to set the InstallService startup behavior to Disabled"
        Set-Service -Name "InstallService" -StartupType "Disabled" -ErrorAction Stop

        # Disable the AppReadiness service
        Write-LogEntry -Value "Attempting to stop the AppReadiness service for automatic store updates"
        Stop-Service -Name "AppReadiness" -Force -ErrorAction Stop
        Write-LogEntry -Value "Attempting to set the AppReadiness startup behavior to Disabled"
        Set-Service -Name "AppReadiness" -StartupType "Disabled" -ErrorAction Stop        
    }
    catch [System.Exception] {
        Write-LogEntry -Value "Failed to disable automatic store updates: $($_.Exception.Message)"
    }

    # Determine provisioned apps
    $AppArrayList = Get-AppxProvisionedPackage -Online | Select-Object -ExpandProperty DisplayName

    # Loop through the list of appx packages
    foreach ($App in $AppArrayList) {
        Write-LogEntry -Value "Processing appx package: $($App)"

        # If application name not in appx package white list, remove AppxPackage and AppxProvisioningPackage
        if (($App -in $WhiteListedApps)) {
            Write-LogEntry -Value "Skipping excluded application package: $($App)"
        }
        else {
            # Attempt to remove AppxPackage
            $AppPackageFullName = Get-AppxPackage -Name $App | Select-Object -ExpandProperty PackageFullName -First 1
            if ($AppPackageFullName -ne $null) {
                try {
                    Write-LogEntry -Value "Removing AppxPackage: $($AppPackageFullName)"
                    Remove-AppxPackage -Package $AppPackageFullName -ErrorAction Stop | Out-Null
                }
                catch [System.Exception] {
                    Write-LogEntry -Value "Removing AppxPackage '$($AppPackageFullName)' failed: $($_.Exception.Message)"
                }
            }
            else {
                Write-LogEntry -Value "Unable to locate AppxPackage: $($AppPackageFullName)"
            }

            # Attempt to remove AppxProvisioningPackage
            Start-Sleep -Seconds 3
            $AppProvisioningPackageName = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Select-Object -ExpandProperty PackageName -First 1
            if ($AppProvisioningPackageName -ne $null) {
                try {

                    #
                    # Idea 1: Check if InstallService service is running at this time, wait for it to complete
                    # Idea 2: Test with: dism.exe /Online /Remove-ProvisionedAppxPackage /PackageName:microsoft.devx.appx.app1_1.0.0.0_neutral_ac4zc6fex2zjp
                    #

                    Write-LogEntry -Value "Removing AppxProvisioningPackage: $($AppProvisioningPackageName)"
                    #Remove-AppxProvisionedPackage -PackageName $AppProvisioningPackageName -Online -ErrorAction Stop | Out-Null
                    $Invocation = Invoke-Executable -FilePath "dism.exe" -Arguments "/Online /Remove-ProvisionedAppxPackage /PackageName:$($AppProvisioningPackageName)"
                    if ($Invocation -eq 0) {
                        Write-LogEntry -Value "Successfully removed AppxProvisioningPackage: $($AppProvisioningPackageName)"
                    }
                    else {
                        Write-LogEntry -Value "Failed to remove AppxProvisioningPackage, exit code $($Invocation) returned from process"
                    }
                }
                catch [System.Exception] {
                    Write-LogEntry -Value "Removing AppxProvisioningPackage '$($AppProvisioningPackageName)' failed: $($_.Exception.Message)"
                }
            }
            else {
                Write-LogEntry -Value "Unable to locate AppxProvisioningPackage: $($AppProvisioningPackageName)"
            }
        }
    }

    # Enable store automatic updates
    try {
        Write-LogEntry -Value "Attempting to remove automatic store update registry values"
        Remove-ItemProperty -Path $RegistryWindowsStorePath -Name "AutoDownload" -Force -ErrorAction Stop
        Remove-ItemProperty -Path $RegistryCloudContent -Name "DisableWindowsConsumerFeatures" -Force -ErrorAction Stop
        Write-LogEntry -Value "Attempting to set the InstallService startup behavior to Manual"
        Set-Service -Name "InstallService" -StartupType "Manual" -ErrorAction Stop
        Write-LogEntry -Value "Attempting to set the AppReadiness startup behavior to Manual"
        Set-Service -Name "AppReadiness" -StartupType "Manual" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-LogEntry -Value "Failed to enable automatic store updates: $($_.Exception.Message)"
    }

    Write-LogEntry -Value "Starting Features on Demand V2 removal process"

    # Get Features On Demand that should be removed
    try {
        $OSBuildNumber = Get-WmiObject -Class "Win32_OperatingSystem" | Select-Object -ExpandProperty BuildNumber

        # Handle cmdlet limitations for older OS builds
        if ($OSBuildNumber -le "16299") {
            $OnDemandFeatures = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -notmatch $WhiteListOnDemand -and $_.State -like "Installed"} | Select-Object -ExpandProperty Name
        }
        else {
            $OnDemandFeatures = Get-WindowsCapability -Online -LimitAccess -ErrorAction Stop | Where-Object { $_.Name -notmatch $WhiteListOnDemand -and $_.State -like "Installed"} | Select-Object -ExpandProperty Name
        }

        foreach ($Feature in $OnDemandFeatures) {
            try {
                Write-LogEntry -Value "Removing Feature on Demand V2 package: $($Feature)"

                # Handle cmdlet limitations for older OS builds
                if ($OSBuildNumber -le "16299") {
                    Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like $Feature } | Remove-WindowsCapability -Online -ErrorAction Stop | Out-Null
                }
                else {
                    Get-WindowsCapability -Online -LimitAccess -ErrorAction Stop | Where-Object { $_.Name -like $Feature } | Remove-WindowsCapability -Online -ErrorAction Stop | Out-Null
                }
            }
            catch [System.Exception] {
                Write-LogEntry -Value "Removing Feature on Demand V2 package failed: $($_.Exception.Message)"
            }
        }    
    }
    catch [System.Exception] {
        Write-LogEntry -Value "Attempting to list Feature on Demand V2 packages failed: $($_.Exception.Message)"
    }

    # Complete
    Write-LogEntry -Value "Completed built-in AppxPackage, AppxProvisioningPackage and Feature on Demand V2 removal process"
}