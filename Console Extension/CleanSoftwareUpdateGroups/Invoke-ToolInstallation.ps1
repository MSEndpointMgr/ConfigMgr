<#
.Synopsis
   Installs or uninstalls the Clean Software Update Groups console extension for ConfigMgr.
.DESCRIPTION
   Configures settings for and installs a console extension to remove expired and superseded 
   updates from software update groups in ConfigMgr.
.PARAMETER SiteServer
   Specifies the name of the Site Server where the SMS Provider is installed.
.PARAMETER Method
   Runs the script in either 'Install' or 'Uninstall' mode.
.PARAMETER Path
    Sets the path where the Clean Software Update Groups script file will be stored. This path must 
    already exist, the script will not create the path if it is not found.
.EXAMPLE
    PS > Invoke-ToolInstallation.ps1 -SiteServer CM01.contoso.com -Method Install -Path C:\Scripts -Verbose
    VERBOSE: ConfigMgr console environment variable detected: C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\i386
    VERBOSE: Creating folder: 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\XmlStorage\Extensions\Actions\23e7a3fe-b0f0-4b24-813a-dc425239f9a2'
    VERBOSE: Editing 'CleanSoftwareUpdateGroups.xml' to contain the correct path to script file
    VERBOSE: Copying 'CleanSoftwareUpdateGroups.xml' to Software Update Groups node action folder
    VERBOSE: Copying 'Clean-CMSoftwareUpdateGroups.ps1' to: 'C:\Scripts'
.EXAMPLE
    PS > Invoke-ToolInstallation.ps1 -SiteServer CM01.contoso.com -Method Uninstall -Path C:\Scripts -Verbose
    VERBOSE: ConfigMgr console environment variable detected: C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\i386
    VERBOSE: Found folder: 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\XmlStorage\Extensions\Actions\23e7a3fe-b0f0-4b24-813a-dc425239f9a2'
    VERBOSE: Removing 'CleanSoftwareUpdateGroups.xml' from Software Update Groups node action folder
    VERBOSE: Removing 'Clean-CMSoftwareUpdateGroups.ps1' from 'C:\Scripts'
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify installation method")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet("Install","Uninstall")]
    [string]$Method,

    [parameter(Mandatory=$true, HelpMessage="Specify a valid path to where the Clean Software Update Groups script file will be stored")]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern("^[A-Za-z]{1}:\\\w+")]
    [ValidateScript({
        # Check if path contains any invalid characters
        if ((Split-Path -Path $_ -Leaf).IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw "$(Split-Path -Path $_ -Leaf) contains invalid characters"
        }
        else {
            # Check if the whole path exists
            if (Test-Path -Path $_ -PathType Container) {
                    return $true
            }
            else {
                throw "Unable to locate part of or the whole specified path, specify a valid path"
            }
        }
    })]
    [string]$Path
)
Begin {
    # Validate that the script is being executed elevated
    try {
        $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $WindowsPrincipal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $CurrentIdentity
        if (-not($WindowsPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
            Write-Warning -Message "Script was not executed elevated, please re-launch." ; break
        }
    } 
    catch {
        Write-Warning -Message $_.Exception.Message ; break
    }
    # Determine PSScriptRoot
    $ScriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
    # Validate ConfigMgr console presence
    if ($env:SMS_ADMIN_UI_PATH -ne $null) {
        try {
            if (Test-Path -Path $env:SMS_ADMIN_UI_PATH -PathType Container -ErrorAction Stop) {
                Write-Verbose -Message "ConfigMgr console environment variable detected: $($env:SMS_ADMIN_UI_PATH)"
            }
        }
        catch [Exception] {
            Write-Warning -Message $_.Exception.Message ; break
        }
    }
    else {
        Write-Warning -Message "ConfigMgr console environment variable was not detected" ; break
    }
    # Define installation file variables
    $XMLFile = "CleanSoftwareUpdateGroups.xml"
    $ScriptFile = "Clean-CMSoftwareUpdateGroups.ps1"
    # Define node folders
    $Node = "23e7a3fe-b0f0-4b24-813a-dc425239f9a2"
    # Validate if required files are present in the script root directory
    if (-not(Test-Path -Path (Join-Path -Path $ScriptRoot -ChildPath $XMLFile) -PathType Leaf -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "Unable to determine location for '$($XMLFile)'. Make sure it's present in '$($ScriptRoot)'." ; break
    }
    if (-not(Test-Path -Path (Join-Path -Path $ScriptRoot -ChildPath $ScriptFile) -PathType Leaf -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "Unable to determine location for '$($ScriptFile)'. Make sure it's present in '$($ScriptRoot)'." ; break
    }
    # Determine Admin console root
    $AdminConsoleRoot = ($env:SMS_ADMIN_UI_PATH).Substring(0,$env:SMS_ADMIN_UI_PATH.Length-9)
    # Create Action folders if not exists
    $FolderList = New-Object -TypeName System.Collections.ArrayList
    $FolderList.AddRange(@(
        (Join-Path -Path $AdminConsoleRoot -ChildPath "XmlStorage\Extensions\Actions\$($Node)")
    )) | Out-Null
    foreach ($CurrentNode in $FolderList) {
        if (-not(Test-Path -Path $CurrentNode -PathType Container)) {
            Write-Verbose -Message "Creating folder: '$($CurrentNode)'"
            New-Item -Path $CurrentNode -ItemType Directory -Force | Out-Null
        }
        else {
            Write-Verbose -Message "Found folder: '$($CurrentNode)'"
        }
    }
}
Process {
    switch ($Method) {
        "Install" {
            # Edit XML files to contain correct path to script file
            if (Test-Path -Path (Join-Path -Path $ScriptRoot -ChildPath $XMLFile) -PathType Leaf -ErrorAction SilentlyContinue) {
                Write-Verbose -Message "Editing '$($XMLFile)' to contain the correct path to script file"
                $XMLDataFilePath = Join-Path -Path $ScriptRoot -ChildPath $XMLFile
                [xml]$XMLDataFile = Get-Content -Path $XMLDataFilePath
                $XMLDataFile.ActionDescription.ActionGroups.ActionDescription.Executable | Where-Object { $_.FilePath -like "*powershell.exe*" } | ForEach-Object {
                    $_.Parameters = $_.Parameters.Replace("#PATH#","'$($Path)\$($ScriptFile)'").Replace("'",'"').Replace("#SERVER#","$($SiteServer)")
                }
                $XMLDataFile.Save($XMLDataFilePath)
            }
            else {
                Write-Warning -Message "Unable to load '$($XMLFile)' from '$($Path)'. Make sure the file is located in the same folder as the installation script." ; break
            }
            # Copy XML to Software Update Groups node
            Write-Verbose -Message "Copying '$($XMLFile)' to Software Update Groups node action folder"
            $XMLStorageSUGArgs = @{
                Path = Join-Path -Path $ScriptRoot -ChildPath $XMLFile
                Destination = Join-Path -Path $AdminConsoleRoot -ChildPath "XmlStorage\Extensions\Actions\$($Node)\$($XMLFile)"
                Force = $true
            }
            Copy-Item @XMLStorageSUGArgs
            # Copy script file to specified path
            Write-Verbose -Message "Copying '$($ScriptFile)' to: '$($Path)'"
            $ScriptFileArgs = @{
                Path = Join-Path -Path $ScriptRoot -ChildPath $ScriptFile
                Destination = Join-Path -Path $Path -ChildPath $ScriptFile
                Force = $true
            }
            Copy-Item @ScriptFileArgs
        }
        "Uninstall" {
            # Remove XML file from Software Update Groups node
            Write-Verbose -Message "Removing '$($XMLFile)' from Software Update Groups node action folder"
            $XMLStorageSUGArgs = @{
                Path = Join-Path -Path $AdminConsoleRoot -ChildPath "XmlStorage\Extensions\Actions\$($Node)\$($XMLFile)"
                Force = $true
                ErrorAction = "SilentlyContinue"
            }
            if (Test-Path -Path (Join-Path -Path $AdminConsoleRoot -ChildPath "XmlStorage\Extensions\Actions\$($Node)\$($XMLFile)")) {
                Remove-Item @XMLStorageSUGArgs
            }
            else {
                Write-Warning -Message "Unable to locate '$(Join-Path -Path $AdminConsoleRoot -ChildPath "XmlStorage\Extensions\Actions\$($Node)\$($XMLFile)")'"
            }
            # Remove script file from specified path
            Write-Verbose -Message "Removing '$($ScriptFile)' from '$($Path)'"
            $ScriptFileArgs = @{
                Path = Join-Path -Path $Path -ChildPath $ScriptFile
                Force = $true
            }
            if (Test-Path -Path (Join-Path -Path $Path -ChildPath $ScriptFile)) {
                Remove-Item @ScriptFileArgs
            }
            else {
                Write-Warning -Message "Unable to locate '$(Join-Path -Path $Path -ChildPath $ScriptFile)'"
            }
        }
    }
}

