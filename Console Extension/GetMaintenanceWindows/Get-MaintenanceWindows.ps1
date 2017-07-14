[CmdletBinding()]
param(
[parameter(Mandatory=$true)]
$SiteServer,
[parameter(Mandatory=$true)]
$SiteCode,
[parameter(Mandatory=$true)]
$ResourceID
)

function Load-Form {
    $Form.Controls.Add($DGVResults1)
    $Form.Controls.Add($DGVResults2)
    $Form.Controls.Add($GBMW)
    $Form.Controls.Add($GBMWUpcoming)
    $Form.Add_Shown({Get-CMMaintenanceWindowsInformation})
	$Form.Add_Shown({$Form.Activate()})
	[void]$Form.ShowDialog()
}

function Get-CMSiteCode {
    $CMSiteCode = Get-WmiObject -Namespace "root\SMS" -Class SMS_ProviderLocation -ComputerName $SiteServer | Select-Object -ExpandProperty SiteCode
    return $CMSiteCode
}

function Get-CMSchedule {
    param(
    $String
    )
    $WMIConnection = [WmiClass]"\\$($SiteServer)\root\SMS\site_$(Get-CMSiteCode):SMS_ScheduleMethods"
    $Schedule = $WMIConnection.psbase.GetMethodParameters("ReadFromString")
    $Schedule.StringData = $String
    $ScheduleData = $WMIConnection.psbase.InvokeMethod("ReadFromString",$Schedule,$null)
    $ScheduleInfo = $ScheduleData.TokenData
    return $ScheduleInfo
}

function Get-CMMaintenanceWindowsInformation {
    $CMSiteCode = Get-CMSiteCode
    $CurrentDateTime = (Get-Date)
    $AllMWDates = @()
    $DateArray = @()
    $CollectionIDs = Get-WmiObject -Namespace "root\SMS\site_$($CMSiteCode)" -Class SMS_FullCollectionMembership -ComputerName $SiteServer -Filter "ResourceID like '$($ResourceID)'"
    foreach ($CollectionID in $CollectionIDs) {
        $CollectionSettings = Get-WmiObject -Namespace "root\SMS\site_$($CMSiteCode)" -Class SMS_CollectionSettings -ComputerName $SiteServer -Filter "CollectionID='$($CollectionID.CollectionID)'"
        foreach ($CollectionSetting in $CollectionSettings) {
            $CollectionSetting.Get()
            foreach ($MaintenanceWindow in $CollectionSetting.ServiceWindows) {
                $StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($MaintenanceWindow.StartTime)
                $DateArray += $MaintenanceWindow
                $CollectionName = Get-WmiObject -Namespace "root\SMS\site_$($CMSiteCode)" -Class SMS_Collection -ComputerName $SiteServer -Filter "CollectionID = '$($CollectionID.CollectionID)'" | Select-Object -ExpandProperty Name
                $DGVResults1.Rows.Add($MaintenanceWindow.Name,$CollectionName) | Out-Null
            }
        }
    }
    $SortedDateArray = $DateArray | Sort-Object -Property RecurrenceType | Select-Object Description, RecurrenceType, ServiceWindowSchedules, isEnabled
    $RecurrenceType1 = ($SortedDateArray | Where-Object { $_.RecurrenceType -eq 1 })
    if ($RecurrenceType1 -ne $null) {
        foreach ($R1RecurrenceType in $RecurrenceType1) {
            if ($R1RecurrenceType.IsEnabled -eq $true) {
                $R1Schedule = Get-CMSchedule -String $R1RecurrenceType.ServiceWindowSchedules
                $R1StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($R1Schedule.StartTime)
                if ((Get-Date) -le $R1StartTime) {
                    $AllMWDates += $R1StartTime
                }
            }
        }
    }
    $RecurrenceType2 = ($SortedDateArray | Where-Object { $_.RecurrenceType -eq 2 })
    if ($RecurrenceType2 -ne $null) {
        foreach ($R2RecurrenceType in $RecurrenceType2) {
            if ($R2RecurrenceType.IsEnabled -eq $true) {
                $R2Schedule = Get-CMSchedule -String $R2RecurrenceType.ServiceWindowSchedules
                $R2StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($R2Schedule.StartTime)
                $R2DaySpan = $R2Schedule.DaySpan
                $R2CurrentDate = (Get-Date)
                do {
                    $R2StartTime = $R2StartTime.AddDays($R2DaySpan)
                }
                until ($R2StartTime -ge $R2CurrentDate)
                if ((Get-Date) -le $R2StartTime) {
                    $AllMWDates += $R2StartTime
                }
            }
        }
    }
    $RecurrenceType3 = ($SortedDateArray | Where-Object { $_.RecurrenceType -eq 3 })
    if ($RecurrenceType3 -ne $null) {
        foreach ($R3RecurrenceType in $RecurrenceType3) {
            if ($R3RecurrenceType.IsEnabled -eq $true) {
                $R3Schedule = Get-CMSchedule -String $R3RecurrenceType.ServiceWindowSchedules
                $R3StartMin = [Management.ManagementDateTimeConverter]::ToDateTime($R3Schedule.StartTime) | Select-Object -ExpandProperty Minute
                $R3StartHour = [Management.ManagementDateTimeConverter]::ToDateTime($R3Schedule.StartTime) | Select-Object -ExpandProperty Hour
                $R3StartDay = $R3Schedule.Day
                switch ($R3StartDay) {
                    1 { $R3DayOfWeek = "Sunday" }
                    2 { $R3DayOfWeek = "Monday" }
                    3 { $R3DayOfWeek = "Tuesday" }
                    4 { $R3DayOfWeek = "Wednesday" }
                    5 { $R3DayOfWeek = "Thursday" }
                    6 { $R3DayOfWeek = "Friday" }
                    7 { $R3DayOfWeek = "Saturday" }
                }
                $R3WeekSpan = $R3Schedule.ForNumberOfWeeks
                switch ($R3WeekSpan) {
                    1 { $R3AddDays = 0 }
                    2 { $R3AddDays = 7 }
                    3 { $R3AddDays = 14 }
                    4 { $R3AddDays = 21 }
                }
                $R3CurrentDate = (Get-Date)
                $R3DaysUntil = 0
                While ($R3CurrentDate.DayOfWeek -ne "$($R3DayOfWeek)") {
                    $R3DaysUntil++
                    $R3CurrentDate = $R3CurrentDate.AddDays(1)
                }
                if ($R3StartHour -le 9) {
                    if ($R3StartMin -le 9) {
                        $R3DateTime = ([datetime]::ParseExact("0$($R3StartHour):0$($R3StartMin)","hh:mm",$null)).AddDays($R3DaysUntil).AddDays($R3AddDays)
                    }
                    elseif ($R3StartMin -ge 10) {
                        $R3DateTime = ([datetime]::ParseExact("0$($R3StartHour):$($R3StartMin)","hh:mm",$null)).AddDays($R3DaysUntil).AddDays($R3AddDays)
                    }
                }
                elseif ($R3StartHour -ge 10) {
                    if ($R3StartMin -le 9) {
                        $R3DateTime = ([datetime]::ParseExact("$($R3StartHour):0$($R3StartMin)","hh:mm",$null)).AddDays($R3DaysUntil).AddDays($R3AddDays)
                    }
                    elseif ($R3StartMin -ge 10) {
                        $R3DateTime = ([datetime]::ParseExact("$($R3StartHour):$($R3StartMin)","hh:mm",$null)).AddDays($R3DaysUntil).AddDays($R3AddDays)
                    }
                }
                if ((Get-Date) -le $R3DateTime) {
                    $AllMWDates += $R3DateTime
                }
            }
        }
    }
    $RecurrenceType4 = ($SortedDateArray | Where-Object { $_.RecurrenceType -eq 4 })
    if ($RecurrenceType4 -ne $null) {
        foreach ($R4RecurrenceType in $RecurrenceType4) {
            if ($R4RecurrenceType.IsEnabled -eq $true) {
                $R4Schedule = Get-CMSchedule -String $R4RecurrenceType.ServiceWindowSchedules
                $R4WeekOrder = $R4Schedule.WeekOrder
                $R4StartHour = [Management.ManagementDateTimeConverter]::ToDateTime($R4Schedule.StartTime) | Select-Object -ExpandProperty Hour
                $R4StartMin = [Management.ManagementDateTimeConverter]::ToDateTime($R4Schedule.StartTime) | Select-Object -ExpandProperty Minute
                $R4StartSec = [Management.ManagementDateTimeConverter]::ToDateTime($R4Schedule.StartTime) | Select-Object -ExpandProperty Second
                $R4WeekDay = $R4Schedule.Day
                switch ($R4WeekDay) {
                    1 { $R4DayOfWeek = "Sunday" }
                    2 { $R4DayOfWeek = "Monday" }
                    3 { $R4DayOfWeek = "Tuesday" }
                    4 { $R4DayOfWeek = "Wednesday" }
                    5 { $R4DayOfWeek = "Thursday" }
                    6 { $R4DayOfWeek = "Friday" }
                    7 { $R4DayOfWeek = "Saturday" }
                }
                if ($R4WeekOrder -ge 1) {
                    $R4Increment = 0
                    $R4Date = (Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1 -Hour $($R4StartHour) -Minute $($R4StartMin) -Second $($R4StartSec))
                    do {
                        $R4Increment++
                        $R4CalcDate = $R4Date.AddDays($R4Increment)
                        $R4CalcDayofWeek = $R4CalcDate.DayOfWeek
                    }
                    until ($R4CalcDayofWeek -like $R4DayOfWeek)
                    $R4CalcDateTime = $R4CalcDate
                    if ($R4WeekOrder -eq 1) {
                        $R4DateTime = $R4CalcDateTime
                    }
                    elseif ($R4WeekOrder -eq 2) {
                        $R4DateTime = $R4CalcDateTime.AddDays(7)
                    }
                    elseif ($R4WeekOrder -eq 3) {
                        $R4DateTime = $R4CalcDateTime.AddDays(14)
                    }
                    elseif ($R4WeekOrder -eq 4) {
                        $R4DateTime = $R4CalcDateTime.AddDays(21)
                    }
                }
                elseif ($R4WeekOrder -eq 0) {
                    $R4Decrement = 0
                    $R4Date = (Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1 -Hour $($R4StartHour) -Minute $($R4StartMin) -Second $($R4StartSec)).AddMonths(1)
                    do {
                        $R4Decrement++
                        $R4CalcDate = $R4Date.AddDays(-$R4Decrement)
                        $R4CalcDayofWeek = $R4CalcDate.DayOfWeek
                    }
                    until ($R4CalcDayofWeek -like $R4DayOfWeek)
                    $R4DateTime = $R4CalcDate
                }
                if ((Get-Date) -le $R4DateTime) {
                    $AllMWDates += $R4DateTime
                }
            }
        }
    }
    $RecurrenceType5 = ($SortedDateArray | Where-Object { $_.RecurrenceType -eq 5 })
    if ($RecurrenceType5 -ne $null) {
        foreach ($R5RecurrenceType in $RecurrenceType5) {
            if ($R5RecurrenceType.IsEnabled -eq $true) {
                $R5Schedule = Get-CMSchedule -String $R5RecurrenceType.ServiceWindowSchedules
                $R5StartTime = [Management.ManagementDateTimeConverter]::ToDateTime($R5Schedule.StartTime)
                $R5StartHour = $R5StartTime.Hour
                $R5StartMin = $R5StartTime.Minute
                $R5StartSec = $R5StartTime.Second
                $R5MonthSpan = $R5Schedule.ForNumberOfMonths
                $R5MonthDay = $R5Schedule.MonthDay
                if ($R5Schedule.MonthDay -ge 1) {
                    if ($R5MonthSpan -eq 1) {
                        $R5DateTime = ((Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day $($R5MonthDay) -Hour $($R5StartHour) -Minute $($R5StartMin) -Second $($R5StartSec))).DateTime
                    }
                    elseif ($R5MonthSpan -gt 1) {
                        $R5DateTime = ((Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day $($R5MonthDay) -Hour $($R5StartHour) -Minute $($R5StartMin) -Second $($R5StartSec)).AddMonths($R5MonthSpan)).DateTime
                    }
                }
                elseif ($R5Schedule.MonthDay -eq 0) {
                    $R5DateTime = ((Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1 -Hour $($R5StartHour) -Minute $($R5StartMin) -Second $($R5StartSec)).AddMonths($R5MonthSpan).AddDays(-1)).DateTime
                }
                if ((Get-Date) -le $R5DateTime) {
                    $AllMWDates += $R5DateTime
                }
            }
        }
    }
    $SortedDates = $AllMWDates | Sort-Object
    $SortedDates | ForEach-Object {
        $DGVResults2.Rows.Add($_)
    }
}

# Assemblies
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

# Form
$Form = New-Object System.Windows.Forms.Form    
$Form.Size = New-Object System.Drawing.Size(700,470)  
$Form.MinimumSize = New-Object System.Drawing.Size(700,470)
$Form.MaximumSize = New-Object System.Drawing.Size(700,470)
$Form.SizeGripStyle = "Hide"
$Form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($PSHome + "\powershell.exe")
$Form.Text = "Maintenance Window Tool 1.0"
$Form.ControlBox = $true
$Form.TopMost = $true

# DataGriView
$DGVResults1 = New-Object System.Windows.Forms.DataGridView
$DGVResults1.Location = New-Object System.Drawing.Size(20,30)
$DGVResults1.Size = New-Object System.Drawing.Size(640,170)
$DGVResults1.ColumnCount = 2
$DGVResults1.ColumnHeadersVisible = $true
$DGVResults1.Columns[0].Name = "Maintenance Window Name"
$DGVResults1.Columns[0].AutoSizeMode = "Fill"
$DGVResults1.Columns[1].Name = "Collection Name"
$DGVResults1.Columns[1].AutoSizeMode = "Fill"
$DGVResults1.AllowUserToAddRows = $false
$DGVResults1.AllowUserToDeleteRows = $false
$DGVResults1.ReadOnly = $True
$DGVResults1.ColumnHeadersHeightSizeMode = "DisableResizing"
$DGVResults1.RowHeadersWidthSizeMode = "DisableResizing"
$DGVResults2 = New-Object System.Windows.Forms.DataGridView
$DGVResults2.Location = New-Object System.Drawing.Size(20,240)
$DGVResults2.Size = New-Object System.Drawing.Size(640,170)
$DGVResults2.ColumnCount = 1
$DGVResults2.ColumnHeadersVisible = $true
$DGVResults2.Columns[0].Name = "Upcoming Maintenance Windows"
$DGVResults2.Columns[0].AutoSizeMode = "Fill"
$DGVResults2.AllowUserToAddRows = $false
$DGVResults2.AllowUserToDeleteRows = $false
$DGVResults2.ReadOnly = $True
$DGVResults2.ColumnHeadersHeightSizeMode = "DisableResizing"
$DGVResults2.RowHeadersWidthSizeMode = "DisableResizing"

# Groupbox
$GBMW = New-Object System.Windows.Forms.GroupBox
$GBMW.Location = New-Object System.Drawing.Size(10,10) 
$GBMW.Size = New-Object System.Drawing.Size(660,200) 
$GBMW.Text = "Maintenance Windows"
$GBMWUpcoming = New-Object System.Windows.Forms.GroupBox
$GBMWUpcoming.Location = New-Object System.Drawing.Size(10,220) 
$GBMWUpcoming.Size = New-Object System.Drawing.Size(660,200) 
$GBMWUpcoming.Text = "Upcoming Maintenance Windows"

# Load form
Load-Form