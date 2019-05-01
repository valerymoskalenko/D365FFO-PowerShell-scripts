#region Schedule script to Optimize Indexes on Databases
$scriptPath = 'C:\Scripts'
$scriptName = 'Optimize-AxDB.ps1'
 
If (Test-Path "HKLM:\Software\Microsoft\Microsoft SQL Server\Instance Names\SQL") {
 
    Write-Host "Installing dbatools PowerShell module"
    Install-Module -Name dbatools -SkipPublisherCheck -Scope AllUsers
 
    Write-Host "Installing Ola Hallengren's SQL Maintenance scripts"
    Import-Module -Name dbatools
    Install-DbaMaintenanceSolution -SqlInstance . -Database master
    Write-Host "Running Ola Hallengren's IndexOptimize tool"
 
} Else {
    Write-Error "SQL not installed.  Skipped Ola Hallengren's index optimization"
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
 
Write-Host "Running Script for the first time..." -ForegroundColor Yellow
Invoke-Expression $scriptFullPath
 
Write-Host "Registering the Script as Scheduled Task..." -ForegroundColor Yellow
#$atStartUp = New-JobTrigger -AtStartup -RandomDelay 00:40:00
$atStartUp =  New-JobTrigger -Daily -At "3:07 AM" -DaysInterval 1 -RandomDelay 00:40:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew 
Register-ScheduledJob -Name AXDBOptimizationStartupTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option 
#Unregister-ScheduledJob -Name AXDBOptimizationStartupTask   
#endregion 
