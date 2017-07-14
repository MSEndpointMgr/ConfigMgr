<#
.SYNOPSIS
    Import a Device into ConfigMgr 2012
.DESCRIPTION
    Import a Device into ConfigMgr 2012
.PARAMETER SiteServer
    Site server name with SMS Provider installed
.PARAMETER ComputerName
    Name of the device
.PARAMETER MACAddress
    Specify the unique MAC address for the device
.PARAMETER CollectionName
    If specified, imported device will be added to the provided collection
.EXAMPLE
    .\Import-CMDevice.ps1 -SiteServer 'CM01' -DeviceName 'CL001' -MACAddress '00:00:00:00:00:00'
.NOTES
    Script name: Import-CMDevice.ps1
    Author:      Nickolaj Andersen
    Contact:     @NickolajA
    DateCreated: 2015-11-02
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Site server where the SMS Provider is installed")]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({Test-Connection -ComputerName $_ -Count 1 -Quiet})]
    [string]$SiteServer,
    [parameter(Mandatory=$true)]
    [string]$DeviceName,
    [parameter(Mandatory=$true)]
    [ValidatePattern('^([0-9a-fA-F]{2}[:]{0,1}){5}[0-9a-fA-F]{2}$')]
    [string]$MACAddress,
    [parameter(Mandatory=$false)]
    [string]$CollectionName
)
Begin {
    # Determine SiteCode from WMI
    try {
        Write-Verbose -Message "Determining SiteCode for Site Server: '$($SiteServer)'"
        $SiteCodeObjects = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer -ErrorAction Stop
        foreach ($SiteCodeObject in $SiteCodeObjects) {
            if ($SiteCodeObject.ProviderForLocalSite -eq $true) {
                $SiteCode = $SiteCodeObject.SiteCode
                Write-Debug -Message "SiteCode: $($SiteCode)"
            }
        }
    }
    catch [System.UnauthorizedAccessException] {
        Write-Warning -Message "Access denied" ; break
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine SiteCode" ; break
    }
}
Process {
    try {
        if ($PSCmdlet.ShouldProcess($DeviceName, "ImportDevice")) {
            # Import Computer
            $WMIConnection = ([WMIClass]"\\$($SiteServer)\root\SMS\site_$($SiteCode):SMS_Site")
            $NewEntry = $WMIConnection.psbase.GetMethodParameters("ImportMachineEntry")
            $NewEntry.MACAddress = $MACAddress
            $NewEntry.NetbiosName = $DeviceName
            $NewEntry.OverwriteExistingRecord = $true
            $Resource = $WMIConnection.psbase.InvokeMethod("ImportMachineEntry", $NewEntry, $null)
            if ([int]$Resource.ReturnValue -eq 0) {
                Write-Verbose -Message "Successfully imported new device with name '$($DeviceName)'"
            }
            if ($PSBoundParameters["CollectionName"]) {
            $CollectionQuery = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "Name like '$($CollectionName)'" -ErrorAction Stop
                if ($CollectionQuery -ne $null) {
                    $Instance = ([WMIClass]"\\$($SiteServer)\root\SMS\Site_$($SiteCode):SMS_CollectionRuleDirect").CreateInstance()
                    $Instance.ResourceClassName = "SMS_R_SYSTEM"
                    $Instance.ResourceID = $Resource.ResourceID
                    $Instance.RuleName = $DeviceName
                    $Rule = $CollectionQuery.AddMemberShipRule($Instance)
                    if ([int]$Rule.ReturnValue -eq 0) {
                        Write-Verbose -Message "Successfully added '$($DeviceName)' to collection '$($CollectionName)'"
                    }
                    # Refresh All Systems collection
                    $CollectionQuery.RequestRefresh() | Out-Null
                }
            }
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "$($_.Exception.Message). Line: $($_.InvocationInfo.ScriptLineNumber)" ; break
    }
}