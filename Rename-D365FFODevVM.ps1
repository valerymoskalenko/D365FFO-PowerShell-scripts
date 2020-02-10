#Default computer name
#https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/edit/master/Rename-D365FFODevVM.ps1
# Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/valerymoskalenko/D365FFO-PowerShell-scripts/master/Rename-D365FFODevVM.ps1'))

#region Define New Computer name <--
$NewComputerName = 'FC-Val10PU24'
Write-Host "New computer name is $NewComputerName" -ForegroundColor Green
$wrongSymbols = @(',','~',':','!','@','#','$','%','^','&','''','.','(',')','{','}','_',' ','\','/','*','?','"','<','>','|')  #https://support.microsoft.com/en-ca/help/909264/naming-conventions-in-active-directory-for-computers-domains-sites-and
[boolean]$WrongComputerName = $False
foreach($c in $NewComputerName.ToCharArray()) {if($c -in $wrongSymbols) {$WrongComputerName = $true; continue;} }
if($WrongComputerName)
{
    Write-Error "Computer name $newComputerName is wrong. It should not contains any of the following symbols: $wrongSymbols"
    Write-Host "Please update computer name. And repeat the script" -ForegroundColor Red
    break;
}
elseif(($NewComputerName.Length -gt 15) -or ($NewComputerName.Length -le 1))
{
    Write-Error "Computer name length should be between 1 and 15 symbols. Current length is $($NewComputerName.Length) symbols."
    Write-Host "Please update computer name. And repeat the script" -ForegroundColor Red
    break;
}
#endregion Define New Computer name -->

#region Disable IE Enhanced Security Configuration <--
function Disable-IEESC
{
    $AdminKey = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}”
    $UserKey = “HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}”
    Set-ItemProperty -Path $AdminKey -Name “IsInstalled” -Value 0
    Set-ItemProperty -Path $UserKey -Name “IsInstalled” -Value 0
    Stop-Process -Name Explorer
    Write-Host “IE Enhanced Security Configuration (ESC) has been disabled.” -ForegroundColor Green
}
Disable-IEESC 
#endregion Disable IE Enhanced Security Configuration -->

#region Disable UAC <--
Write-Verbose( "Disable UAC") -Verbose  # More details here https://www.powershellgallery.com/packages/cEPRSDisableUAC     
& "$env:SystemRoot\System32\reg.exe" ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 4 /f
& "$env:SystemRoot\System32\reg.exe" ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableInstallerDetection /t REG_DWORD /d 1 /f
& "$env:SystemRoot\System32\reg.exe" ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f
gpupdate
#endregion Disable UAC -->

#region password age pop up <--
net accounts /maxpwage:unlimited
#endregion password age pop up -->

#region Configure Windows Defender <--
Import-Module Defender
Add-MpPreference -ExclusionExtension '*.mdf', '*.ldf', '*.xml', '*.rdl', '*.md'
Add-MpPreference -ExclusionPath 'C:\ProgramData\sf'
Add-MpPreference -ExclusionPath 'C:\Program Files\Microsoft Service Fabric\bin'
Add-MpPreference -ExclusionPath 'C:\AosService\PackagesLocalDirectory\Bin','K:\AosService\PackagesLocalDirectory\Bin'
Add-MpPreference -ExclusionProcess @('Fabric.exe','FabricHost.exe','FabricInstallerService.exe','FabricSetup.exe','FabricDeployer.exe',
    'ImageBuilder.exe','FabricGateway.exe','FabricDCA.exe','FabricFAS.exe','FabricUOS.exe','FabricRM.exe','FileStoreService.exe')
Add-MpPreference -ExclusionProcess @('sqlservr.exe','pgc.exe','labelC.exe','xppc.exe','SyncEngine.exe','xppcAgent.exe','ReportingServicesService.exe','iisexpress.exe')
Add-MpPreference -ExclusionPath 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Binn' 
#endregion Configure Windows Defender -->

#region Installing d365fo.tools and dbatools <--
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Installing PowerShell modules d365fo.tools and dbatools
Install-Module -Name d365fo.tools -SkipPublisherCheck -Scope AllUsers
Install-Module -Name dbatools -SkipPublisherCheck -Scope AllUsers
#endregion Installing d365fo.tools and dbatools -->

#region SQL Server settings <--
$newName = $NewComputerName
$oldName= Invoke-Sqlcmd -Query "select @@servername as Name"
Write-Host "Old sql name is" $oldName.Name -ForegroundColor Yellow
$SQLSCript = @"
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
EXEC sys.sp_configure N'min server memory (MB)', N'2048'
EXEC sys.sp_configure N'max server memory (MB)', N'8192'
EXEC sys.sp_configure N'backup compression default', N'1'
EXEC sys.sp_configure N'cost threshold for parallelism', N'50'
EXEC sys.sp_configure N'max degree of parallelism', N'1'
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE
GO

sp_dropserver [$($oldName.Name)];
GO
sp_addserver [$newName], local;
GO
"@
Write-Host "Updating sql name to" $newName -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $SQLSCript
#endregion SQL Server settings -->

#region Disable Windows Updates <--
$WindowsUpdatePath = "HKLM:SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\"
$AutoUpdatePath = "HKLM:SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
If(Test-Path -Path $WindowsUpdatePath) {
    Remove-Item -Path $WindowsUpdatePath -Recurse
}
New-Item $WindowsUpdatePath -Force
New-Item $AutoUpdatePath -Force
Set-ItemProperty -Path $AutoUpdatePath -Name NoAutoUpdate -Value 1
Get-ScheduledTask -TaskPath "\Microsoft\Windows\WindowsUpdate\" | Disable-ScheduledTask
takeown /F C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator /A /R
icacls C:\Windows\System32\Tasks\Microsoft\Windows\UpdateOrchestrator /grant Administrators:F /T
Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator\" | Disable-ScheduledTask
Stop-Service wuauserv
Set-Service wuauserv -StartupType Disabled
Write-Host "All Windows Updates were disabled" -ForegroundColor Green
#endregion Disable Windows Updates -->

#region Update hosts file <--
$fileHosts = "$env:windir\System32\drivers\etc\hosts"
"127.0.0.1 $($env:COMPUTERNAME)" | Add-Content -PassThru $fileHosts
"127.0.0.1 $NewComputerName" | Add-Content -PassThru $fileHosts
"127.0.0.1 localhost" | Add-Content -PassThru $fileHosts
#endregion Update hosts file -->

#region Check and Clean up InventDimFieldBinding Table <--
Write-Host "Checking InventDimFieldBinding table for orphan InventProductDimensionFlavor record" -ForegroundColor Yellow
$InventDimFieldBinding = Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "select * from InventDimFieldBinding" 
$InventDimFieldBinding | FT -AutoSize -Wrap
#If table contains record regarding *Flavor, then we will clean up whole table. DB Sync will restore all information there. 
$InventDimFieldBindingFlavor = Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "select * from InventDimFieldBinding where CLASSNAME = 'InventProductDimensionFlavor'" 
if ($InventDimFieldBindingFlavor -ne $null)
{
    Write-Host "..Cleaning up InventDimFieldBinding table" -ForegroundColor Yellow
    Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "delete from InventDimFieldBinding" 
}
#endregion Check and Clean up InventDimFieldBinding Table -->

#region Schedule script to Optimize Indexes on Databases <--
$scriptPath = 'C:\Scripts'
$scriptName = 'Optimize-AxDB.ps1'

If (Test-Path “HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL”) {
    Write-Host “Installing Ola Hallengren's SQL Maintenance scripts”
    Import-Module -Name dbatools
    Install-DbaMaintenanceSolution -SqlInstance . -Database master
    Write-Host “Running Ola Hallengren's IndexOptimize tool”
} Else {
    Write-Verbose “SQL not installed.  Skipped Ola Hallengren's index optimization”
}

Write-Host "Saving Script..." -ForegroundColor Yellow
$script = @'
#region run Ola Hallengren's IndexOptimize
If (Test-Path “HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL”) {
 
    # http://calafell.me/defragment-indexes-on-d365-finance-operations-virtual-machine/
    $sql = "EXECUTE master.dbo.IndexOptimize
        @Databases = 'ALL_DATABASES',
        @FragmentationLow = NULL,
        @FragmentationMedium = 'INDEX_REORGANIZE,INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
        @FragmentationHigh = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE',
        @FragmentationLevel1 = 5,
        @FragmentationLevel2 = 25,
        @LogToTable = 'N',
        @UpdateStatistics = 'ALL',
        @OnlyModifiedStatistics = 'Y',
        @MaxDOP = 0"
 
    Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $sql
} Else {
    Write-Verbose “SQL not installed.  Skipped Ola Hallengren's index optimization”
}
#endregion
'@

$scriptFullPath = Join-Path $scriptPath $scriptName

New-Item -Path $scriptPath -ItemType Directory -Force
Set-Content -Value $script -Path $scriptFullPath -Force
 
#Write-Host "Running Script for the first time..." -ForegroundColor Yellow
#Invoke-Expression $scriptFullPath

Write-Host "Registering the Script as Scheduled Task..." -ForegroundColor Yellow
#$atStartUp = New-JobTrigger -AtStartup -RandomDelay 00:40:00
$atStartUp =  New-JobTrigger -Daily -At "3:07 AM" -DaysInterval 1 -RandomDelay 00:40:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew 
Register-ScheduledJob -Name AXDBOptimizeStartupTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option 
#Unregister-ScheduledJob -Name AXDBOptimizeStartupTask   
#endregion Schedule script to Optimize Indexes on Databases -->

#region Downloading Chrome browser <--
$Path = $env:TEMP; 
$Installer = "chrome_installer.exe"; 
Invoke-WebRequest 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' -Outfile $Path\$Installer;
Start-Process -FilePath $Path\$Installer -Args "/silent /install" -Verb RunAs -Wait; 
Remove-Item $Path\$Installer
#endregion Downloading Chrome browser -->

#region Fix Trace Parser <--
#https://sinedax.blogspot.com/2018/12/trace-parser-doesnt-work-dynamics-365.html
$resourcefiledir = "C:\AOSService\webroot"
$inputmanfile = "C:\AOSService\webroot\Monitoring\DynamicsAXExecutionTraces.man"
$outputmanfile = "C:\AOSService\webroot\Monitoring\DynamicsAXExecutionTraces_copy.man"
$temp = Get-Content $inputmanfile
$temp = $temp -replace "%APPROOT%",$resourcefiledir
$temp | out-file $outputmanfile
wevtutil im $outputmanfile
$inputmanfile = "C:\AOSService\webroot\Monitoring\DynamicsAXXppExecutionTraces.man"
$outputmanfile = "C:\AOSService\webroot\Monitoring\DynamicsAXXppExecutionTraces_copy.man"
$temp = Get-Content $inputmanfile
$temp = $temp -replace "%APPROOT%",$resourcefiledir
$temp | out-file $outputmanfile
wevtutil im $outputmanfile
#endregion Fix Trace Parser -->

#region Disable Telemetry (requires a reboot to take effect) <--
Set-ItemProperty -Path HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection -Name AllowTelemetry -Type DWord -Value 0
Get-Service DiagTrack,Dmwappushservice | Stop-Service | Set-Service -StartupType Disabled
#endregion Disable Telemetry -->

#region Start Menu: Disable Cortana <--
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings")) {
	New-Item -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Type DWord -Value 0
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization")) {
	New-Item -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Type DWord -Value 1
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Type DWord -Value 1
If (!(Test-Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore")) {
	New-Item -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Force | Out-Null
}
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" -Name "HarvestContacts" -Type DWord -Value 0
If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search")) {
	New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Force | Out-Null
}
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Type DWord -Value 0
#endregion Start Menu: Disable Cortana -->

#region Workflow error. An error occurred while the HTTP request <--
#This could be due to the fact that the server certificate is not configured properly with HTTP.sys in the https case. 
#this could also be caused by the mismatch of the security binding between the client and the server
# https://sdhruva.wordpress.com/2019/11/22/dynamics-365-fo-workflow-error/
Set-ItemProperty HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319 -Name SchUseStrongCrypto -Value 1 -Type dword -Force -Confirm:$false
if ((Test-Path HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319)) { 
    Set-ItemProperty HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319 -Name SchUseStrongCrypto -Value 1 -Type dword -Force -Confirm:$false
}
#endregion Workflow error. An error occurred while the HTTP request -->

#region Set power settings to High Performance <--
Write-Host "Setting power settings to High Performance" -ForegroundColor Yellow
powercfg.exe /SetActive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
#endregion Set power settings to High Performance -->

#Rename and restart
Rename-Computer -NewName $NewComputerName -Restart   
