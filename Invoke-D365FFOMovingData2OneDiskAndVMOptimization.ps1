# https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Invoke-D365FFOMovingData2OneDiskAndVMOptimization.ps1
$ErrorActionPreference = 'Stop'
#region Installing d365fo.tools and dbatools <--
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Write-Host 'Installing PowerShell modules d365fo.tools and dbatools' -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
$modules2Install = @('d365fo.tools','dbatools','RobocopyPS','Carbon')
foreach($module in  $modules2Install)
{
    Write-Host '..working on module' $module -ForegroundColor Yellow
    if ($null -eq $(Get-Command -Module $module)) {
        Write-Host '....installing module' $module -ForegroundColor Gray
        Install-Module -Name $module -SkipPublisherCheck -Scope AllUsers
    } else {
        Write-Host '....updating module' $module -ForegroundColor Gray
        Update-Module -Name $module
    }
}
#endregion Installing d365fo.tools and dbatools -->

#region Shutdown D365FO and Apply Defender rules <--
Write-Host 'Stopping D365FO' -ForegroundColor Yellow
Stop-D365Environment -All
Add-D365WindowsDefenderRules  #Add Defender Rules to improve performance
#endregion Shutdown D365FO and Apply Defender rules -->

#region Default values for Variables<--
[string]$diskK_ServiceVolume = (Get-Volume -FileSystemLabel 'Service Volume').DriveLetter + ':';
if ($null -eq $diskK_ServiceVolume) {$diskK_ServiceVolume = 'K:'}
[string]$diskG_MSSQLData = (Get-Volume -FileSystemLabel 'MSSQL Data').DriveLetter + ':';
if ($null -eq $diskG_MSSQLData) {$diskG_MSSQLData = 'G:'}
[string]$diskH_MSSQLLogs = (Get-Volume -FileSystemLabel 'MSSQL Logs').DriveLetter + ':';
if ($null -eq $diskH_MSSQLLogs) {$diskH_MSSQLLogs = 'H:'}
[string]$diskI_MSSQLTempDB = (Get-Volume -FileSystemLabel 'TempDB Storage').DriveLetter + ':';
if ($null -eq $diskI_MSSQLTempDB) {$diskI_MSSQLTempDB = 'I:'} #JFI, We are going to skip this folder. It will be restored automatically by MSSQL in disk D:\
[string]$diskJ_MSSQLBackup = (Get-Volume -FileSystemLabel 'MSSQL Backup').DriveLetter + ':';
if ($null -eq $diskJ_MSSQLBackup) {$diskJ_MSSQLBackup = 'J:'}
if ($null -eq $diskP_SSDDisk) {$diskP_SSDDisk = 'P:'}  #Target disk
#endregion Default values for Variables -->

#region Get new disk online and format it -->
$local_disks = Get-Disk | where {$_.PartitionStyle -eq 'RAW'}

if ($null -eq $local_disks)
{
    Write-Error "There is no new disk attached to this VM"
    throw "There is no new disk attached to this VM"
}
if ($null -ne $local_disks[1])  #$local_disks.Count -ne 1
{
    $local_disks | FT -AutoSize
    Write-Error "Only one new disk should be attached to the VM"
    throw "Only one new disk should be attached to the VM"
}

foreach($local_disk in $local_disks)
{
    [string]$diskP_SSDDiskLetterOnly = $diskP_SSDDisk.Replace(':','')
    Write-Host 'Formatting drive' $diskP_SSDDiskLetterOnly -ForegroundColor Yellow
    $local_disk | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -DriveLetter $diskP_SSDDiskLetterOnly -UseMaximumSize -Alignment $(4*1024) | Format-Volume -FileSystem NTFS -NewFileSystemLabel $DriveLabel -AllocationUnitSize $(4*1024) -Confirm:$false
    #$local_disk | New-Partition -DriveLetter $diskP_SSDDiskLetterOnly -UseMaximumSize -Alignment $(4*1024) | Format-Volume -FileSystem NTFS -NewFileSystemLabel $DriveLabel -AllocationUnitSize $(4*1024) -Confirm:$false
}
#endregion Get new disk online and format it <--

#region Adding sql service account to the local Administrator group <--
Import-Module Microsoft.PowerShell.LocalAccounts
Import-Module -Name Carbon
$sServiceName = 'MSSQLSERVER'  #MS SQL Service name
$mssql = Get-WmiObject -Query "SELECT * FROM Win32_Service WHERE Name = '$sServiceName'"
[string]$mssqlServiceUser = $($mssql.StartName)
Write-Host 'Adding' $mssqlServiceUser 'service account to local Administrators group' -ForegroundColor Yellow
Add-LocalGroupMember -Group 'Administrators' -Member $mssqlServiceUser
Get-LocalGroupMember -Group 'Administrators' | FT
Grant-CPrivilege -Identity $mssqlServiceUser -Privilege SeImpersonatePrivilege -Verbose
Grant-CPrivilege -Identity $mssqlServiceUser -Privilege SeLockMemoryPrivilege -Verbose
Grant-CPrivilege -Identity $mssqlServiceUser -Privilege SeManageVolumePrivilege -Verbose
#endregion Adding sql service account to the local Administrator group -->

#region General SQL Server settings <--
Write-Host 'SQL Server settings' -ForegroundColor Yellow
$compMaxRAM = [Math]::Round((Get-WmiObject -Class win32_computersystem -ComputerName localhost).TotalPhysicalMemory/1Mb)
$compSQLMaxRAM = [Math]::Round($compMaxRAM / 8)
$compSQLMaxRAM = if ($compSQLMaxRAM -ge 8200) {8192} else {$compSQLMaxRAM} #Max SQL should not be more than 8192 MB of RAM
$compSQLMinRAM = [Math]::Round($compMaxRAM / 16)
$compSQLMinRAM = if ($compSQLMinRAM -le 1000) {1024} else {$compSQLMinRAM} #Just 1024 MB of RAM should be enough as minimum everywhere
Write-Host '.. SQL Max RAM' $compSQLMaxRAM 'SQL Min RAM' $compSQLMinRAM -ForegroundColor Gray
$SQLSCript = @"
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
EXEC sys.sp_configure N'min server memory (MB)', N'$compSQLMinRAM'
EXEC sys.sp_configure N'max server memory (MB)', N'$compSQLMaxRAM'
EXEC sys.sp_configure N'backup compression default', N'1'
EXEC sys.sp_configure N'cost threshold for parallelism', N'50'
EXEC sys.sp_configure N'max degree of parallelism', N'1'
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE
GO
"@
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $SQLSCript
#endregion General SQL Server settings -->

#region Move SQL TempDB to disk D:\ <--
#$computerName = $env:COMPUTERNAME.Remove($env:COMPUTERNAME.LastIndexOf('-') ,$env:COMPUTERNAME.Length - $env:COMPUTERNAME.LastIndexOf('-') )
Write-Host 'SQL Performance Optimization: Moving TempDB to Temp Drive D:\' -ForegroundColor Yellow
$SQLScriptMoveTempDB = @'
/* Re-sizing TempDB to 8 GB */
    USE [master];
    GO
    ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev',  FILENAME = 'D:\d365fo_tempdb1.mdf',size = 2GB, FILEGROWTH = 512MB);
    ALTER DATABASE tempdb MODIFY FILE (NAME = N'templog',  FILENAME = 'D:\d365fo_templog.ldf',size = 2GB, FILEGROWTH = 512MB);
    ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev2', FILENAME = 'D:\d365fo_tempdb2.mdf',size = 2GB, FILEGROWTH = 512MB);
    ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev3', FILENAME = 'D:\d365fo_tempdb3.mdf',size = 2GB, FILEGROWTH = 512MB);
    ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev4', FILENAME = 'D:\d365fo_tempdb4.mdf',size = 2GB, FILEGROWTH = 512MB);
    -- ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev5', FILENAME = 'D:\d365fo_tempdb5.mdf',size = 2GB, FILEGROWTH = 512MB);
    -- ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev6', FILENAME = 'D:\d365fo_tempdb6.mdf',size = 2GB, FILEGROWTH = 512MB);
    -- ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev7', FILENAME = 'D:\d365fo_tempdb7.mdf',size = 2GB, FILEGROWTH = 512MB);
    -- ALTER DATABASE tempdb MODIFY FILE (NAME = N'tempdev8', FILENAME = 'D:\d365fo_tempdb8.mdf',size = 2GB, FILEGROWTH = 512MB);
GO
'@
Invoke-DbaQuery -SqlInstance localhost -Database master -Query $SQLScriptMoveTempDB
#endregion Move SQL TempDB to disk D:\ -->

#region SQL Databases optimization: Set grow step and Execute DB Shrink -->
#Import SQL PowerShell module
Import-Module SQLPS –DisableNameChecking
Write-Host 'SQL Performance optimization: Set growing factor to 64MByte' -ForegroundColor Yellow

foreach($database in @('AxDB','AxDW','DynamicsAxReportServer','DynamicsAxReportServerTempDB','DYNAMICSXREFDB','FinancialReportingDb'))
{
    $SQLDatabase = Get-SqlDatabase -Name $database -ServerInstance localhost
    #Set Size and Autogrowth Settings for Data Files of the Database
    $FileGroups = $SQLDatabase.FileGroups
    ForEach($FileGroup in $FileGroups)
    {
        ForEach ($File in $FileGroup.Files)
        {
            $File.GrowthType = 'KB'
            $File.Growth = '65536' #64MB
            #$File.MaxSize = '-1' #Unlimited
            #$File.Size = '5242880' #5GB
            $File.Alter()
        }
    }
    #Set Size and Autogrowth Settings for Log Files
    Foreach($LogFile in $SQLDatabase.LogFiles)
    {
        $LogFile.GrowthType = [Microsoft.SqlServer.Management.Smo.FileGrowthType]::KB
        $LogFile.Growth = '65536'  #64MB
        #$LogFile.Size = '2097152' #2GB
        #$LogFile.MaxSize = '-1' #Unlimited
        $LogFile.Alter()
    }
#Read more: https://www.sharepointdiary.com/2017/06/change-sql-server-database-initial-size-auto-growth-settings-using-powershell.html#ixzz6LZFf2mHH
}

#Write-Host 'SQL Performance optimization: Shrink all user Databases (10 minutes)' -ForegroundColor Yellow
#Invoke-DbaDbShrink -SqlInstance localhost -AllUserDatabases -ExcludeDatabase DYNAMICSXREFDB -Verbose
#endregion SQL Databases optimization: Set grow step and Execute DB Shrink <--

#region Detach all D365FO SQL Databases <--
Write-Host 'Detaching all D365FO Databases' -ForegroundColor Yellow
$SQLScriptDetachAllDB = @'
    USE [master]
    ALTER DATABASE [AxDB] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    EXEC master.dbo.sp_detach_db @dbname = N'AxDB'
    GO
    ALTER DATABASE [AxDW] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    EXEC master.dbo.sp_detach_db @dbname = N'AxDW'
    GO
    ALTER DATABASE [DynamicsAxReportServer] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    EXEC master.dbo.sp_detach_db @dbname = N'DynamicsAxReportServer'
    GO
    ALTER DATABASE [DynamicsAxReportServerTempDB] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    EXEC master.dbo.sp_detach_db @dbname = N'DynamicsAxReportServerTempDB'
    GO
    ALTER DATABASE [DYNAMICSXREFDB] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    EXEC master.dbo.sp_detach_db @dbname = N'DYNAMICSXREFDB'
    GO
    ALTER DATABASE [FinancialReportingDb] SET  SINGLE_USER WITH ROLLBACK IMMEDIATE
    EXEC master.dbo.sp_detach_db @dbname = N'FinancialReportingDb'
    GO
'@
Invoke-DbaQuery -SqlInstance localhost -Database master -Query $SQLScriptDetachAllDB
#endregion Shutdown D365FO and Detach all D365FO SQL Databases -->

#region stop Monitoring services -->
Write-Host 'Stopping monitoring and diagnostics services' -ForegroundColor Yellow
Get-Service DiagTrack,Dmwappushservice,MR2012ProcessService,LCSDiagnosticClientService -ErrorAction SilentlyContinue | Stop-Service -Force -Verbose

Write-Host '..Stopping Monitoring Agent ETW sessions...' -ForegroundColor Yellow
& K:\AosService\PackagesLocalDirectory\Plugins\Monitoring\MonitoringInstall.exe /stopsessions /log:K:\AosService\PackagesLocalDirectory\Plugins\Monitoring\Stopsessions.log /append

Write-Host '..Stopping Monitoring Agent processes...' -ForegroundColor Yellow
& K:\AosService\PackagesLocalDirectory\Plugins\Monitoring\MonitoringInstall.exe /stopagentlauncher /id:SingleAgent /log:K:\AosService\PackagesLocalDirectory\Plugins\Monitoring\StopAgentLauncher.log /append /agentDirectory:K:\AosService\PackagesLocalDirectory\Plugins\Monitoring /rootdatadir:K:\MonAgentData

#Stop D365 environment again
Write-Host 'Stopping and disabling all FSCM services' -ForegroundColor Yellow
Stop-D365Environment -All
Get-D365Environment | Set-Service -StartupType Disabled

#Main FSCM services
Get-process -Name Batch, MRServiceHost, Microsoft.Dynamics.AX.Framework.Tools.DMF.SSISHelperService -ErrorAction SilentlyContinue | Stop-Process -Force -Verbose

#IIS Services
Get-Process -Name iisadmin, was, w3svc -ErrorAction SilentlyContinue | Stop-Process -Force -Verbose

#monitoring Services
Get-Process -Name LCSDiagFXService, MonAgentCore, MonAgentHost, MonAgentLauncher, MonAgentManager, WindowsAzureGuestAgent, WindowsAzureNetAgent -ErrorAction SilentlyContinue | Stop-Process -Force -Verbose

#SQL Services
Write-Host 'Stopping SQL Services' -ForegroundColor Yellow
Stop-DbaService -Force
#endregion stop Monitoring services <--

#region Copy data to disk P: -->
Write-Host 'Starting of data moving...' -ForegroundColor Yellow
$target_MSSQLData = Join-Path -Path $diskP_SSDDisk -ChildPath '\MSSQL\Data'
$target_MSSQLLogs = Join-Path -Path $diskP_SSDDisk -ChildPath '\MSSQL\Logs'
$target_MSSQLBackup = Join-Path -Path $diskP_SSDDisk -ChildPath '\MSSQL\Backup'
$target_ServiceVolume = Join-Path -Path $diskP_SSDDisk -ChildPath '\'
$source_MSSQLData = Join-Path -Path $diskG_MSSQLData -ChildPath '\MSSQL_DATA'
$source_MSSQLLogs = Join-Path -Path $diskH_MSSQLLogs -ChildPath '\MSSQL_LOGS'
$source_MSSQLBackup = Join-Path -Path $diskJ_MSSQLBackup -ChildPath '\MSSQL_BACKUP'
$source_ServiceVolume = Join-Path -Path $diskK_ServiceVolume -ChildPath '\'
$robocopy_logFile = 'C:\Temp\robocopy.txt'
#Create target folders
New-Item -Path $target_MSSQLData, $target_MSSQLLogs, $target_MSSQLBackup -ItemType Directory -Force
#Install-Module -Name RobocopyPS -SkipPublisherCheck -Scope AllUsers
Import-Module -Name RobocopyPS
Write-Host 'Copy MS SQL Data files. It could take about 9 minutes' -ForegroundColor Yellow
$robocopyData = Invoke-RoboCopy -Source $source_MSSQLData -Destination $target_MSSQLData -LogFile $robocopy_logFile -IncludeEmptySubDirectories -ExcludeDirectory 'System Volume Information' -Threads 32
if (-not $robocopyData.Success)
{
    $robocopyData
    throw $robocopyData.LastExitCodeMessage
} else {
    Write-Host '.. Total time' $robocopyData.TotalTime 'Speed' $robocopyData.Speed -ForegroundColor Gray
}
Write-Host 'Copy MS SQL Logs files. It could take about 7 minutes' -ForegroundColor Yellow
$robocopyLogs = Invoke-RoboCopy -Source $source_MSSQLLogs -Destination $target_MSSQLLogs -LogFile $robocopy_logFile -IncludeEmptySubDirectories -ExcludeDirectory 'System Volume Information' -Threads 32
if (-not $robocopyLogs.Success)
{
    $robocopyLogs
    throw $robocopyLogs.LastExitCodeMessage
} else {
    Write-Host '.. Total time' $robocopyLogs.TotalTime 'Speed' $robocopyLogs.Speed -ForegroundColor Gray
}
Write-Host 'Copy MS SQL Backup files. It could take about 0 minutes' -ForegroundColor Yellow
$robocopyBackup = Invoke-RoboCopy -Source $source_MSSQLBackup -Destination $target_MSSQLBackup -LogFile $robocopy_logFile -IncludeEmptySubDirectories -ExcludeDirectory 'System Volume Information' -Threads 32
if (-not $robocopyBackup.Success)
{
    $robocopyBackup
    throw $robocopyBackup.LastExitCodeMessage
} else {
    Write-Host '.. Total time' $robocopyBackup.TotalTime 'Speed' $robocopyBackup.Speed -ForegroundColor Gray
}
Write-Host 'Copy files from Service Volume. It could take about 12 minutes' -ForegroundColor Yellow
#Exclude it as well Copying File K:\MonAgentData\SingleAgent\Tables\AsmScannerCounter_00000001000001.tsf. The system cannot find the file specified.
$robocopyServiceVolume = Invoke-RoboCopy -Source $source_ServiceVolume -Destination $target_ServiceVolume -LogFile $robocopy_logFile -IncludeEmptySubDirectories -ExcludeDirectory 'System Volume Information' -Threads 32
if (-not $robocopyServiceVolume.Success)
{
    $robocopyServiceVolume
    throw $robocopyServiceVolume.LastExitCodeMessage
} else {
    Write-Host '.. Total time' $robocopyServiceVolume.TotalTime 'Speed' $robocopyServiceVolume.Speed -ForegroundColor Gray
}
#endregion Copy data to disk P: <--

#region Renaming disks -->
Write-Host 'Renaming disk P: to K:' -ForegroundColor Yellow
Get-Partition -DriveLetter $diskK_ServiceVolume.Replace(':','') | Set-Partition -NewDriveLetter Q -Verbose
Get-Partition -DriveLetter $diskP_SSDDisk.Replace(':','') | Set-Partition -NewDriveLetter $diskK_ServiceVolume.Replace(':','') -Verbose
#endregion Renaming disks <--

#region Fix registry value -->
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Dynamics\AX\7.0\SDK" -Name "BackupPath" -Value "$diskK_ServiceVolume\DynamicsBackup"
#endregion Fix registry value <--

#region Attach SQL Databases -->
Write-Host 'Start SQL Services back' -ForegroundColor Yellow
Start-DbaService

Write-Host 'Attach all Databases back' -ForegroundColor Yellow
Write-Host '  Please note that only standard databases will be restored. If this environment has the AxDB restored from other environment, it will be necessary to re-attach it manually' -ForegroundColor Yellow
$SQLScriptAtachAllDB = @"
    USE [master]
    GO
    CREATE DATABASE [AxDB] ON ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Data\AxDB.mdf' ), ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Logs\AxDB_log.ldf' ) FOR ATTACH
    CREATE DATABASE [AxDW] ON ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Data\AxDW.mdf' ),( FILENAME = N'$diskK_ServiceVolume\MSSQL\Logs\AxDW_log.ldf' ) FOR ATTACH
    CREATE DATABASE [DynamicsAxReportServer] ON ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Data\DynamicsAxReportServer.mdf' ),( FILENAME = N'$diskK_ServiceVolume\MSSQL\Logs\DynamicsAxReportServer_log.ldf' ) FOR ATTACH
    CREATE DATABASE [DynamicsAxReportServerTempDB] ON ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Data\DynamicsAxReportServerTempDB.mdf' ),( FILENAME = N'$diskK_ServiceVolume\MSSQL\Logs\DynamicsAxReportServerTempDB_log.ldf' ) FOR ATTACH
    CREATE DATABASE [DYNAMICSXREFDB] ON ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Data\DYNAMICSXREFDB.mdf' ),( FILENAME = N'$diskK_ServiceVolume\MSSQL\Logs\DYNAMICSXREFDB_log.ldf' ) FOR ATTACH
    CREATE DATABASE [FinancialReportingDb] ON ( FILENAME = N'$diskK_ServiceVolume\MSSQL\Data\FinancialReportingDb.mdf' ),( FILENAME = N'$diskK_ServiceVolume\MSSQL\Logs\FinancialReportingDb_log.ldf' ) FOR ATTACH
"@
Invoke-DbaQuery -SqlInstance localhost -Database master -Query $SQLScriptAtachAllDB
#endregion Attach SQL Databases <--

#region Update Default paths in SQL Server -->
Write-Host 'Update Default paths in SQL Server' -ForegroundColor Yellow
[string]$newTarget_MSSQLData = Join-Path -Path $diskK_ServiceVolume -ChildPath '\MSSQL\Data'
[string]$newTarget_MSSQLLogs = Join-Path -Path $diskK_ServiceVolume -ChildPath '\MSSQL\Logs'
[string]$newTarget_MSSQLBackup = Join-Path -Path $diskK_ServiceVolume -ChildPath '\MSSQL\Backup'
Get-Service -Name MSSQLSERVER | Start-Service
#Add-Type -AssemblyName 'Microsoft.SqlServer.Smo, Version=10.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91'
$server = New-Object Microsoft.SqlServer.Management.Smo.Server($env:ComputerName)
$server.Properties['BackupDirectory'].Value = $newTarget_MSSQLBackup
$server.Properties['DefaultFile'].Value = $newTarget_MSSQLData
$server.Properties['DefaultLog'].Value = $newTarget_MSSQLLogs
$server.Alter()
#endregion Update Default paths in SQL Server <--

#region Schedule script to Optimize Indexes on Databases -->
$scriptPath = 'C:\Scripts'
$scriptName = 'Optimize-AxDB.ps1'
Write-Host 'Installing Ola Hallengren''s SQL Maintenance scripts'
Import-Module -Name dbatools
Install-DbaMaintenanceSolution -SqlInstance . -Database master
Write-Host 'Saving Script...' -ForegroundColor Yellow
$script = @'
    #region run Ola Hallengren's IndexOptimize
    $sqlIndexOptimize = "EXECUTE master.dbo.IndexOptimize
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
    Import-Module -Name dbatools
    Invoke-DbaQuery -SqlInstance localhost -Query $sqlIndexOptimize
    #endregion run Ola Hallengren's IndexOptimize
'@
$scriptFullPath = Join-Path $scriptPath $scriptName
New-Item -Path $scriptPath -ItemType Directory -Force
Set-Content -Value $script -Path $scriptFullPath -Force
Write-Host 'Running Script for the first time (10 minutes) ...' -ForegroundColor Yellow
Invoke-Expression $scriptFullPath

Write-Host 'Registering the Script as Scheduled Task to run it Daily...' -ForegroundColor Yellow
$atStartUp =  New-JobTrigger -Daily -At '3:07 AM' -DaysInterval 1 -RandomDelay 00:40:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AXDBOptimizationDailyTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AXDBOptimizationDailyTask

Write-Host 'Registering the Script as Scheduled Task to run it at Startup...' -ForegroundColor Yellow
$atStartUp = New-JobTrigger -AtStartup -RandomDelay 00:55:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AXDBOptimizationStartupTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AXDBOptimizationStartupTask
#endregion Schedule script to Optimize Indexes on Databases <--

# Enable D365 Services
Get-D365Environment | Set-Service -StartupType Automatic

#region Delete Storage pool -->
#if it failed, just re-execute whole block again or remove manually from Server Manager --> File and Storage Services --> Volumes --> Storage Pools
Write-Host 'Removing Storage Pool. Confirm that you are going to remove old disks' -ForegroundColor Yellow
Get-VirtualDisk -FriendlyName 'Pool0' | Remove-VirtualDisk -Verbose
Get-StoragePool -IsPrimordial $false | Remove-StoragePool -Verbose
#endregion Delete Storage pool <--

# Uninstall unnecessary PowerShell modules. Carbon definitely should be removed.
Uninstall-Module -Name Carbon,RobocopyPS
#If it generates the error "module 'Carbon' is currently in use." then please execute this uninstall command in the separate PowerShell window
#Please note if you skip Carbon module uninstallation, then you will get issues with LCS Deployments

Write-Host 'Finished. Please stop VM and remove old disks' -ForegroundColor Green
