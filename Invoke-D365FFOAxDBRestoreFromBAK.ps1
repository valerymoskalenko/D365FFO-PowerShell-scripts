#https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Invoke-D365FFOAxDBRestoreFromBAK.ps1
[string]$dt = get-date -Format "yyyyMMdd_HHmmss" #Generate the datetime stamp to make DB files unique

#If you are going to download BAK file from the LCS Asset Library either Azure Blob Storage, please use in this section
$BacpacSasLinkFromLCS = 'https://ctssqlbackup.blob.core.windows.net/fs3main-10/FS3Main-10_2021-01-25_083223.bak?sp=r&st=2021-01-26T07:40:21Z&se=2021-01-26T15:40:21Z&spr=https&sv=2019-12-12&sr=b&sig=15%2ByPW000000000000000lJYA%3D'
$dbName = 'CTSMain' #Any Meaningful name. Original Environment name, Project name, ... No spaces in the name!
$TempFolder = 'd:\temp\' # 'c:\temp\'  #$env:TEMP  #Path to Temp folder

#If you are NOT going to download BAK file from the LCS Asset Library, please use in this section
#$BacpacSasLinkFromLCS = ''
#$f = Get-ChildItem D:\temp\AxDB_GWTest_20201021.bak  #Please note that this file should be accessible from SQL server service account
#$dbName = $($f.BaseName).Replace(' ','_') + $dt # $f.BaseName  #'AxDB_CTS1005BU2'  #Temporary Database name for new AxDB. Use a file name or any meaningful name.

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

#region Apply SQL Connection settings <--
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true 
Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false
#endregion Apply SQL Connection settings -->

## Stop D365FO instance
Write-Host "Stopping D365FO environment" -ForegroundColor Yellow
Stop-D365Environment | FT
Enable-D365Exception -Verbose


## (Optional) Backup current AxDB just in case. You can find this DB as AxDB_original.
## You can skip this step
#Write-Host "Backup current AxDB (Optional)" -ForegroundColor Yellow
#Backup-DbaDatabase -SqlInstance localhost -Database AxDB -Type Full -CompressBackup -BackupFileName dbname-1005_original-backuptype-timestamp.bak -ReplaceInName

#region Download bacpac from LCS
if ($BacpacSasLinkFromLCS.StartsWith('http'))
{
    Write-Host "Downloading BACPAC from the LCS Asset library" -ForegroundColor Yellow
    New-Item -Path $TempFolder -ItemType Directory -Force
    $TempFileName = Join-path $TempFolder -ChildPath $($dbName + '_' + $dt + '.bak')

    Write-Host "..Downloading file" $TempFileName -ForegroundColor Yellow
    Invoke-D365InstallAzCopy
    Invoke-D365AzCopyTransfer -SourceUri $BacpacSasLinkFromLCS -DestinationUri $TempFileName -ShowOriginalProgress -EnableException

    $f = Get-ChildItem $TempFileName
    $dbName = $($f.BaseName).Replace(' ','_')
}
#endregion Download bacpac from LCS

## Restore New Database to SQL Server. Database name is AxDB_NEW
Write-Host "Restoring new Database" -ForegroundColor Yellow
#Trust SqlServer Certificate
Set-DbatoolsConfig -FullName 'sql.connection.trustcert' -Value $true -Register
#$f = Get-ChildItem C:\users\Admind9fca084f4\Downloads\AxDB_CTS-1005-BU2-202005051340.bak  #Please note that this file should be accessible from SQL server service account
If (-not (Test-DbaPath -SqlInstance localhost -Path $($f.FullName)))
{
    Write-Warning "Database file $($f.FullName) could not be found by SQL Server. Try to move it to C:\Temp"
    throw "Database file $($f.FullName) could not be found by SQL Server. Try to move it to C:\Temp"
}
$f | Unblock-File
$f | Restore-DbaDatabase -SqlInstance localhost -DatabaseName $dbName -ReplaceDbNameInFile -DestinationFileSuffix $dt -Verbose
Rename-DbaDatabase -SqlInstance localhost -Database $dbName -LogicalName "$($f.BaseName)_<FT>"

#Remove AxDB_Original database, if it exists
Write-Host "Removing old original database" -ForegroundColor Yellow
Remove-D365Database -DatabaseName AxDB_original

#Switch AxDB   AxDB_original <-- AxDB <-- AxDB_NEW
Write-Host "Switching databases" -ForegroundColor Yellow
Switch-D365ActiveDatabase -NewDatabaseName $dbName

## Enable SQL Change Tracking
Write-Host "Enabling SQL Change Tracking" -ForegroundColor Yellow

## ALTER DATABASE AxDB SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 6 DAYS, AUTO_CLEANUP = ON)
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "ALTER DATABASE AxDB SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 6 DAYS, AUTO_CLEANUP = ON)"

## Disable all current Batch Jobs
Write-Host "Disabling all current Batch Jobs" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "UPDATE BatchJob SET STATUS = 0 WHERE STATUS IN (1,2,5,7) --Set any waiting, executing, ready, or canceling batches to withhold."

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

## INFO: get Admin email address/tenant
Write-Host "Getting information about tenant and admin account from AxDB" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query "Select ID, Name, NetworkAlias from UserInfo where ID = 'Admin'" | FT

## Execute Database Sync
Write-Host "Executing Database Sync" -ForegroundColor Yellow
Invoke-D365DbSync -ShowOriginalProgress

## Start D365FO environment. Then open UI and refresh Data Entities.
Write-Host "Starting D365FO environment. Then open UI and refresh Data Entities." -ForegroundColor Yellow
Start-D365Environment | FT

## INFO: get User email address/tenant
$sqlGetUsers = @"
select ID, Name, NetworkAlias, NETWORKDOMAIN, Enable from userInfo
where NETWORKALIAS not like '%@contosoax7.onmicrosoft.com'
  and NETWORKALIAS not like '%@capintegration01.onmicrosoft.com'
  and NETWORKALIAS not like '%@devtesttie.ccsctp.net'
  and NETWORKALIAS not like '%@DAXMDSRunner.com'
  and NETWORKALIAS not like '%@dynamics.com'
  and NETWORKALIAS != ''
"@
Write-Host "Getting information about users from AxDB" -ForegroundColor Yellow
Invoke-DbaQuery -SqlInstance localhost -Database AxDB -Query $sqlGetUsers | FT
