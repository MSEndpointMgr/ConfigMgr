<#
.SYNOPSIS
    Configure Microsoft Edge settings, e.g. enable Home button.

.DESCRIPTION
    This script serves as a template to successfully configure different settings related to Microsoft Edge that requires manipulation of the registry.
    Active Setup is leveraged to perform a run once experience per user. There are three different run modes supported by this script:

    - Stage
        This mode is the initial mode that should be invoked e.g. during operating system deployment with MDT or ConfigMgr. Script is copied to C:\Windows
        and Active Setup is prepared.
    - CreateProcess
        This mode makes sure that the script is re-launched during Active Setup in order not to prolong the logon experience for the end user.
    - Execute
        This mode performs the actual configuration of Microsoft Edge settings.

    Use only the Stage run mode to prepare the system for Active Setup and Microsoft Edge configuration changes.

.EXAMPLE
    .\Set-MicrosoftEdgeSetting.ps1 -RunMode Stage

.NOTES
    Version history:
    1.0.0 - (2016-10-11) Script created

.NOTES
    FileName:    Set-MicrosoftEdgeSetting.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2016-10-11
    Updated:     2016-10-11
    Version:     1.0.0
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Stage","Execute", "CreateProcess")]
    [string]$RunMode
)
Process {
    # Functions
    function Invoke-Process {
        param(
            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,

            [parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Arguments,

            [parameter(Mandatory=$false)]
            [switch]$Hidden,

            [parameter(Mandatory=$false)]
            [switch]$Wait
        )
        # Construct new ProcessStartInfo object
        $ProcessStartInfo = New-Object -TypeName System.Diagnostics.ProcessStartInfo
        $ProcessStartInfo.FileName = $Name
        $ProcessStartInfo.Arguments = $Arguments

        # Hide the process window
        if ($Hidden -eq $true) {
            $ProcessStartInfo.WindowStyle = "Hidden"
            $ProcessStartInfo.CreateNoWindow = $true
        }

        # Instatiate new process
        $Process = [System.Diagnostics.Process]::Start($ProcessStartInfo)

        # Wait for process to terminate
        if ($Wait -eq $true) {
            $Process.WaitForExit()
        }

        # Return exit code from process
        return $Process.ExitCode
    }

    switch ($RunMode) {
        "Stage" {
            if (-not(Test-Path -Path (Join-Path -Path $env:SystemRoot -ChildPath $MyInvocation.MyCommand.Name) -PathType Leaf)) {
                # Stage script in system root directory for ActiveSetup
                try {
                    Copy-Item $MyInvocation.MyCommand.Definition -Destination $env:SystemRoot -ErrorAction Stop
                }
                catch [System.Exception] {
                    Write-Warning -Message "Unable to stage script in system root directory for ActiveSetup. Error message: $($_.Exception.Message)" ; exit
                }
            }

            # Prepare ActiveSetup
            try {
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\EdgeSettings" -type Directory -Force -ErrorAction Stop
                New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\EdgeSettings" -Name Version -Value 1 -PropertyType String -Force -ErrorAction Stop
                New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\EdgeSettings" -Name StubPath -Value "powershell.exe -ExecutionPolicy ByPass -NoProfile -File $(Join-Path -Path $env:SystemRoot -ChildPath $MyInvocation.MyCommand.Name) -RunMode CreateProcess" -PropertyType ExpandString -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to prepare ActiveSetup key. Error message: $($_.Exception.Message)"
            }
        }
        "CreateProcess" {
            # Invoke script for Active Setup
            Invoke-Process -Name "powershell.exe" -Arguments "-ExecutionPolicy Bypass -NoProfile -File $($env:SystemRoot)\$($MyInvocation.MyCommand.Name) -RunMode Execute" -Hidden
        }
        "Execute" {
            # Validate that the Microsoft Edge appcontainer exists
            do {
                Start-Sleep -Seconds 3
            }
            while (-not(Test-Path -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe"))

            ### This section covers a required registry value for most settings you'd want to change
            # Create MicrosoftEdge key
            try {
                New-Item -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge" -type Directory -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create MicrosoftEdge key. Error message: $($_.Exception.Message)"
            }

            # Create Main key
            try {
                New-Item -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -type Directory -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create Main key. Error message: $($_.Exception.Message)"
            }

            ### This section is required when enabling the Home Button to be shown
            # Add HomeButtonEnabled value
            try {
                New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name HomeButtonEnabled -PropertyType DWORD -Value 1 -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create HomeButtonEnabled value. Error message: $($_.Exception.Message)"
            }

            # Add HomeButtonPage value
            try {
                New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name HomeButtonPage -PropertyType String -Value "http://www.google.com" -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create HomeButtonPage value. Error message: $($_.Exception.Message)"
            }
            
            ### This section disables the Welcome screen
            # Add FirstRun key
            try {
                New-Item -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FirstRun" -Type Directory -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create FirstRun key. Error message: $($_.Exception.Message)"
            }

            # Add LastFirstRunVersionDelivered value
            try {
                New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\FirstRun" -Name LastFirstRunVersionDelivered -Value 1 -Type DWORD -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create LastFirstRunVersionDelivered value. Error message: $($_.Exception.Message)"
            }

            # Add IE10TourShown value
            try {
                New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name IE10TourShown -Value 1 -Type DWORD -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create IE10TourShown value. Error message: $($_.Exception.Message)"
            }

            ### This section disables the default browser prompt
            # Add DisallowDefaultBrowserPrompt value
            try {
                New-ItemProperty -Path "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe\MicrosoftEdge\Main" -Name "DisallowDefaultBrowserPrompt" -Value 1 -Type DWORD -Force -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to create DisallowDefaultBrowserPrompt value. Error message: $($_.Exception.Message)"
            }            
        }
    }
}