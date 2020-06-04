#region Schedule script to Optimize Indexes on Databases -->
$scriptPath = 'C:\Scripts'
$scriptName = 'Optimize-AxDB.ps1'

Write-Host "Installing Ola Hallengren's SQL Maintenance scripts"
Import-Module -Name dbatools
Install-DbaMaintenanceSolution -SqlInstance . -Database master
Write-Host "Running Ola Hallengren's IndexOptimize tool"

Write-Host "Saving Script..." -ForegroundColor Yellow
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

Write-Host "Running Script for the first time..." -ForegroundColor Yellow
Invoke-Expression $scriptFullPath

Write-Host "Registering the Script as Scheduled Task to run it Daily..." -ForegroundColor Yellow
$atStartUp =  New-JobTrigger -Daily -At "3:07 AM" -DaysInterval 1 -RandomDelay 00:40:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AXDBOptimizationDailyTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AXDBOptimizationDailyTask

Write-Host "Registering the Script as Scheduled Task to run it at Startup..." -ForegroundColor Yellow
$atStartUp = New-JobTrigger -AtStartup -RandomDelay 00:55:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AXDBOptimizationStartupTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AXDBOptimizationStartupTask

#endregion Schedule script to Optimize Indexes on Databases <--
