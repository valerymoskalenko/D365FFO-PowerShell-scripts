$f = Get-ChildItem C:\temp\All81BinaryUpdates_4_4.zip  #Please update this path
#############################################
$ErrorActionPreference = "Stop"
#region Installing d365fo.tools  <--
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Write-Host "Installing PowerShell module d365fo.tools" -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
$modules2Install = @('d365fo.tools')
foreach($module in  $modules2Install)
{
    Write-Host "..working on module" $module -ForegroundColor Yellow
    if ($null -eq $(Get-Command -Module $module)) {
        Write-Host "....installing module" $module -ForegroundColor Gray
        Install-Module -Name $module -SkipPublisherCheck -Scope AllUsers
    } else {
        Write-Host "....updating module" $module -ForegroundColor Gray
        Update-Module -Name $module
    }
}
#endregion Installing d365fo.tools and  -->

#region Stop D365FO instance
Write-Host "Stopping D365FO environment" -ForegroundColor Yellow
Stop-D365Environment | FT
#endregion Stop D365FO instance

#region Test Deployable package
if (-not (Test-Path -Path $f.FullName))
{
    Write-Warning "File $($f.FullName) can not be found. Please check `$f variable"
    throw "File $($f.FullName) can not be found. Please check `$f variable"
}
#endregion Test Deployable package
#region Old Runbooks -->
if ($null -ne $(Get-D365Runbook))
{
    Write-Host "Old runbooks has been found. Backup and remove"
    Get-D365Runbook | Backup-D365Runbook -Force -Verbose #Delete old runbooks
    (Get-D365Runbook).File | Remove-Item -Force
} else {
    Write-host "No old runbooks has been found"
}
#endregion Old Runbooks -->

#region Deploy Deployable package
## it will be extracted from Archive and Deployed
Invoke-D365SDPInstall -Path $f.FullName -Command RunAll -Verbose
## Example How to re-execute failed step
#    $extractedDP = Join-Path -Path $f.Directory -ChildPath $f.BaseName
#    If (-not (Test-Path -Path $extractedDP)) { throw "Please update `$extractedDP variable with correct path with extracted Deployable Package" }
#    Invoke-D365SDPInstall -Path $extractedDP -Command ReRunStep -Step 25 -ShowOriginalProgress -Verbose
#endregion Deploy Deployable package
