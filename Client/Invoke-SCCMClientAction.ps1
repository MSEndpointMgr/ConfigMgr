<#
.SYNOPSIS
    Invoke the specified SCCM client actions on the computer
.DESCRIPTION
    This script will execute the supplied SCCM client actions on the target computer
.PARAMETER Computername
    Computer name on which to run the actions
.EXAMPLE
    $Policies = 'ApplicationDeploymentEvaluationCycle', 'DiscoveryDataCollectionCycle', 'FileCollectionCycle', 'HardwareInventoryCycle', 'MachinePolicyRetrievalCycle', 'MachinePolicyEvaluationCycle', 'SoftwareInventoryCycle', 'SoftwareMeteringUsageReportCycle', 'SoftwareUpdatesAssignmentsEvaluationCycle', 'SoftwareUpdateScanCycle', 'StateMessageRefresh', 'UserPolicyRetrievalCycle', 'UserPolicyEvaluationCycle', 'WindowsInstallersSourceListUpdateCycle'
    Invoke-SCCMClientAction -computername $ENV:COMPUTERNAME -ClientAction $Policies
.NOTES
    Script name: Invoke-SCCMClientAction
    Author:      Devin Stokes
    DateCreated: 2021-12-15
#>
Function Invoke-SCCMClientAction {
    [CmdletBinding()]
            
    # Parameters used in this function
    param
    ( 
        [Parameter(Position = 0, Mandatory = $True, HelpMessage = "Provide server names", ValueFromPipeline = $true)] 
        [string[]]$Computername,

        [ValidateSet('ApplicationDeploymentEvaluationCycle',
            'DiscoveryDataCollectionCycle',
            'FileCollectionCycle',
            'HardwareInventoryCycle',
            'MachinePolicyRetrievalCycle',
            'MachinePolicyEvaluationCycle',
            'SoftwareInventoryCycle',
            'SoftwareMeteringUsageReportCycle',
            'SoftwareUpdatesAssignmentsEvaluationCycle',
            'SoftwareUpdateScanCycle',
            'StateMessageRefresh',
            'UserPolicyRetrievalCycle',
            'UserPolicyEvaluationCycle',
            'WindowsInstallersSourceListUpdateCycle')] 
        [string[]]$ClientAction

    ) 
    $ActionResults = @()
    Try { 
        $ActionResults = Invoke-Command -ComputerName $Computername { param([array]$ClientAction)
            "Executing $($ClientAction.Length) actions on $env:COMPUTERNAME..." | Out-Host

            Foreach ($Item in $ClientAction) {
                $Object = @{} | select "Action name", Status
                Try {
                    $ScheduleIDMappings = @{ 
                        'ApplicationDeploymentEvaluationCycle'      =	"{00000000-0000-0000-0000-000000000121}";
                        'DiscoveryDataCollectionCycle'              =	"{00000000-0000-0000-0000-000000000003'}";
                        'FileCollectionCycle'                       =	"{00000000-0000-0000-0000-000000000010}";
                        'HardwareInventoryCycle'                    = "{00000000-0000-0000-0000-000000000001'}";
                        'MachinePolicyRetrievalCycle'               = "{00000000-0000-0000-0000-000000000021}";
                        'MachinePolicyEvaluationCycle'              = "{00000000-0000-0000-0000-000000000022}";
                        'SoftwareInventoryCycle'                    = "{00000000-0000-0000-0000-000000000002}";
                        'SoftwareMeteringUsageReportCycle'          = "{00000000-0000-0000-0000-000000000031}";
                        'SoftwareUpdatesAssignmentsEvaluationCycle'	= "{00000000-0000-0000-0000-000000000108}";
                        'SoftwareUpdateScanCycle'                   = "{00000000-0000-0000-0000-000000000113}";
                        'StateMessageRefresh'                       = "{00000000-0000-0000-0000-000000000111}";
                        'UserPolicyRetrievalCycle'                  = "{00000000-0000-0000-0000-000000000026}";
                        'UserPolicyEvaluationCycle'                 = "{00000000-0000-0000-0000-000000000027}";
                        'WindowsInstallersSourceListUpdateCycle'    = "{00000000-0000-0000-0000-000000000032}"
                    }
                    $ScheduleID = $ScheduleIDMappings[$item]
                    Write-Verbose "Processing $Item - $ScheduleID"
                    [void]([wmiclass] "root\ccm:SMS_Client").TriggerSchedule($ScheduleID);
                    $Status = "Success"
                    Write-Verbose "Operation status - $status"
                }
                Catch {
                    $Status = "Failed"
                    Write-Verbose "Operation status - $status"
                }
                $Object."Action name" = $item
                $Object.Status = $Status
                $Object
            }

        } -ArgumentList (, $ClientAction) -ErrorAction Stop | Select-Object @{n = 'ServerName'; e = { $_.pscomputername } }, "Action name", Status
    }  
    Catch {
        Write-Error $_.Exception.Message 
    }   
    Return $ActionResults           
}       

