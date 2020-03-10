[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [parameter(Mandatory = $true, ParameterSetName = "Single")]
    [parameter(ParameterSetName = "Recurse")]
    [string]$SiteServer,
    [parameter(Mandatory = $false, ParameterSetName = "Single")]
    $ApplicationName,
    [parameter(Mandatory = $true, ParameterSetName = "Single")]
    [parameter(ParameterSetName = "Recurse")]
    [string]$Locate,
    [parameter(Mandatory = $true, ParameterSetName = "Single")]
    [parameter(ParameterSetName = "Recurse")]
    [string]$Replace,
    [parameter(Mandatory = $false, ParameterSetName = "Recurse")]
    [switch]$Recurse,
    [parameter(Mandatory = $false, ParameterSetName = "Single")]
    [parameter(ParameterSetName = "Recurse")]
    [switch]$Copy
)

Begin {
    try {
        # Determine SiteCode
        Write-Verbose "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Debug "SiteCode: $($SideCode)"
            }
        }
    }
    catch [Exception] {
        Throw "Unable to determine SiteCode"
    }
    try {
        # Load assemblies
        Write-Verbose "Trying to load necessary assemblies"
        [System.Reflection.Assembly]::LoadFrom((Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.dll")) | Out-Null
        [System.Reflection.Assembly]::LoadFrom((Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll")) | Out-Null
        [System.Reflection.Assembly]::LoadFrom((Join-Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll")) | Out-Null
    }
    catch [Exception] {
        Throw $_.Exception.Message
    }
}

Process {
    function Rename-ApplicationSource {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [parameter(Mandatory = $true)]
            $AppName
        )
        $AppName | ForEach-Object {
            $LocalizedDisplayName = $_.LocalizedDisplayName
            $CurrentApplication = [wmi]$_.__PATH
            # Deserialize SDMPakageXML property from string
            $ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($CurrentApplication.SDMPackageXML, $True)

            foreach ($DeploymentType in $ApplicationXML.DeploymentTypes) {
                $Installer = $DeploymentType.Installer
                $CurrentContentLocation = $DeploymentType.Installer.Contents[0].Location.TrimEnd("\")
                $ContentLocation = $CurrentContentLocation -replace "$($Locate)", "$($Replace)"
                if ($CurrentContentLocation -match $Locate) {
                    try {
                        # If Copy parameter is specified, copy source content to destination
                        if ($Copy) {
                            Write-Verbose "Initiating copy operation"
                            if ($PSCmdlet.ShouldProcess("From: $($CurrentContentLocation)", "Copy files")) {
                                Write-Verbose "Copy destination: $($ContentLocation)"
                                if (-not(Test-Path -Path $ContentLocation)) {
                                    New-Item -Path $ContentLocation -ItemType Directory | Out-Null
                                    if ((Get-ChildItem -Path $ContentLocation | Measure-Object).Count -eq 0) {
                                        Write-Verbose "Copy source: `n$($CurrentContentLocation)"
                                        $SourceChildItems = Get-ChildItem -Path $CurrentContentLocation
                                        foreach ($SourceChildItem in $SourceChildItems) {
                                            Copy-Item -Path $SourceChildItem.FullName -Destination $ContentLocation -Force -Recurse -Verbose:($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    catch [Exception] {
                        Throw $_.Exception.Message
                    }

                    # Update the content source location
                    if ($PSCmdlet.ShouldProcess("Application: $($LocalizedDisplayName)", "Amend content source path")) {
                        if ($CurrentContentLocation -ne $ContentLocation) {
                            Write-Verbose "Current content source path: `n $($CurrentContentLocation)"
                            $UpdateContent = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentImporter]::CreateContentFromFolder($ContentLocation)
                            $UpdateContent.FallbackToUnprotectedDP = $True
                            $UpdateContent.OnFastNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::Download
                            $UpdateContent.OnSlowNetwork = [Microsoft.ConfigurationManagement.ApplicationManagement.ContentHandlingMode]::DoNothing
                            $UpdateContent.PeerCache = $False
                            $UpdateContent.PinOnClient = $False
                            $Installer.Contents[0].ID = $UpdateContent.ID
                            $Installer.Contents[0] = $UpdateContent
                            # Serialize $ApplicationXML object back to a string and store it in $UpdatedXML
                            $UpdatedXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($ApplicationXML, $True)
                            $CurrentApplication.SDMPackageXML = $UpdatedXML
                            $CurrentApplication.Put() | Out-Null
                            Write-Verbose "New content source path: `n $($ContentLocation)"
                        }
                        elseif ($CurrentContentLocation -eq $ContentLocation) {
                            Write-Warning "The current content location path matches the new location, will not update the path for '$($LocalizedDisplayName)'."
                        }
                    }
                }
                else {
                    Write-Warning "The search term '$($Locate)' for application '$($LocalizedDisplayName)' could not be matched in the content source location '$($CurrentContentLocation)'."
                }
            }
        }
    }

    if (($PSBoundParameters["Recurse"]) -and (-not($PSBoundParameters["ApplicationName"])) -and ($ApplicationName.Length -eq 0)) {
        $ApplicationName = New-Object -TypeName System.Collections.ArrayList
        $GetApplications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_Application" -Filter "IsLatest = '$True'" -ComputerName $SiteServer ## Baard
        $GetApplications | ForEach-Object {
            $ApplicationName.Add($_) | Out-Null
        }
        Rename-ApplicationSource -AppName $ApplicationName -Verbose
    }
    elseif (($PSBoundParameters["Recurse"]) -and ($PSBoundParameters["ApplicationName"])) {
        Write-Warning "You cannot specify the 'ApplicationName' and 'Recurse' parameters at the same time"
    }
    if ((-not($PSBoundParameters["Recurse"])) -and ($PSBoundParameters["ApplicationName"]) -and ($ApplicationName.Length -ge 1)) {
        $GetApplicationName = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_ApplicationLatest" -Filter "LocalizedDisplayName like '%$($ApplicationName)%'" -ComputerName $SiteServer ## Baard
        Rename-ApplicationSource -AppName $GetApplicationName -Verbose
    }
}

# & .\Update-CMApplicationSource.ps1 -SiteServer Oslmgt09 -Locate oslmgt02 -Replace Oslmgt09 -ApplicationName "AlternaTIFF x86" -Copy -Verbose
# & .\Update-CMApplicationSource.ps1 -SiteServer Oslmgt09 -Locate oslmgt02 -Replace Oslmgt09 -Copy -Recurse -Verbose
