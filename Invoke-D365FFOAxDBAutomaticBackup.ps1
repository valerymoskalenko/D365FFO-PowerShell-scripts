# https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Invoke-D365FFOAxDBAutomaticBackup.ps1
## Release notes
## v 2.0 2021-02-24
#    Updated to use Az module
#    Instead of storing Storage Account Key, it stores SAS token with limited permissions

$scriptPath = 'C:\Scripts'
$scriptName = 'Backup-AxDB.ps1'
$AzureSubscription = 'abdc6aca-a039-4e38-9dd5-adbd1a93f1a1'
$AzureResourceGroup = 'CTS-SQL-Backup'
$AzureStorageAccount = 'ctssqlbackup'
	
$ErrorActionPreference = "Stop"
	
#region Installing d365fo.tools and dbatools <--
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Write-Host "Installing PowerShell modules d365fo.tools and dbatools" -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
#Register-PSRepository -Default -Verbose
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
$modules2Install = @(<#'d365fo.tools', #>'dbatools')
foreach ($module in  $modules2Install) {
	    Write-Host "..working on module" $module -ForegroundColor Yellow
	    if ($null -eq $(Get-Command -Module $module)) {
	        Write-Host "....installing module" $module -ForegroundColor Gray
	        Install-Module -Name $module -SkipPublisherCheck -Scope AllUsers -AllowClobber
	    }
	    else {
	        Write-Host "....updating module" $module -ForegroundColor Gray
	        Update-Module -Name $module
	    }
}
#endregion Installing d365fo.tools and dbatools -->
	
#region Install Az module
Write-Host "Installing Az module. If you have issues here, please run it on PowerShell CLI - not ISE" -ForegroundColor Yellow
Install-Module -Name Az.Accounts,Az.Storage -AllowClobber -Scope CurrentUser
Import-Module -Name Az.Accounts,Az.Storage
#endregion Install Az module
	
#region prepare SAS token
Write-Host "Connecting to Azure..." -ForegroundColor Yellow
Connect-AzAccount
	
Write-Host "Getting Azure context to subscription $AzureSubscription ..." -ForegroundColor Yellow
Set-AzContext -Subscription $AzureSubscription -Verbose
	
$storageContainerName = $([System.Environment]::MachineName).ToLower()
Write-Host "Container name (Computer Name) is" $storageContainerName -ForegroundColor Yellow
	
Write-Host "Getting Azure Storage..." -ForegroundColor Yellow
$st = Get-AzStorageAccount -StorageAccountName $AzureStorageAccount -ResourceGroupName $AzureResourceGroup -Verbose
if ($null -eq $st) {throw "Please check Storage Account"}
	
Write-Host "Getting SAS link for 10 years ..." -ForegroundColor Yellow
$StorageSAStokenReadOnly = $st | New-AzStorageAccountSASToken -Service Blob -ResourceType Object -Permission "w" -ExpiryTime $((Get-Date).AddYears(10))
	
$stContainer = $st | Get-AzStorageContainer | where {$_.Name -eq $storageContainerName}
if ($null -eq $stContainer) {
	Write-Host "Creating Container" $storageContainerName -ForegroundColor Yellow
	$st | New-AzStorageContainer -Name $storageContainerName
}
#endregion
	
#region Saving script
Write-Host "Saving Script..." -ForegroundColor Yellow
$script = @'
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
	    
	#Uploading backup to Azure Blob Storage
	    Write-Output "Uploading file $SqlBackupPath to Azure Blob $storageAccountName"
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	    $ctx = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $StorageSAStoken
	Set-AzStorageBlobContent -Context $ctx -Container $storageContainer -Blob $SqlBackupFile -File $SqlBackupPath -ConcurrentTaskCount 10 -Force
	
'@
$StorageSAStoken = '$StorageSAStoken'
$storageAccountName = '$storageAccountName'
$scriptCreds = @"
	$storageAccountName = '$AzureStorageAccount'
	$StorageSAStoken = '$StorageSAStokenReadOnly'
"@
	
$scriptFullPath = Join-Path $scriptPath $scriptName
New-Item -Path $scriptPath -ItemType Directory -Force
Set-Content -Value $scriptCreds -Path $scriptFullPath -Force
Add-Content -Value $script -Path $scriptFullPath -Force
#endregion Saving script
	
#region Running Script for the first time
Write-Host "Running Script for the first time..." -ForegroundColor Yellow
Invoke-Expression $scriptFullPath
#endregion Running Script for the first time
	
#region Registering the Script as Scheduled Task to run it Daily
#Write-Host "Registering the Script as Scheduled Task to run it Daily..." -ForegroundColor Yellow
$atStartUp = New-JobTrigger -Daily -At "8:07 AM" -DaysInterval 1 -RandomDelay 00:40:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AxDBBackupDailyTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AxDBBackupDailyTask
	
Write-Host "Registering the Script as Scheduled Task to run it at Startup..." -ForegroundColor Yellow
$atStartUp = New-JobTrigger -AtStartup -RandomDelay 00:25:00
$option = New-ScheduledJobOption -StartIfIdle -MultipleInstancePolicy IgnoreNew
Register-ScheduledJob -Name AxDBBackupStartupTask -Trigger $atStartUp -FilePath $scriptFullPath -ScheduledJobOption $option
#Unregister-ScheduledJob -Name AxDBBackupStartupTask
#endregion Registering the Script as Scheduled Task to run it Daily
	
#Azure log out. Answer yes to clean your credentials
Write-Host "Disconnecting and cleaning up any credentials. Please confirm it. If it generates an error then retry" -ForegroundColor Yellow
Disconnect-AzAccount
Clear-AzContext -Scope CurrentUser

#Fixing AzureRM and Az modules incompatibility for d365fo.tools
install-module AzureRM.profile -AllowClobber
install-module Azure.Storage -AllowClobber


