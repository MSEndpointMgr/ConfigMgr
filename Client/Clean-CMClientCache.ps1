$ResourceMgr = New-Object -ComObject "UIResource.UIResourceMgr"
$CacheInfo = $ResourceMgr.GetCacheInfo()
$CacheInfo.GetCacheElements() | ForEach-Object {
    Write-Output "Deleting ContentID:" $_.ContentID
    Write-Output "Content location:" $_.Location
    Write-Output ""
    $CacheInfo.DeleteCacheElement($_.CacheElementID)
}