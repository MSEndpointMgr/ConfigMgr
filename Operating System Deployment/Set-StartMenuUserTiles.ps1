<#
.SYNOPSIS
    Pin application tiles in the start menu for the current user.

.DESCRIPTION
    This script can pin any supported application to the user customizable portion of the start menu, even when a partially locked start menu is used.
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
    .\Set-StartMenuUserTiles.ps1 -RunMode Stage

.NOTES
    Version history:
    1.0.0 - (2018-09-18) Script created

.NOTES
    FileName:    Set-StartMenuUserTiles.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-09-18
    Updated:     2018-09-18
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
                New-Item -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\StartMenu" -type Directory -Force -ErrorAction Stop
                New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\StartMenu" -Name Version -Value 1 -PropertyType String -Force -ErrorAction Stop
                New-ItemProperty "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\StartMenu" -Name StubPath -Value "powershell.exe -ExecutionPolicy ByPass -NoProfile -File $(Join-Path -Path $env:SystemRoot -ChildPath $MyInvocation.MyCommand.Name) -RunMode CreateProcess" -PropertyType ExpandString -Force -ErrorAction Stop
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
            # Functions
            function Get-PinnedAppState {
                param(
                    [parameter(Mandatory=$true, HelpMessage="Name of a pinned application.")]
                    [ValidateNotNullOrEmpty()]
                    [string]$ApplicationName
                )
                $PinnedApp = ((New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | Where-Object { $_.Name -like $ApplicationName }).verbs() | Where-Object { $_.Name.replace('&', '') -match 'Unpin from Start' }
                if ($PinnedApp -ne $null) {
                    return $true
                }
                else {
                    return $false
                }
            }

            function Get-Application {
                param(
                    [parameter(Mandatory=$true, HelpMessage="Name of an application.")]
                    [ValidateNotNullOrEmpty()]
                    [string]$ApplicationName
                )
                # Get all applications
                $Applications = (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items()  
                $Applications = $Applications | Sort-Object -Property Name -Unique

                # Construct a list object for all applications and add each item from the string array
                $ApplicationList = New-Object -TypeName System.Collections.ArrayList
                foreach ($Application in $Applications) {
                    $ApplicationList.Add($Application.Name) | Out-Null
                    $Application
                }

                # Check to see if application name from parameter input is in the application list
                if ($ApplicationName -in $ApplicationList) {
                    return $true
                }
                else {
                    return $false
                }
            }

            # Set PowerShell variables
            $ErrorActionPreference = "Stop"

            # Create list of applications to be pinned to the start menu
            $AppList = @("Command prompt", "Calendar")

            foreach ($ApplicationName in $AppList) {
                # Check if the specified parameter input is valid
                $ValidApplication = Get-Application -ApplicationName $ApplicationName
                if ($ValidApplication -eq $true) {
                    # Check if app is already pinned
                    $PinnedState = Get-PinnedAppState -ApplicationName $ApplicationName
                    if ($PinnedState -eq $false) {
                        try {
                            # Attempt to pin the application
                            $InvokePin = ((New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items() | Where-Object { $_.Name -like $ApplicationName }).verbs() | Where-Object { $_.Name.replace('&', '') -match 'Pin to Start' } | ForEach-Object { $_.DoIt() }
                            Write-Verbose -Message "Successfully pinned application: $($ApplicationName)"
                        }
                        catch [System.Exception] {
                            Write-Warning -Message "Failed to pin application '$($ApplicationName)'. Error message: $($_.Exception.Message)"
                        }
                    }
                    else {
                        Write-Warning -Message "Application '$($ApplicationName)' is already pinned to the start menu"
                    }
                }
                else {
                    Write-Warning -Message "Invalid application name specified"
                }
            }
        }
    }
}