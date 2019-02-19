<#
.SYNOPSIS
	Set a custom image as the lock screen image on Windows 10.
	
.DESCRIPTION
    This script can set a custom image as the lock screen image on Windows 10. An image file named lockscreen.jpg
    needs to be available for the script to read in the same directory where the script is launched from. 
    The lockscreen.jpg file needs to be in a supported resolution, e.g. 1920x1080.

.PARAMETER State
    Set a custom lock screen image or revert to previously used image.
    
.PARAMETER Force
    Enforce the custom lock screen image change by logging off all users currently logged in.

.EXAMPLE
	# Enable the logon maintenance message:
	.\Set-LockScreenImage.ps1 -State "Custom"

	# Disable the logon maintenance message:
	.\Set-LockScreenImage.ps1 -State "Revert"

.NOTES
    FileName:    Set-LockScreenImage.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2018-12-18
	Updated:     2019-01-23
  
    Version history:
    1.0.0 - (2018-12-18) Script created
    1.0.1 - (2019-01-23) Updated the Force switch to log off all users instead of terminating the winlogon processes
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
	[parameter(Mandatory = $true, HelpMessage = "Set a custom lock screen image or revert to previously used image.")]
	[ValidateNotNullOrEmpty()]
	[ValidateSet("Custom", "Revert")]
    [string]$State,
    
	[parameter(Mandatory = $false, HelpMessage = "Enforce the custom lock screen image change by logging off all users currently logged in.")]
	[switch]$Force
)
Process {
    # Functions
    function Test-RegistryKey {
        param(
            [parameter(Mandatory=$true, HelpMessage="Path to key where value to test exists")]
            [ValidateNotNullOrEmpty()]
            [string]$Path,
    
            [parameter(Mandatory=$false, HelpMessage="Name of the value")]
            [ValidateNotNullOrEmpty()]
            [string]$Name
        )
        # If item property value exists return True, else catch the failure and return False
        try {
            if ($PSBoundParameters["Name"]) {
                $Existence = Get-ItemProperty -Path $Path | Select-Object -ExpandProperty $Name -ErrorAction Stop
            }
            else {
                $Existence = Get-ItemProperty -Path $Path -ErrorAction Stop
            }
            
            if ($Existence -ne $null) {
                return $true
            }
        }
        catch [System.Exception] {
            return $false
        }
    }    

	function Update-RegistryValue {
		param (
			[parameter(Mandatory=$false, HelpMessage="The registy key to work with.")]
			[ValidateNotNullOrEmpty()]
			[string]$RegistryKey,

			[parameter(Mandatory=$false, HelpMessage="The registry item to restore.")]
			[ValidateNotNullOrEmpty()]
			[string]$RegistryItem,

			[parameter(Mandatory=$false, HelpMessage="The registry item to restore.")]
			[ValidateNotNullOrEmpty()]
			[string]$RegistryValue,

			[parameter(Mandatory=$true, HelpMessage="The file to use.")]
			[ValidateNotNullOrEmpty()]
			[string]$File,

			[parameter(Mandatory=$true, HelpMessage="The job type, backup or restore.")]
			[ValidateNotNullOrEmpty()]
			[ValidateSet("Backup", "Restore")]
			[string]$Action
		)
		switch ($Action) {
			"Backup" {
				$RegistryValue | Out-File -Encoding ASCII -FilePath $File -Force
			}
			"Restore" {
				if ((Test-Path -Path $File) -eq $true) {
					$Content = [string]::join([environment]::NewLine, (Get-Content -Path $File))
					Set-ItemProperty -Path $RegistryKey -Name $RegistryItem -Value $Content
				}
				else {
					Set-ItemProperty -Path $RegistryKey -Name $RegistryItem -Value $null
				}
			}
		}
	}

	# Define Variables
	$PersonalizationRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    $LockScreenBackupFile = Join-Path -Path $env:SystemRoot -ChildPath "TEMP\LockScreenBackup.txt"

	switch ($State) {
		"Custom" {
            # Locate the lockscreen.jpg image from within the script root directory
            $LockScreenImagePath = Join-Path -Path $PSScriptRoot -ChildPath "lockscreen.jpg"

            if (Test-Path -Path $LockScreenImagePath) {
                # Copy lockscreen.jpg to local directory
                $LocalLockScreenImagePath = Join-Path -Path $env:SystemRoot -ChildPath "TEMP\lockscreen.jpg"
                Write-Verbose -Message "Copying lock screen image to temporary location: $($LocalLockScreenImagePath)"
                Copy-Item -Path $LockScreenImagePath -Destination $LocalLockScreenImagePath -Force
                
                # Ensure that Personalization registry key exists, if not create it
                if (-not(Test-Path -Path $PersonalizationRegPath)) {
                    New-Item -Path $PersonalizationRegPath -ItemType Directory -Force
                    Write-Verbose -Message "Successfully created the Personalization registry key for System context"
                }

                # Backup lock screen registry values
                if (Test-RegistryKey -Path $PersonalizationRegPath -Name "LockScreenImage") {
                    Write-Verbose -Message "Lock screen image has been previously set, backing up registry values to: $($LockScreenBackupFile)"
                    $CurrentLockScreenImage = (Get-Item -Path $PersonalizationRegPath | Get-ItemProperty).LockScreenImage
                    Update-RegistryValue -RegistryValue $CurrentLockScreenImage -File $LockScreenBackupFile -Action Backup

                    ### Do something with that picture, save it locally or copy the path into a text file for Restore mode
                }

                # Enable lock screen changing
                if (Test-RegistryKey -Path $PersonalizationRegPath -Name "NoChangingLockScreen") {
                    Write-Verbose -Message "Changing the NoChangingLockScreen registry value to FALSE"
                    Set-ItemProperty -Path $PersonalizationRegPath -Name "NoChangingLockScreen" -Value $false
                }

                # Set the custom lock screen image from the locally copied image file
                Set-ItemProperty -Path $PersonalizationRegPath -Name "LockScreenImage" -Value $LocalLockScreenImagePath -Force
                Write-Verbose -Message "Successfully set the custom lock screen image, waiting 10 seconds for changes to apply"

                # Sleep for a few seconds for winlogon to process the changes
                Start-Sleep -Seconds 10

                # Force logoff all users
                if ($PSBoundParameters["Force"]) {
                    (Get-WmiObject -Class "Win32_OperatingSystem").Win32Shutdown(4)
                }
            }
            else {
                Write-Warning -Message "Unable to locate the custom lock screen image, please ensure it's available in the same directory where the script was launched from"
            }
		}
		"Revert" {
			try {
				# Revert lock screen image values
				Update-RegistryValue -RegistryKey $PersonalizationRegPath -RegistryItem LockScreenImage -File $LockScreenBackupFile -Action Restore

                # Disable lock screen changing
                if (Test-RegistryKey -Path $PersonalizationRegPath -Name "NoChangingLockScreen") {
                    Write-Verbose -Message "Changing the NoChangingLockScreen registry value to TRUE"
                    Set-ItemProperty -Path $PersonalizationRegPath -Name "NoChangingLockScreen" -Value $true
                }

                # Sleep for a few seconds for winlogon to process the changes
                Write-Verbose -Message "Successfully reverted lock screen image, waiting 10 seconds for changes to apply"
                Start-Sleep -Seconds 10

                # Force logoff all users
                if ($PSBoundParameters["Force"]) {
                    (Get-WmiObject -Class "Win32_OperatingSystem").Win32Shutdown(4)
                }
			}
			catch [System.Exception] {
				Write-Warning -Message "$($_.Exception.Message)"
			}
		}
	}
}