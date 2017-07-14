<#
.SYNOPSIS
    Set additional update languages for Office 365 updates that are not currently supported by ConfigMgr

.DESCRIPTION
    This script will make changes to the site configuration allowing for additional update languages for Office 365 that will
    be downloaded per update, that are not currently supported by ConfigMgr.

.PARAMETER SiteServer
    Site server name with SMS Provider installed.

.PARAMETER Language
    Specify the additional languages as a string array. Pass an empty string to clear the existing additional languages.

.EXAMPLE
    # Set a couple of languages
    .\Set-CMAdditionalUpdateLanguagesForOffice365.ps1 -SiteServer CM01 -Language "sv-SE", "da-DK"

    # Clear the languages set
    .\Set-CMAdditionalUpdateLanguagesForOffice365.ps1 -SiteServer CM01 -Language ""

.NOTES
    FileName:    Set-CMAdditionalUpdateLanguagesForOffice365.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    Created:     2017-03-30
    Updated:     2017-03-30
    
    Version history:
    1.0.0 - (2017-03-30) Script created
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed.")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="Specify the additional languages as a string array. Pass an empty string to clear the existing additional languages.")]
    [ValidateNotNull()]
    [AllowEmptyString()]
    [string[]]$Language
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

    # Determine top level Site Code
    Write-Verbose -Message "Determine top level Site Code in hierarchy"
    $SiteDefinitions = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_SCI_SiteDefinition -ComputerName $SiteServer
    foreach ($SiteDefinition in $SiteDefinitions) {
        if ($SiteDefinition.ParentSiteCode -like [System.String]::Empty) {
            $TopLevelSiteCode = $SiteDefinition.SiteCode
            Write-Verbose -Message "Determined top level Site Code: $($TopLevelSiteCode)"
        }
    }

    # Join language array to string object
    $Languages = $Language -join ", "

}
Process {
    if ($TopLevelSiteCode -ne $null) {
        # Detect presence of SMS_WSUS_CONFIGURATION_MANAGER component
        $WSUSComponent = Get-CimInstance -Namespace "root\SMS\site_$($SiteCode)" -ClassName SMS_SCI_Component -ComputerName $SiteServer -Verbose:$false | Where-Object -FilterScript { ($_.SiteCode -like $TopLevelSiteCode) -and ($_.ComponentName -like "SMS_WSUS_CONFIGURATION_MANAGER") }

        if ($WSUSComponent -ne $null) {
            # Get embedded property list for SMS_WSUS_CONFIGURATION_MANAGER
            $WSUSAdditionalUpdateLanguageProperty = $WSUSComponent.Props | Where-Object -FilterScript { $_.PropertyName -like "AdditionalUpdateLanguagesForO365" }

            if ($WSUSAdditionalUpdateLanguageProperty -ne $null) {
                # Construct array index for Props property
                $PropsIndex = 0
            
                # Amend AdditionalUpdateLanguagesForO365 embedded property instance
                foreach ($EmbeddedProperty in $WSUSComponent.Props) {
                    if ($EmbeddedProperty.PropertyName -like "AdditionalUpdateLanguagesForO365") {
                        Write-Verbose -Message "Amending AdditionalUpdateLanguagesForO365 embedded property with additional languages: $($Languages)"
                        $EmbeddedProperty.Value2 = $Languages
                        $WSUSComponent.Props[$PropsIndex] = $EmbeddedProperty
                    }

                    # Increase Props index
                    $PropsIndex++
                }

                # Construct property table
                $PropsTable = @{
                    Props = $WSUSComponent.Props
                }

                # Save changes made to existing AdditionalUpdateLanguagesForO365 embedded property instance
                try {
                    Get-CimInstance -InputObject $WSUSComponent -Verbose:$false | Set-CimInstance -Property $PropsTable -Verbose:$false -ErrorAction Stop
                    Write-Verbose -Message "Successfully amended AdditionalUpdateLanguagesForO365 embedded property"
                }
                catch [System.Exception] {
                    Write-Warning -Message $_.Exception.Message ; break
                }

                # Get WSUS component again and pass embedded property to pipeline for output
                $WSUSComponent = Get-CimInstance -Namespace "root\SMS\site_$($SiteCode)" -ClassName SMS_SCI_Component -ComputerName $SiteServer -Verbose:$false | Where-Object -FilterScript { ($_.SiteCode -like $TopLevelSiteCode) -and ($_.ComponentName -like "SMS_WSUS_CONFIGURATION_MANAGER") }
                $WSUSAdditionalUpdateLanguageProperty = $WSUSComponent.Props | Where-Object -FilterScript { $_.PropertyName -like "AdditionalUpdateLanguagesForO365" }
                Write-Output -InputObject $WSUSAdditionalUpdateLanguageProperty
            }
        }
    }
    else {
        Write-Warning -Message "Unable to determine top level Site Code, bailing out"
    }
}