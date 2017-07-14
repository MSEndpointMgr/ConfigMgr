$SiteServer = "CAS01"
$SiteCode = "CAS"
$AppName = "7-Zip 9.20 x64"

try {
    Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.dll")
    Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.Extender.dll")
    Add-Type -Path (Join-Path -Path (Get-Item $env:SMS_ADMIN_UI_PATH).Parent.FullName -ChildPath "Microsoft.ConfigurationManagement.ApplicationManagement.MsiInstaller.dll")
}
catch {
    Write-Error $_.Exception.Message
}

$Applications = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class "SMS_ApplicationLatest" -ComputerName $SiteServer -Filter "LocalizedDisplayName like '%$($AppName)%'"
foreach ($Application in $Applications) {
    $LocalizedDisplayName = $Application.LocalizedDisplayName
    $CurrentApplication = [wmi]$Application.__PATH
    $ApplicationXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::DeserializeFromString($CurrentApplication.SDMPackageXML, $true)
    foreach ($DeploymentType in $ApplicationXML.DeploymentTypes) {
        # Clear the current Requirement rules
        $DeploymentType.Requirements.Clear()
        # Create an Operands object
        $Operands = New-Object -TypeName "Microsoft.ConfigurationManagement.DesiredConfigurationManagement.CustomCollection``1[[Microsoft.SystemsManagementServer.DesiredConfigurationManagement.Expressions.RuleExpression]]"
        $Operands.Add("Windows/All_x64_Windows_8.1_Client")
        $Operands.Add("Windows/All_x64_Windows_7_Client")
        # Create an Operator
        $Operator = [Microsoft.ConfigurationManagement.DesiredConfigurationManagement.ExpressionOperators.ExpressionOperator]::OneOf
        # Create an Operating Systems Expression object
        $OSExpression = New-Object -TypeName Microsoft.SystemsManagementServer.DesiredConfigurationManagement.Expressions.OperatingSystemExpression -ArgumentList (
            $Operator, 
            $Operands
        )
        # Create an Annotation object
        $Annotation = New-Object -TypeName Microsoft.SystemsManagementServer.DesiredConfigurationManagement.Rules.Annotation
        $Annotation.DisplayName = New-Object -TypeName Microsoft.SystemsManagementServer.DesiredConfigurationManagement.Rules.LocalizableString -ArgumentList (
            "DisplayName", 
            "Operating system One of {All Windows 7 (64-bit), All Windows 8.1 (64-bit)}", 
            $null
        )
        # Create a NonComplianceSeverity object
        $NonComplianceSeverity = [Microsoft.SystemsManagementServer.DesiredConfigurationManagement.Rules.NoncomplianceSeverity]::None
        # Create a Requirement object
        $RequirementRule = New-Object -TypeName Microsoft.SystemsManagementServer.DesiredConfigurationManagement.Rules.Rule -ArgumentList (
            ("Rule_" + [Guid]::NewGuid().ToString()),
            $NonComplianceSeverity,
            $Annotation,
            $OSExpression
        )
        # Add the Requirement object to the DeploymentType
        $DeploymentType.Requirements.Add($RequirementRule)
        # Re-serialize the ApplicationXML object
        $UpdatedXML = [Microsoft.ConfigurationManagement.ApplicationManagement.Serialization.SccmSerializer]::SerializeToString($ApplicationXML, $true)
        # Update WMI object
        $CurrentApplication.SDMPackageXML = $UpdatedXML
        $CurrentApplication.Put()
    }
}