[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [parameter(Mandatory=$true, HelpMessage="Name of the Site server with the SMS Provider")]
    [ValidateNotNullOrEmpty()]
    [string]$SiteServer,

    [parameter(Mandatory=$true, HelpMessage="API key provided by Dell")]
    [ValidateNotNullOrEmpty()]
    [string]$APIKey,

    [parameter(Mandatory=$true, HelpMessage="Name of the device warranty")]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceName,

    [parameter(Mandatory=$true, HelpMessage="ResourceID for device")]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceID
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
        Write-Warning -Message "Access denied" ; exit
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to determine Site Code" ; exit
    }

    # Create a global sync hash table
    $Global:SyncHash = [System.Collections.Hashtable]::Synchronized(@{})
    $SyncHash.Host = $Host
    $SyncHash.OnClose = $false
    $SyncHash.ScriptRoot = $PSScriptRoot   

    # Add custom properties to the sync hash table
    $SyncHash.DeviceName = $DeviceName
    $SyncHash.APIKey = $APIKey
    $SyncHash.ResourceID = $ResourceID
    $SyncHash.ServiceTag = [System.String]::Empty
    $SyncHash.Model = [System.String]::Empty
    $SyncHash.SandboxMode = $false
    $SyncHash.ProgressBarMode = $false
    $SyncHash.ObservableCollection = New-Object -TypeName System.Collections.ObjectModel.ObservableCollection[Object]
    $SyncHash.MessageBoxText = [System.String]::Empty
    $SyncHash.MessageBoxHeader = [System.String]::Empty
    $SyncHash.InvokeMessageBox = $false

    # Create runspace
    $Runspace = [RunspaceFactory]::CreateRunspace()
    $Runspace.ApartmentState = "STA" 
    $Runspace.ThreadOptions = "ReuseThread"           
    $Runspace.Open()
    $Runspace.SessionStateProxy.SetVariable("SyncHash", $SyncHash)

    # Show GUI
    $PowerShellCommand = [PowerShell]::Create().AddScript({
        # Functions
        function Load-XAMLCode {
            param(
                [parameter(Mandatory=$true)]
                [ValidateNotNullOrEmpty()]
                [string]$FilePath
            )
            # Construct new XML document
            $XAMLLoader = New-Object -TypeName System.Xml.XmlDocument

            # Load file from parameter input
            $XAMLLoader.Load($FilePath)

            # Return XAML document
            return $XAMLLoader
        }

        function Prompt-MessageBox {
            param(
                [parameter(Mandatory=$true)]
                [ValidateNotNullOrEmpty()]
                [string]$Message,

                [parameter(Mandatory=$true)]
                [ValidateNotNullOrEmpty()]
                [string]$WindowTitle,

                [parameter(Mandatory=$false)]
                [ValidateNotNullOrEmpty()]
                [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,

                [parameter(Mandatory=$false)]
                [ValidateNotNullOrEmpty()]
                [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::None
            )
            return [System.Windows.Forms.MessageBox]::Show($Message, $WindowTitle, $Buttons, $Icon)
        }

        # Add assemblies
        Add-Type -AssemblyName "PresentationFramework", "PresentationCore", "WindowsBase", "System.Windows.Forms"

        # Load XAML code
        $XAMLCode = Load-XAMLCode -FilePath (Join-Path -Path $SyncHash.ScriptRoot -ChildPath "MainWindow.xaml")

        # Instantiate XAML window
        $XAMLReader = (New-Object -TypeName System.Xml.XmlNodeReader -ArgumentList $XAMLCode) 
        $SyncHash.Window = [Windows.Markup.XamlReader]::Load($XAMLReader)
	    $SyncHash.Window.Add_Closed({$SyncHash.OnClose = $true})

        # Convert Base64 image string to bitmap for XAML Window Icon property
        $Base64Image = "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"
        $BitmapImage = New-Object -TypeName System.Windows.Media.Imaging.BitmapImage
        $BitmapImage.BeginInit()
        $BitmapImage.StreamSource = [System.IO.MemoryStream][System.Convert]::FromBase64String($Base64Image)
        $BitmapImage.EndInit()
        $BitmapImage.Freeze()
        $SyncHash.Window.Icon = $BitmapImage

        # Locate and dynamically create the XAML controls
        $XAMLCode.SelectNodes("//*[@Name]") | ForEach-Object { $SyncHash.$($_.Name) = $SyncHash.Window.FindName("$($_.Name)") }

        # Site Configuration - Events
        $SyncHash.Button_Start.Add_Click({
            $SyncHash.ObservableCollection.Clear()
            $SyncHash.Host.Runspace.Events.GenerateEvent("Button_Warranty_Click", $SyncHash.Button_Start, $null, "")
        })

        # GUI update script block (this code will run for each tick in the timer below)
        $GUIUpdateBlock = {
            # Device Name
            if ($SyncHash.DeviceName -notlike [System.String]::Empty) {
                $SyncHash.TextBox_DeviceName.Text = $SyncHash.DeviceName
            }

            # Service tag
            if ($SyncHash.ServiceTag -notlike [System.String]::Empty) {
                $SyncHash.TextBox_ServiceTag.Text = $SyncHash.ServiceTag
            }

            # Model
            if ($SyncHash.Model -notlike [System.String]::Empty) {
                $SyncHash.TextBox_Model.Text = $SyncHash.Model
            }

            # Sandbox mode
            if ($SyncHash.CheckBox_SandBox.IsChecked -eq $true) {
                $SyncHash.SandboxMode = $true
            }
            else {
                $SyncHash.SandboxMode = $false
            }

            # DataGrid
            if ($SyncHash.ObservableCollection.Count -ge 1) {
                $SyncHash.DataGrid_Main.ItemsSource = $SyncHash.ObservableCollection
                if ($SyncHash.DataGrid_Main.Items.NeedsRefresh) {
                    $SyncHash.DataGrid_Main.Items.Refresh()
                }
            }

            # ProgressBar
            switch ($SyncHash.ProgressBarMode) {
                $true {
                    $SyncHash.ProgressBar_Main.IsIndeterminate = $true
                }
                $false {
                    $SyncHash.ProgressBar_Main.IsIndeterminate = $false
                }
            }

            # MessageBox
            if ($SyncHash.InvokeMessageBox -eq $true) {
                Prompt-MessageBox -Message $SyncHash.MessageBoxText -WindowTitle $SyncHash.MessageBoxHeader -Icon Warning
                $SyncHash.InvokeMessageBox = $false
                $SyncHash.MessageBoxText = [System.String]::Empty
                $SyncHash.MessageBoxHeader = [System.String]::Empty
            }
        }

        # Before displaying the GUI, create a DispatcherTimer running the GUI update block
        $Global:DispatcherTimer = New-Object -TypeName System.Windows.Threading.DispatcherTimer

        # Run 4 times every second
        $DispatcherTimer.Interval = [TimeSpan]"0:0:0.01"

        # Invoke the GUIUpdateBlock script block
        $DispatcherTimer.Add_Tick($GUIUpdateBlock)

        # Start the DispatcherTimer
        $DispatcherTimer.Start()

        # Show GUI
        $SyncHash.Window.ShowDialog() | Out-Null
    })

    # Invoke code in PowerShellCommand variable assigning it to a runspace
    $PowerShellCommand.Runspace = $Runspace
    $Data = $PowerShellCommand.BeginInvoke()
}
Process {
    # Functions
    function Get-DeviceProperty {
        param(
            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$ResourceID,

            [Parameter(Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("Model","SerialNumber")]
            [string]$Property
        )
        switch ($Property) {
            "Model" { $DeviceQuery = "SELECT * FROM SMS_G_System_COMPUTER_SYSTEM WHERE ResourceID like '$($ResourceID)'" }
            "SerialNumber" { $DeviceQuery = "SELECT * FROM SMS_G_System_PC_BIOS WHERE ResourceID like '$($ResourceID)'" }
        }
        $DeviceComputerSystem = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query $DeviceQuery -ComputerName $SiteServer -ErrorAction SilentlyContinue
        if ($DeviceComputerSystem -ne $null) {
            return $DeviceComputerSystem.$Property
        }
    }

    function Get-Warranty {
        # Initiate progressbar control
        $SyncHash.ProgressBarMode = $true

        # Validate device hardware inventory presence
        $DeviceQuery = "SELECT * FROM SMS_G_System_COMPUTER_SYSTEM WHERE ResourceID like '$($ResourceID)'"
        $DeviceHardwareInventory = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query $DeviceQuery -ComputerName $SiteServer -ErrorAction SilentlyContinue
        if ($DeviceHardwareInventory -ne $null) {
            # Get service tag and model from SMS provider
            $SyncHash.ServiceTag = Get-DeviceProperty -ResourceID $ResourceID -Property SerialNumber
            $SyncHash.Model = Get-DeviceProperty -ResourceID $ResourceID -Property Model

            # Define API urls
            $SyncHash.ProductionAPI = "https://api.dell.com/support/assetinfo/v4/getassetwarranty/$($SyncHash.ServiceTag)?apikey=$($SyncHash.APIKey)"
            $SyncHash.SandboxAPI = "https://sandbox.api.dell.com/support/assetinfo/v4/getassetwarranty/$($SyncHash.ServiceTag)?apikey=$($SyncHash.APIKey)"

            # Determine what API to get warranty data from
            switch ($SyncHash.SandboxMode) {
                $true { $URI = $SyncHash.SandboxAPI }
                $false { $URI = $SyncHash.ProductionAPI }
            }

            # Get warranty data
            try {
                # Invoke REST method against Dell Warranty API
                $AssetInformation = Invoke-RestMethod -Uri $URI -Method Get -ErrorAction Stop

                # Empty string array holding custom objects per asset entitlement
                $AssetEntitlements = @()

                # Construct custom object
                if ($AssetInformation -ne $null) {
                    foreach ($AssetInfo in $AssetInformation.AssetWarrantyResponse.AssetEntitlementData) {
                        $PSObject = [PSCustomObject]@{
                            Description = $AssetInfo.ServiceLevelDescription
                            StartDate = ($AssetInfo.StartDate -as [datetime]).ToShortDateString()
                            EndDate = ($AssetInfo.EndDate -as [datetime]).ToShortDateString()
                            ShipDate = ($AssetInformation.AssetWarrantyResponse.AssetHeaderData.ShipDate -as [datetime]).ToShortDateString()
                        }
                        $AssetEntitlements += $PSObject
                    }

                    # Construct new ObservableCollection object to hold the custom objects
                    $ObservableCollection = New-Object -TypeName System.Collections.ObjectModel.ObservableCollection[Object] -ArgumentList @(,$AssetEntitlements)

                    # Set shared SyncHash property
                    $SyncHash.ObservableCollection = $ObservableCollection
                }
                else {
                    $SyncHash.MessageBoxText = "Empty warranty response from API"
                    $SyncHash.MessageBoxHeader = "API Error"
                    $SyncHash.InvokeMessageBox = $true
                }
            }
            catch [System.Exception] {
                if ($SyncHash.SandboxMode -eq $false) {
                    $SyncHash.MessageBoxText = "An error occured while attempting to invoke a request against Dell Production API. Before you can leverage the production API, use sandbox mode and contact Dell to get your API key promoted.`n`nError: $($_.Exception.Message)"
                    $SyncHash.MessageBoxHeader = "API Error"
                    $SyncHash.InvokeMessageBox = $true
                }
                else {
                    $SyncHash.MessageBoxText = "$($_.Exception.Message)"
                    $SyncHash.MessageBoxHeader = "API Error"
                    $SyncHash.InvokeMessageBox = $true
                }
            
            }            
        }
        else {
            $SyncHash.MessageBoxText = "No valid hardware inventory found for $($SyncHash.DeviceName)"
            $SyncHash.MessageBoxHeader = "Hardware inventory not found"
            $SyncHash.InvokeMessageBox = $true
        }

        # Complete progressbar control
        $SyncHash.ProgressBarMode = $false
    }

    function Stop-ScriptExecution {
	    # Keep the window open until it has manually been closed
	    do {
		    Start-Sleep -Seconds 1
		    if ($SyncHash.Window.IsVisible -eq $false) {
			    Start-Sleep -Seconds 2
		    }
	    }
	    while ($SyncHash.OnClose -ne $true)
    }

    # Register events for functions
    Register-EngineEvent -SourceIdentifier "Button_Warranty_Click" -Action {
        Get-Warranty
    }

    # Stop script execution in order to prevent script exiting
    Stop-ScriptExecution

    # Unregister events
    $RegisteredEvents = Get-EventSubscriber -SourceIdentifier "Button_*"
    if ($RegisteredEvents -ne $null) {
        foreach ($RegisteredEvent in $RegisteredEvents) {
            Unregister-Event -SourceIdentifier $RegisteredEvent.SourceIdentifier
        }
    }
}