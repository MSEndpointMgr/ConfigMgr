# Define the name of the update channel
$UpdateChannelName = "Broad" # Valid options are: Monthly, Targeted, Broad and Insiders

switch ($UpdateChannelName) {
    "Monthly" {
        $UpdateChannel = "http://officecdn.microsoft.com/pr/492350f6-3a01-4f97-b9c0-c7c6ddf67d60"
    }
    "Targeted" {
        $UpdateChannel = "http://officecdn.microsoft.com/pr/b8f9b850-328d-4355-9145-c59439a0c4cf"
    }
    "Broad" {
        $UpdateChannel = "http://officecdn.microsoft.com/pr/7ffbc6bf-bc32-4f92-8982-f9dd17fd3114"
    }
    "Insiders" {
        $UpdateChannel = "http://officecdn.microsoft.com/pr/64256afe-f5d9-4f86-8936-8840a6a4f5be"
    }
}

# Change update channel if existing does not match desired update channel
Write-Output -InputObject "Chosen update channel '$($UpdateChannelName)' translated to: $($UpdateChannel)"
$OfficeC2RClientPath = Join-Path -Path $env:CommonProgramW6432 -ChildPath "Microsoft Shared\ClickToRun\OfficeC2RClient.exe"
$C2RConfiguration = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
$CurrentUpdateChannel = Get-ItemProperty -Path $C2RConfiguration | Select-Object -ExpandProperty CDNBaseUrl
if ($CurrentUpdateChannel -notlike $UpdateChannel) {
    Write-Output -InputObject "Current update channel does not match specified update channel, calling procedure to change update channel"
    
    # Update registy configuration for new update channel
    Set-ItemProperty -Path $C2RConfiguration -Name "UpdateChannel" -Value $UpdateChannel -Force
    Write-Output -InputObject "Updated registry configuration with new update channel data endpoint"

    # Call OfficeC2RClient.exe and change the update channel
    $OfficeC2RClientParameters = "/changesetting channel=$($UpdateChannelName)"
    Write-Output -InputObject "Calling OfficeC2RClient.exe with the following parameters: $($OfficeC2RClientParameters)"
    Start-Process -FilePath $OfficeC2RClientPath -ArgumentList $OfficeC2RClientParameters -Wait

    # Call OfficeC2RClient.exe and update Office applications
    $OfficeC2RClientParameters = "/update user updateprompt=false forceappshutdown=true displaylevel=true"
    Write-Output -InputObject "Calling OfficeC2RClient.exe with the following parameters: $($OfficeC2RClientParameters)"
    Start-Process -FilePath $OfficeC2RClientPath -ArgumentList $OfficeC2RClientParameters

    # Trigger hardware inventory
    Invoke-WmiMethod -Namespace "root\ccm" -Class "SMS_Client" -Name "TriggerSchedule" -ArgumentList "{00000000-0000-0000-0000-000000000001}"
}
else {
    Write-Output -InputObject "Current update channel matches specified update channel, will not attempt to change update channel"
}