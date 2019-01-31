#Default computer name
$NewComputerName = 'BBD-Val812U22'
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
 
 
#Disable IE Enhanced Security Configuration
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
 
 
#Disable UAC
Write-Verbose( "Disable UAC") -Verbose  # More details here https://www.powershellgallery.com/packages/cEPRSDisableUAC     
& "$env:SystemRoot\System32\reg.exe" ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 4 /f
& "$env:SystemRoot\System32\reg.exe" ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableInstallerDetection /t REG_DWORD /d 1 /f
& "$env:SystemRoot\System32\reg.exe" ADD "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v EnableLUA /t REG_DWORD /d 0 /f
gpupdate
 
 
#password age pop up
net accounts /maxpwage:unlimited
 
 
#Configure Windows Defender
Import-Module Defender
Add-MpPreference -ExclusionExtension '*.mdf', '*.ldf', '*.xml', '*.rdl', '*.md'
Add-MpPreference -ExclusionPath 'C:\ProgramData\sf'
Add-MpPreference -ExclusionPath 'C:\Program Files\Microsoft Service Fabric\bin'
Add-MpPreference -ExclusionPath 'C:\AosService\PackagesLocalDirectory\Bin','K:\AosService\PackagesLocalDirectory\Bin'
Add-MpPreference -ExclusionProcess @('Fabric.exe','FabricHost.exe','FabricInstallerService.exe','FabricSetup.exe','FabricDeployer.exe',
    'ImageBuilder.exe','FabricGateway.exe','FabricDCA.exe','FabricFAS.exe','FabricUOS.exe','FabricRM.exe','FileStoreService.exe')
Add-MpPreference -ExclusionProcess @('sqlservr.exe','pgc.exe','labelC.exe','xppc.exe','SyncEngine.exe','xppcAgent.exe','ReportingServicesService.exe','iisexpress.exe')
Add-MpPreference -ExclusionPath 'C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Binn' 
 
 
#SQL
Import-Module Sqlps
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
Invoke-Sqlcmd -Query $SQLSCript
 
 
#Disable Windows Updates
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
 
#Update hosts file
$fileHosts = "$env:windir\System32\drivers\etc\hosts"
"127.0.0.1 $($env:COMPUTERNAME)" | Add-Content -PassThru $fileHosts
"127.0.0.1 $NewComputerName" | Add-Content -PassThru $fileHosts
"127.0.0.1 localhost" | Add-Content -PassThru $fileHosts
 
#Rename and restart
Rename-Computer -NewName $NewComputerName -Restart
