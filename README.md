# D365FFO-RenameDevVM
Rename and adjust some settings new Dev VM (D365FFO, VHD-based VM)
Please find how-to use example below
```
Set-ExecutionPolicy Bypass -Scope Process -Force; 
$NewComputerName = 'FC-Val10PU24'
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
That executes OLA Index Optimization for all databases every day at 3:07 am

# Test-D365FOLabelsFromCheckins.ps1
Find missing labels between Latest checked-in Label file and all versions of the same Label file.
It download all versions of Label file from DevOps. Store them. Then compare with the latest version in order to find any missing label Ids
