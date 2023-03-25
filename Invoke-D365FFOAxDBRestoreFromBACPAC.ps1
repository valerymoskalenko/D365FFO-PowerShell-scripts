## ***** Download bacpac file *********
#Save it to c:\temp\ or d:\temp\ for Azure VM
#Use the following PowerShell script to convert bacpac file to the SQL Database
#https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Invoke-D365FFOAxDBRestoreFromBACPAC.ps1

#If you are going to download BACPAC file from the LCS Asset Library, please use in this section
$BacpacSasLinkFromLCS = 'https://uswedpl1catalog.blob.core.windows.net%2Fproduct-financeandoperations%2Fd00c14a8-1980-481b-8506-f642cce1fac'
$NewDB = 'Demo-20230325' #Database name. No spaces in the name! Do not put here AxDB!
$TempFolder = 'd:\temp\' # 'c:\temp\'  #$env:TEMP

#If you are NOT going to download BACPAC file from the LCS Asset Library, please use in this section
$BacpacSasLinkFromLCS = ''
$f = Get-ChildItem D:\temp\CFBSSalesbackup.bacpac  #Please note that this file should be accessible from SQL server service account
$NewDB = $($f.BaseName).Replace(' ','_'); #'AxDB_CTS1005BU2'  #Temporary Database name for new AxDB. Use a file name or any meaningful name.
$NewDB = $($f.BaseName).Replace('-','_'); #'AxDB_CTS1005BU2'  #Temporary Database name for new AxDB. Use a file name or any meaningful name.

#############################################
$ErrorActionPreference = "Stop"

#region Installing d365fo.tools and dbatools <--
# This is required by Find-Module, by doing it beforehand we remove some warning messages
Write-Host "Installing PowerShell modules d365fo.tools and dbatools" -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
$modules2Install = @('d365fo.tools','dbatools')
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
#endregion Installing d365fo.tools and dbatools -->

#region Download bacpac from LCS
if ($BacpacSasLinkFromLCS.StartsWith('http'))
{
    Write-Host "Downloading BACPAC from the LCS Asset library" -ForegroundColor Yellow
    New-Item -Path $TempFolder -ItemType Directory -Force
    $TempFileName = Join-path $TempFolder -ChildPath "$NewDB.bacpac"

    Write-Host "..Downloading file" $TempFileName -ForegroundColor Yellow
    Invoke-D365InstallAzCopy
    Invoke-D365AzCopyTransfer -SourceUri $BacpacSasLinkFromLCS -DestinationUri $TempFileName -ShowOriginalProgress

    $f = Get-ChildItem $TempFileName 
    $NewDB = $($f.BaseName).Replace(' ','_')
}
#endregion Download bacpac from LCS

## Stop D365FO instance.
## Optional. You may Import bacpac while D365FO is up and running
## Stopping of D365FO will just improve performance / RAM Memory consumption
Write-Host "Stopping D365FO environment" -ForegroundColor Yellow
Stop-D365Environment
Enable-D365Exception -Verbose
Invoke-D365InstallSqlPackage  #Installing modern SqlPackage just in case

## Import bacpac to SQL Database
If (-not (Test-DbaPath -SqlInstance localhost -Path $($f.FullName)))
{
    Write-Warning "Database file $($f.FullName) could not be found by SQL Server. Try to move it to C:\Temp or D:\Temp"
    throw "Database file $($f.FullName) could not be found by SQL Server. Try to move it to C:\Temp or D:\Temp"
}
$f | Unblock-File
Write-Host "Import BACPAC file to the SQL database" $NewDB -ForegroundColor Yellow
Import-D365Bacpac -ImportModeTier1 -BacpacFile $f.FullName -NewDatabaseName $NewDB -ShowOriginalProgress -Verbose

## Removing AxDB_orig database and Switching AxDB:   NULL <-1- AxDB_original <-2- AxDB <-3- [NewDB]
Write-Host "Stopping D365FO environment and Switching Databases" -ForegroundColor Yellow
Stop-D365Environment
Remove-D365Database -DatabaseName 'AxDB_Original' -Verbose

# Suspend the script for 2.5 seconds
Start-Sleep -Seconds 2.5

Switch-D365ActiveDatabase -NewDatabaseName $NewDB -Verbose

# Suspend the script for 2.5 seconds
Start-Sleep -Seconds 2.5

## Put on hold all Batch Jobs
Write-Host "Disabling all current Batch Jobs" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "UPDATE BatchJob SET STATUS = 0 WHERE STATUS IN (1,2,5,7)  --Set any waiting, executing, ready, or canceling batches to withhold."

## Enable Users except Guest
Write-Host "Enable all users except Guest" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "Update USERINFO set ENABLE = 1 where ID != 'Guest'"

## Set DB Recovery Model to Simple  (Optional)
#Set-DbaDbRecoveryModel -SqlInstance localhost -RecoveryModel Simple -Database AxDB -Confirm:$false

## Enable SQL Change Tracking
Write-Host "Enabling SQL Change Tracking" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "ALTER DATABASE AxDB SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 6 DAYS, AUTO_CLEANUP = ON)"

## Truncate System tables. Values there will be re-created after AOS start
Write-Host "Truncating System tables. Values there will be re-created after AOS start" -ForegroundColor Yellow
$sqlSysTablesTruncate = @"
TRUNCATE TABLE SYSSERVERCONFIG
TRUNCATE TABLE SYSSERVERSESSIONS
TRUNCATE TABLE SYSCORPNETPRINTERS
TRUNCATE TABLE SYSCLIENTSESSIONS
TRUNCATE TABLE BATCHSERVERCONFIG
TRUNCATE TABLE BATCHSERVERGROUP
"@
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $sqlSysTablesTruncate

#fix retail users
$fixDBusers = @"
use AxDB;
DROP USER IF EXISTS [axdeployextuser];
DROP USER IF EXISTS [axretaildatasyncuser];
DROP USER IF EXISTS [axretailruntimeuser];
DROP USER IF EXISTS [axdbadmin];
GO
CREATE USER [axdeployextuser] FROM LOGIN [axdeployextuser];
CREATE USER [axdbadmin] FROM LOGIN [axdbadmin];
CREATE USER [axretaildatasyncuser] FROM LOGIN [axretaildatasyncuser];
CREATE USER [axretailruntimeuser] FROM LOGIN [axretailruntimeuser];
EXEC sp_addrolemember 'db_owner', 'axdeployextuser';
EXEC sp_addrolemember 'db_owner', 'axdbadmin';
EXEC sp_addrolemember 'db_owner', 'axretaildatasyncuser';
EXEC sp_addrolemember 'db_owner', 'axretailruntimeuser';
GO
"@
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $fixDBusers

## Clean up Power BI settings
Write-Host "Cleaning up Power BI settings" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "UPDATE PowerBIConfig set CLIENTID = '', APPLICATIONKEY = '', REDIRECTURL = ''"

## Run Database Sync
Write-Host "Executing Database Sync" -ForegroundColor Yellow
Invoke-D365DBSync -ShowOriginalProgress -Verbose

## Backup AxDB database
Write-Host "Backup AxDB" -ForegroundColor Yellow
Backup-DbaDatabase -SqlInstance localhost -Database AxDB -Type Full -CompressBackup -BackupFileName "dbname-$NewDB-backuptype-timestamp.bak" -ReplaceInName


## Promote user as admin and set default tenant  (Optional)
#Set-D365Admin -AdminSignInName 'D365Admin@ciellos.com'

## Start D365FO instance
Write-Host "Starting D365FO environment. Then open UI and refresh Data Entities." -ForegroundColor Yellow
Start-D365Environment

## INFO: get User email address/tenant
Write-Host "Getting information about users from AxDB" -ForegroundColor Yellow
$sqlGetUsers = @"
select ID, Name, NetworkAlias, NETWORKDOMAIN, Enable from userInfo
where NETWORKALIAS not like '%@contosoax7.onmicrosoft.com'
  and NETWORKALIAS not like '%@capintegration01.onmicrosoft.com'
  and NETWORKALIAS not like '%@devtesttie.ccsctp.net'
  and NETWORKALIAS not like '%@DAXMDSRunner.com'
  and NETWORKALIAS not like '%@dynamics.com'
  and NETWORKALIAS != ''
"@
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $sqlGetUsers | FT
