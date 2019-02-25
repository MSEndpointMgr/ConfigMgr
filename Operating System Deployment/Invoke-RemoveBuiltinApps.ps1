# https://github.com/SCConfigMgr/ConfigMgr
# ConfigMgr/Operating System Deployment/Invoke-RemoveBuiltinApps.ps1
####################################################################################
$CompanyName            = "Contoso"

# CMTrace Compatible Log Files
$Global:CMLogFilePath   = "C:\$CompanyName\RemoveAPPXv4.log"
$Global:CMLogFileSize   = "40" # Rollover size in KB
####################################################################################

function Start-CMTraceLog
{
    # Checks for path to log file and creates if it does not exist
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
            
    )

    $indexoflastslash = $Path.lastindexof('\')
    $directory = $Path.substring(0, $indexoflastslash)

    if (!(test-path -path $directory))
    {
        New-Item -ItemType Directory -Path $directory
    }
    else
    {
        # Directory Exists, do nothing    
    }

    # return 0;
}

function Write-CMTraceLog
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
            
        [Parameter()]
        [ValidateSet(1, 2, 3)]
        [int]$LogLevel = 1,

        [Parameter()]
        [string]$Component,

        [Parameter()]
        [ValidateSet('Info','Warning','Error')]
        [string]$Type
    )
    $LogPath = $Global:CMLogFilePath

    Switch ($Type)
    {
        Info {$LogLevel = 1}
        Warning {$LogLevel = 2}
        Error {$LogLevel = 3}
    }

    # Get Date message was triggered
    $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"

    $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'

    # When used as a module, this gets the line number and position and file of the calling script
    # $RunLocation = "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)"

    $LineFormat = $Message, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), $Component, $LogLevel
    $Line = $Line -f $LineFormat

    # Write new line in the log file
    Add-Content -Value $Line -Path $LogPath

    # Roll log file over at size threshold
    if ((Get-Item $Global:CMLogFilePath).Length / 1KB -gt $Global:CMLogFileSize)
    {
        $log = $Global:CMLogFilePath
        Remove-Item ($log.Replace(".log", ".lo_"))
        Rename-Item $Global:CMLogFilePath ($log.Replace(".log", ".lo_")) -Force
    }
} 

# Start the log up
Start-CMTraceLog -Path $Global:CMLogFilePath

# Functions
# Depreciating since this logger is obsolete
function Write-LogEntry
{
    param(
        [parameter(Mandatory = $true, HelpMessage = "Value added to the RemovedApps.log file.")]
        [ValidateNotNullOrEmpty()]
        [string]$Value,

        [parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
        [ValidateNotNullOrEmpty()]
        [string]$FileName = "RemovedApps.log"
    )
    # Determine log file location
    $LogFilePath = Join-Path -Path $env:windir -ChildPath "Temp\$($FileName)"

    # Add value to log file
    try
    {
        Out-File -InputObject $Value -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
    }
    catch [System.Exception]
    {
        Write-Warning -Message "Unable to append log entry to RemovedApps.log file"
    }
}

# Get a list of all apps
# Write-LogEntry -Value "Starting built-in AppxPackage, AppxProvisioningPackage and Feature on Demand V2 removal process"
Write-CMTraceLog -Message "Starting built-in AppxPackage, AppxProvisioningPackage and Feature on Demand V2 removal process" -Component "Main" -Type "Info"

$AppArrayList = Get-AppxPackage -PackageTypeFilter Bundle -AllUsers | Select-Object -Property Name, PackageFullName | Sort-Object -Property Name

# White list of appx packages to keep installed
$WhiteListedApps = New-Object -TypeName System.Collections.ArrayList
$WhiteListedApps.AddRange(@(
    "Microsoft.DesktopAppInstaller", 
    "Microsoft.MSPaint",
    "Microsoft.Windows.Photos",
    "Microsoft.StorePurchaseApp",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.WindowsAlarms",
    "Microsoft.WindowsCalculator", 
    "Microsoft.WindowsSoundRecorder", 
    "Microsoft.BingWeather",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.WindowsStore",
    "Microsoft.WindowsMaps",
    "Microsoft.WindowsCamera",
    "Microsoft.AAD.BrokerPlugin",
    "Microsoft.WindowsAlarms"
))

# Windows 10 version 1809
$WhiteListedApps.AddRange(@(
    "Microsoft.ScreenSketch",
    "Microsoft.HEIFImageExtension",
    "Microsoft.VP9VideoExtensions",
    "Microsoft.WebMediaExtensions",
    "Microsoft.WebpImageExtension"
))

# Loop through the list of appx packages
foreach ($App in $AppArrayList)
{
    # If application name not in appx package white list, remove AppxPackage and AppxProvisioningPackage
    if (($App.Name -in $WhiteListedApps))
    {
        # Write-LogEntry -Value "Skipping excluded application package: $($App.Name)"
        Write-CMTraceLog -Message "   Skipping excluded application package: $($App.Name) (WhiteListedApp)" -Component "Main" -Type "Info"
    }
    else
    {
        # Gather package names
        $AppPackageFullName = Get-AppxPackage -Name $App.Name | Select-Object -ExpandProperty PackageFullName -First 1
        $AppProvisioningPackageName = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App.Name } | Select-Object -ExpandProperty PackageName -First 1

        # Attempt to remove AppxPackage
        if ($null -ne $AppPackageFullName)
        {
            try
            {
                # Write-LogEntry -Value "Removing AppxPackage: $($AppPackageFullName)"
                Write-CMTraceLog -Message "   Removing AppxPackage: $($AppPackageFullName)" -Component "Main" -Type "Info"

                Remove-AppxPackage -Package $AppPackageFullName -ErrorAction Stop | Out-Null
            }
            catch [System.Exception]
            {
                # Write-LogEntry -Value "Removing AppxPackage '$($AppPackageFullName)' failed: $($_.Exception.Message)"
                Write-CMTraceLog -Message "   Removing AppxPackage '$($AppPackageFullName)' failed: $($_.Exception.Message)" -Component "Main" -Type "Error"
            }
        }
        else
        {
            # Write-LogEntry -Value "Unable to locate AppxPackage: $($AppPackageFullName)"
            Write-CMTraceLog -Message "   Unable to locate AppxPackage: $($AppPackageFullName)" -Component "Main" -Type "Error"
        }

        # Attempt to remove AppxProvisioningPackage
        if ($null -ne $AppProvisioningPackageName)
        {
            try
            {
                # Write-LogEntry -Value "Removing AppxProvisioningPackage: $($AppProvisioningPackageName)"
                Write-CMTraceLog -Message "   Removing AppxProvisioningPackage: $($AppProvisioningPackageName)" -Component "Main" -Type "Info"

                Remove-AppxProvisionedPackage -PackageName $AppProvisioningPackageName -Online -ErrorAction Stop | Out-Null
            }
            catch [System.Exception]
            {
                # Write-LogEntry -Value "Removing AppxProvisioningPackage '$($AppProvisioningPackageName)' failed: $($_.Exception.Message)"
                Write-CMTraceLog -Message "   Removing AppxProvisioningPackage '$($AppProvisioningPackageName)' failed: $($_.Exception.Message)" -Component "Main" -Type "Error"
            }
        }
        else
        {
            # Write-LogEntry -Value "Unable to locate AppxProvisioningPackage: $($AppProvisioningPackageName)"
            Write-CMTraceLog -Message "   Unable to locate AppxProvisioningPackage: $($AppProvisioningPackageName)" -Component "Main" -Type "Error"
        }
    }
}

# White list of Features On Demand V2 packages
# Write-LogEntry -Value "Starting Features on Demand V2 removal process"
Write-CMTraceLog -Message "Starting Features on Demand V2 removal process" -Component "Main" -Type "Info"

$WhiteListOnDemand = "NetFX3|Tools.Graphics.DirectX|Tools.DeveloperMode.Core|Language|Browser.InternetExplorer|ContactSupport|OneCoreUAP|Media.WindowsMediaPlayer"

# Get Features On Demand that should be removed
try
{
    $OSBuildNumber = Get-WmiObject -Class "Win32_OperatingSystem" | Select-Object -ExpandProperty BuildNumber

    # Handle cmdlet limitations for older OS builds
    if ($OSBuildNumber -le "16299")
    {
        $OnDemandFeatures = Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -notmatch $WhiteListOnDemand -and $_.State -like "Installed"} | Select-Object -ExpandProperty Name
    }
    else
    {
        $OnDemandFeatures = Get-WindowsCapability -Online -LimitAccess -ErrorAction Stop | Where-Object { $_.Name -notmatch $WhiteListOnDemand -and $_.State -like "Installed"} | Select-Object -ExpandProperty Name
    }

    foreach ($Feature in $OnDemandFeatures)
    {
        try
        {
            # Write-LogEntry -Value "Removing Feature on Demand V2 package: $($Feature)"
            Write-CMTraceLog -Message "   Removing Feature on Demand V2 package: $($Feature)" -Component "Main" -Type "Info"

            # Handle cmdlet limitations for older OS builds
            if ($OSBuildNumber -le "16299")
            {
                Get-WindowsCapability -Online -ErrorAction Stop | Where-Object { $_.Name -like $Feature } | Remove-WindowsCapability -Online -ErrorAction Stop | Out-Null
            }
            else
            {
                Get-WindowsCapability -Online -LimitAccess -ErrorAction Stop | Where-Object { $_.Name -like $Feature } | Remove-WindowsCapability -Online -ErrorAction Stop | Out-Null
            }
        }
        catch [System.Exception]
        {
            # Write-LogEntry -Value "Removing Feature on Demand V2 package failed: $($_.Exception.Message)"
            Write-CMTraceLog -Message "   Removing Feature on Demand V2 package failed: $($_.Exception.Message)" -Component "Main" -Type "Info"
        }
    }    
}
catch [System.Exception]
{
    # Write-LogEntry -Value "Attempting to list Feature on Demand V2 packages failed: $($_.Exception.Message)"
    Write-CMTraceLog -Message "   Removing Feature on Demand V2 package failed: $($_.Exception.Message)" -Component "Main" -Type "Error"
}

# Complete
# Write-LogEntry -Value "Completed built-in AppxPackage, AppxProvisioningPackage and Feature on Demand V2 removal process"
Write-CMTraceLog -Message "Completed built-in AppxPackage, AppxProvisioningPackage and Feature on Demand V2 removal process" -Component "Main" -Type "Info"
