# Rename-D365FFODevVM
Rename and adjust some settings new Dev VM (D365FFO, VHD-based VM)
Please find how-to use example below
```
Set-ExecutionPolicy Bypass -Scope Process -Force; 
$NewComputerName = 'FC-Val10PU24'
$disableMR = $true #Stop and Disable Management Reporter
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/valerymoskalenko/D365FFO-PowerShell-scripts/master/Rename-D365FFODevVM.ps1'))
```
# Rotate-D365FFODevVMCertificates.ps1
Check and rotate SSL Certificates on DEV VM (D365FFO, VHD-based VM)

# Get-D365FFODataEntity.ps1
Read Data Entity from D365FFO instance.
Use Azure Application and OAuth2 auth. Then get the data through OData protocol.
Please find more information here https://vmoskalenkoblog.wordpress.com/2018/06/25/reading-odata-from-dynamics-365/ 
Please find other examples here https://github.com/d365collaborative/d365fo.integrations 

# Add-D365FFOLicense2DP.ps1
You should use this script as inline PowerShell script on the Build Server. You should insert this step right after "Generate Packages"
Scan for a ISV License files in the folders K:\AosService\PackagesLocalDirectory\License
Then add license files to the Deployable Package.
So, you don't need to merge packages to install ISV license.
Please find details here https://www.yammer.com/dynamicsaxfeedbackprograms/#/Threads/show?threadId=86735357902848

# Invoke-D365FFOAxDBOptimization.ps1
Create a Scheduled task.
That executes OLA Index Optimization for all databases every day at 3:07 am and at every VM startup

# Invoke-D365FFOAxDBAutomaticBackup.ps1
Create a Scheduled task.
Executes AxDB backup and upload it to Azure Blob Storage every day at 8:07 am

# Invoke-D365FFOAxDBRestoreFromBAK.ps1
Restore AxDB database from BAK file on the new D365FO FnO environment.

# Invoke-D365FFOAxDBRestoreFromBACPAC.ps1
Restore AxDB database from BACPAC file on the new D365FO FnO environment.

# Invoke-D365FFOMovingData2OneDiskAndVMOptimization.ps1
Optimization for LCS-controlled Azure VM (Cloud-hosted environments only)
- Deploy new VM through LCS
   - Tier 1 only. Cloud-hosted on your Azure subscription
   - Set 2,4, or any disks
   - Set it to Premium SSD, Managed or Standard HDD
- Wait for deployment completion
- Add a new Standard SSD to your LCS Azure VM
- Open the Remote Desktop Connection and execute this PowerShell script. 
   This script does the following (automatic):
     - Detect new disk. Init and format it.
     - Add SQL service account to Administrators group and update Local Policy
     - Update Windows Defender rules
     - Set min and max RAM for SQL server
     - Move Temp DB to disk D: (temporary disk)
     - Set grow parameters for all Databases
     - Shrink all databases
     - Detach all databases
     - Copy all data to the new disk
     - Rename disks
     - Update default paths on SQL server
     - Schedule Index Optimization task
     - Delete old disks and storage pool 
- Review that script above completed successfully 
- Stop VM
- Detach old disks (2,4, or more)
- Start VM and do a smoke test on the environment
- Delete old detached disks from Azure Storage

Please note that this script has the known bug. It moves only pre-defined database-related files. Thus, you may loose fresh deployed database. 
However, on mew-created VMs it should be OK. In any case, please make sure that you have copied all database-related files (mdf and ldf)

# Test-D365FOLabelsFromCheckins.ps1
Find missing labels between Latest checked-in Label file and all versions of the same Label file.
It download all versions of Label file from DevOps. Store them. Then compare with the latest version in order to find any missing label Ids

# New-D365FFODeployment.ps1
Script to deploy a Deployable Package to DEV envrionment.
