#Default computer name
#https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/edit/master/Rename-D365FFODevVM.ps1
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
 
#region Installing d365fo.tools
 
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
 
# Installing d365fo.tools
If ((Find-Module -Name d365fo.tools).InstalledDate -eq $null) {
    Write-Host "Installing d365fo.tools"
    Write-Host "    Documentation: https://github.com/d365collaborative/d365fo.tools"
    Install-Module -Name d365fo.tools -SkipPublisherCheck -Scope AllUsers
}
else {
    Write-Host "Updating d365fo.tools"
    Update-Module -name d365fo.tools -SkipPublisherCheck -Scope AllUsers
}
 
#endregion
 
#region Schedule script to Optimize Indexes on Databases
$scriptPath = 'C:\Scripts'
$scriptName = 'Optimize-AxDB.ps1'
 
If (Test-Path “HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL”) {
 
    Write-Host “Installing dbatools PowerShell module”
    Install-Module -Name dbatools -SkipPublisherCheck -Scope AllUsers
 
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
 
Function Execute-Sql {
    Param(
        [Parameter(Mandatory=$true)][string]$server,
        [Parameter(Mandatory=$true)][string]$database,
        [Parameter(Mandatory=$true)][string]$command
    )
    Process
    {
        $scon = New-Object System.Data.SqlClient.SqlConnection
        $scon.ConnectionString = "Data Source=$server;Initial Catalog=$database;Integrated Security=true"
        
        $cmd = New-Object System.Data.SqlClient.SqlCommand
        $cmd.Connection = $scon
        $cmd.CommandTimeout = 0
        $cmd.CommandText = $command
 
        try
        {
            $scon.Open()
            $cmd.ExecuteNonQuery()
        }
        catch [Exception]
        {
            Write-Warning $_.Exception.Message
        }
        finally
        {
            $scon.Dispose()
            $cmd.Dispose()
        }
    }
}
 
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
 
    Execute-Sql -server "." -database "master" -command $sql
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
#endregion  
 
#Rename and restart
Rename-Computer -NewName $NewComputerName -Restart   
