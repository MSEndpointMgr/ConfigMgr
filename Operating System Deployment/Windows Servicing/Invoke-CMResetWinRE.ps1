# Disable WinRE
try {
	Start-Process -FilePath "reagentc.exe" -ArgumentList "/Disable" -Wait -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "An error occured while disabling WinRE. Error message: $($_.Exception.Message)" ; exit 1
}

# Enable WinRE
try {
	Start-Process -FilePath "reagentc.exe" -ArgumentList "/Enable" -Wait -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message "An error occured while enabling WinRE. Error message: $($_.Exception.Message)" ; exit 1
}