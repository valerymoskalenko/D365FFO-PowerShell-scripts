$scriptPath = 'C:\Scripts'
$scriptName = 'Backup-AxDB.ps1'

### Please do not forget to update storageAccountName and storageAccountKey variable in the internal script below
$ErrorActionPreference = "Stop"
#region Installing d365fo.tools and dbatools <--
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Write-Host "Installing PowerShell modules d365fo.tools and dbatools" -ForegroundColor Yellow
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
$modules2Install = @('d365fo.tools', 'dbatools')
foreach ($module in  $modules2Install) {
    Write-Host "..working on module" $module -ForegroundColor Yellow
    if ($null -eq $(Get-Command -Module $module)) {
        Write-Host "....installing module" $module -ForegroundColor Gray
        Install-Module -Name $module -SkipPublisherCheck -Scope AllUsers
    }
    else {
        Write-Host "....updating module" $module -ForegroundColor Gray
        Update-Module -Name $module
    }
}
#endregion Installing d365fo.tools and dbatools -->

#region Saving script
Write-Host "Saving Script..." -ForegroundColor Yellow
$script = @'
    #variables
    $storageAccountName = 'sqlbackup'
    $storageAccountKey = 'voj/ugRS********************************************************a9cjMdcrA=='
    $SqlServer = [System.Environment]::MachineName
    $SqlTempFolder = 'D:\Backup'
    $SqlBackupFile = $SqlServer+'_'+$((Get-Date).ToString("yyyy-MM-dd_hhmmss"))+'.bak'
    $SqlBackupFileTrn = $SqlServer+'_'+$((Get-Date).ToString("yyyy-MM-dd_hhmmss"))+'.trn'
    $SqlBackupPath = Join-Path -Path $SqlTempFolder -ChildPath $SqlBackupFile
    $storageContainer = $SqlServer.ToLower()
    $DaysExcept1DayOfMonth = -90 #Days. Should be -30, -60, -90
    $DaysAll = -90 #Days. Should be -30, -60, -90

    #removing deprecated backup files from local drive
    New-Item -Path $SqlTempFolder -ItemType Directory -Force
    Write-Output "Delete old files from $SqlTempFolder"
    Get-ChildItem –Path $SqlTempFolder -Recurse | Where-Object {($_.CreationTime -lt (Get-Date).AddDays($DaysExcept1DayOfMonth)) -and ($_.CreationTime.Day -ne 1)} | Remove-Item -Recurse
    Get-ChildItem –Path $SqlTempFolder -Recurse | Where-Object {($_.CreationTime -lt (Get-Date).AddDays($DaysAll))} | Remove-Item -Recurse

    #Backup
    Write-Output "Backup to $SqlBackupPath"
    #Backup-SqlDatabase -Database AxDB -ServerInstance $SqlServer -BackupFile $SqlBackupPath -CompressionOption On -BackupAction Database
    Backup-DbaDatabase -SqlInstance $SqlServer -Database AxDB -Path $SqlTempFolder -FilePath $SqlBackupFileTrn -Type Log -CompressBackup #-Verbose
    Backup-DbaDatabase -SqlInstance $SqlServer -Database AxDB -Path $SqlTempFolder -FilePath $SqlBackupPath -Type Full -CompressBackup #-Verbose
    #Invoke-DbaDbShrink -SqlInstance $SqlServer -Database AxDB -FileType Log -Verbose

    #Creating container if it doesn't exist
    $ctx = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    Write-Output "Processing Azure Blob Container $storageContainer"
    $container = Get-AzureStorageContainer -Context $ctx | where {$_.Name -eq $storageContainer}
    if($container -eq $null)
    {
        Write-Output "..Creating new container $storageContainer"
        New-AzureStorageContainer -Context $ctx -Name $storageContainer
    }

    #Duplicate file check and uploading file to Azure Blob Storage
    Write-Output "Uploading file $SqlBackupPath to Azure Blob $storageAccountName"
    $BlobFiles = Get-AzureStorageBlob -Context $ctx -Container $storageContainer | where {$_.Name -eq $SqlBackupFile}
    if($BlobFiles -ne $null)
    {
        Write-Output "..Removing duplicate file from Azure $SqlBackupFile"
        $BlobFiles | Remove-AzureStorageBlob
    }
    Set-AzureStorageBlobContent -Context $ctx -Container $storageContainer -Blob $SqlBackupFile -File $SqlBackupPath
'@
$scriptFullPath = Join-Path $scriptPath $scriptName
New-Item -Path $scriptPath -ItemType Directory -Force
Set-Content -Value $script -Path $scriptFullPath -Force
#endregion Saving script

#region Running Script for the first time
Write-Host "Running Script for the first time..." -ForegroundColor Yellow
Invoke-Expression $scriptFullPath
#endregion Running Script for the first time

#region Registering the Script as Scheduled Task to run it Daily
Write-Host "Registering the Script as Scheduled Task to run it Daily..." -ForegroundColor Yellow
$atStartUp = New-JobTrigger -Daily -At "8:07 AM" -DaysInterval 1 -RandomDelay 00:40:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AXDBBackupDailyTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AXDBBackupDailyTask

#Write-Host "Registering the Script as Scheduled Task to run it at Startup..." -ForegroundColor Yellow
#$atStartUp = New-JobTrigger -AtStartup -RandomDelay 00:25:00
#$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
#Register-ScheduledJob -Name AXDBBackupStartupTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AXDBBackupStartupTask
#endregion Registering the Script as Scheduled Task to run it Daily
