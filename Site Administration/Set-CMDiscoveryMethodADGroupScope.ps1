# Import Configuration Manager module
Import-Module -Name ConfigurationManager

# Set location to the ConfigMgr PSDrive
Set-Location -Path P01:

# Define variables
$SearchFilter = "Groups"
$SearchBase = "OU=Contoso,DC=contoso,DC=com"

# Get distinguished names for eligible OU's
$OUDistinguishedNames = Get-ADOrganizationalUnit -Filter "Name -like '$($SearchFilter)'" -SearchBase $SearchBase | Select-Object -ExpandProperty DistinguishedName

# Construct array list
$ADGroupDiscoveryList = New-Object -TypeName System.Collections.ArrayList

# Process each discovered AD object
foreach ($OUDistinguishedName in $OUDistinguishedNames) {
    # Determine parent OU name
    $OUParent = (([ADSI]"LDAP://$($OUDistinguishedName)").Parent).SubString(7)
    $OUParentName = Get-ADOrganizationalUnit -Identity $OUParent | Select-Object -ExpandProperty Name

    # Create new ADGroupDiscoveryScope object and add it to the array list
    $ADGroupDiscoveryScope = New-CMADGroupDiscoveryScope -Name $OUParentName -LdapLocation "LDAP://$($OUDistinguishedName)" -RecursiveSearch $true
    $ADGroupDiscoveryList.Add($ADGroupDiscoveryScope) | Out-Null
    
}

# Set the Discovery Method scope
Set-CMDiscoveryMethod -ActiveDirectoryGroupDiscovery -AddGroupDiscoveryScope $ADGroupDiscoveryList