<#
Scan for a ISV License files in the folders K:\AosService\PackagesLocalDirectory\License
Then add license files to the Deployable Package.
You should use this script as inline PowerShell script on the Build Server.

I have added new step on the BUILD server. It's a PowerShell script. Inline. 
It scan the metadata folder, where you keep the code, for a folder "License" 
and copy all files from where to AOSService\Scripts\License path inside the zip package.
You should insert this step right after "Generate Packages"
#>

[string]$MetaData = "K:\AosService\PackagesLocalDirectory"
[string]$DPFile = "$(Agent.BuildDirectory)\Packages\AXDeployableRuntime*.zip"
[string]$TempPath = "D:\TEMP"

$LicenseTemp = Join-Path -Path $TempPath -ChildPath "AOSService"
$LicensePath = Join-Path -Path $LicenseTemp -ChildPath "Scripts\License"

Write-Host "Looking for a licenses folder at" $MetaData -ForegroundColor Yellow
New-Item -Path $TempPath -ItemType Directory -Force
New-Item -Path $LicensePath -ItemType Directory -Force
$LicenseFolders = Get-ChildItem -Path $MetaData -Include "License" -Recurse -Depth 6
foreach($LicenseFolder in $LicenseFolders)
{
    Write-Host "Copy the license from folder" $LicenseFolder.FullName -ForegroundColor Yellow
    $LicenseFiles = Get-ChildItem -Path $LicenseFolder
    foreach($file in $LicenseFiles)
    {
        Write-Host "..Copy the license from file" $file.FullName -ForegroundColor Yellow
        Copy-Item -path $($file.FullName) -Destination $LicensePath -Force -Recurse -Verbose
    }
}

foreach($zipFile in Get-ChildItem -Path $DPFile)
{
    [string]$zipFileFullName = $zipFile.FullName
    Write-Host "Working on" $zipFileFullName -ForegroundColor Yellow
    C:\DynamicsTools\7za.exe a -r -y -mx3 -bb3 "$zipFileFullName" "$LicenseTemp"
}
