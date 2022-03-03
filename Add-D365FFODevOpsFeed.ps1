$DevOpsSessionParameters = @{
        Instance            = 'https://dev.azure.com/'
        Collection          = 'Contoso'
        Project             = 'Dynamics365Dev'
        Account             = 'dmin@contoso.com'
        PersonalAccessToken = 'taoaaaaaaaaaaaaaaaaPATbbbbbbbbbbbbbbbbbbbbbb5ga'
    }

$DevOpsFeedName = "D365FO_10.0.17"  #No whitespaces allowed #Please create it manually as Project scoped
$TempFolder = 'd:\Temp\' + $DevOpsFeedName
$SASLinks = @( #Copy from LCS SAS links here in any order. Please note starting from 10.0.18, it should 4 links.
  'https://uswedpl1catalog.blob.core.windows.net/product-ax7productname/84ea2b7f-13d5-4b74-855c-e892fab1d68e/AX7ProductName-12-27-743473ab-8e79-44f7-8d6b-f32ac256d585-84ea2b7f-13d5-4b74-855c-e892fab1d68e?sv=2015-12-11&sr=b&sig=U%2FF2rhmmU6%2BjTaw6DoHRppG1NtN6oU1Ka69X2Pn4ugM%3D&se=2021-04-07T08%3A33%3A15Z&sp=r',
  'https://uswedpl1catalog.blob.core.windows.net/product-ax7productname/11a66aad-e6c4-4113-ba9f-e207d95d3fa5/AX7ProductName-12-27-743473ab-8e79-44f7-8d6b-f32ac256d585-11a66aad-e6c4-4113-ba9f-e207d95d3fa5?sv=2015-12-11&sr=b&sig=X9dMXJbomxZ%2BiSus5h10cJ3JKGcyurRJa%2Bskh9wI3L8%3D&se=2021-04-07T08%3A33%3A40Z&sp=r',
  'https://uswedpl1catalog.blob.core.windows.net/product-ax7productname/ac3f8f34-941d-421c-9b02-9bd859b44b4c/AX7ProductName-12-27-743473ab-8e79-44f7-8d6b-f32ac256d585-ac3f8f34-941d-421c-9b02-9bd859b44b4c?sv=2015-12-11&sr=b&sig=y8%2BpBU%2FhFid7PVYOlkJwM2H8uEQAr5DZxruS%2BV%2B4IQU%3D&se=2021-04-07T08%3A34%3A03Z&sp=r',
  ''
)
$TFS_FolderWithBuildProject = 'C:\TFS_ALL\Build\BuildProject\BuildProject\'
$TFS_ProjectFileName = 'BuildProject.rnrproj'

$ErrorActionPreference = "Stop"
#make sure that TEMP folder is exists
(New-Item -Path $TempFolder -ItemType Directory -Force).FullName
#region Installing powershell modules <--
# This is requried by Find-Module, by doing it beforehand we remove some warning messages
Write-Host "Installing PowerShell modules d365fo.tools and AzurePipelinesPS" -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
#[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; 
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers
#Register-PSRepository -Default -Verbose
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
#Install-Module -Name PackageManagement -Force -MinimumVersion 1.4.6 -Scope CurrentUser -AllowClobber -Repository PSGallery

$modules2Install = @('d365fo.tools')
foreach ($module in $modules2Install) {
    Write-Host "..working on module" $module -ForegroundColor Yellow
    if ($null -eq $(Get-Command -Module $module)) {
        Write-Host "....installing module" $module -ForegroundColor Gray
        Install-Module -Name $module -SkipPublisherCheck -Scope AllUsers -Repository PSGallery
    }
    else {
        Write-Host "....updating module" $module -ForegroundColor Gray
        Update-Module -Name $module
    }
}
#endregion Installing powershell modules -->
Invoke-D365InstallAzCopy -Verbose
Invoke-D365InstallNuget -Verbose

cd "C:\Temp\d365fo.tools\NuGet"
$SoourcePath = "https://pkgs.dev.azure.com/$($DevOpsSessionParameters.Collection)/$($DevOpsSessionParameters.Project)/_packaging/$DevOpsFeedName/nuget/v3/index.json"
Write-Host "Uploading NuGet packages to" $SoourcePath -ForegroundColor Yellow
.\nuget sources add -Name $DevOpsFeedName -Source $SoourcePath -username $DevOpsSessionParameters.Account -password $DevOpsSessionParameters.PersonalAccessToken

<# if you have error: "The name specified has already been added to the list of available package sources. Provide a unique name."
C:\Temp\d365fo.tools\nuget>nuget.exe sources list
Registered Sources:
  1.  nuget.org [Enabled]
      https://api.nuget.org/v3/index.json
  2.  D365FO_10.0.17 [Enabled]
      https://pkgs.dev.azure.com//_packaging/D365FO_10.0.17/nuget/v3/index.json
  3.  Microsoft Visual Studio Offline Packages [Enabled]
      C:\Program Files (x86)\Microsoft SDKs\NuGetPackages\

C:\Temp\d365fo.tools\nuget>nuget.exe sources remove -name D365FO_10.0.17
Package source with Name: D365FO_10.0.17 removed successfully.#>

$contentNuGetPackagesConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<packages>
"@
$nl = [Environment]::NewLine

[int]$counter = 1
ForEach($SASLink in $SASLinks)
{
    Write-Host "Working on file #" $counter -ForegroundColor Yellow
    $TempFolderDownload = Join-Path $TempFolder "Download-$counter"
    New-Item -Path $TempFolderDownload -ItemType Directory -Force
    $TempFileName = Join-path $TempFolderDownload "File-$counter.zip"
    
#Download NuGet package from LCS
    Write-Host "..Downloading file " $TempFileName -ForegroundColor Yellow
    Invoke-D365AzCopyTransfer -SourceUri $SASLink -DestinationUri $TempFileName -ShowOriginalProgress
    #make sure that the SAS link is not expired

#Upload NuGet package to Azure DevOps feed
    Write-Host "..Uploading file " $TempFileName -ForegroundColor Yellow
    Invoke-D365AzureDevOpsNugetPush -Path $TempFileName -source $DevOpsFeedName -ShowOriginalProgress
    $counter = $counter + 1

#Get details about NuGet package
    $ZipStream = [io.compression.zipfile]::OpenRead($TempFileName)
    $ZipItem = $ZipStream.GetEntry('_rels/.rels')
    $ItemReader = New-Object System.IO.StreamReader($ZipItem.Open())
    [xml]$rels = $ItemReader.ReadToEnd()
    $TargetZipFileName = $($rels.Relationships.Relationship | where {$_.Type -eq 'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'}).Target
    $ZipItem = $ZipStream.GetEntry($TargetZipFileName.Substring(1,$TargetZipFileName.Length-1))
    $ItemReader = New-Object System.IO.StreamReader($ZipItem.Open())
    [xml]$target = $ItemReader.ReadToEnd()
    $contentNuGetPackagesConfig = $contentNuGetPackagesConfig + $nl + "  <package id=`"$($target.coreProperties.identifier)`" version=`"$($target.coreProperties.version)`" targetFramework=`"net40`" />"
    Write-Host "..File is" "<package id=`"$($target.coreProperties.identifier)`" version=`"$($target.coreProperties.version)`"" -ForegroundColor Yellow

}
$contentNuGetPackagesConfig = $contentNuGetPackagesConfig + $nl + "</packages>" + $nl

#Creating a new folder in the TSF folder for the Build project/solution
$TFS_Folder = Join-Path -Path $TFS_FolderWithBuildProject -ChildPath $DevOpsFeedName
(New-Item -Path $TFS_Folder -ItemType Directory -Force).FullName

$contentNuGetConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="$DevOpsFeedName" value="$SoourcePath" />
  </packageSources>
</configuration>
"@
Write-Host "Saving nuget.config file in" $TFS_Folder -ForegroundColor Yellow
$contentNuGetConfig | Set-Content -Path $(Join-Path -Path $TFS_Folder -ChildPath 'nuget.config') -Force

Write-Host "Saving packages.config file in" $TFS_Folder -ForegroundColor Yellow
$contentNuGetPackagesConfig | Set-Content -Path $(Join-Path -Path $TFS_Folder -ChildPath 'packages.config') -Force

#Removing NuGet Source added above
Write-Host "Removing NuGet source" $DevOpsFeedName -ForegroundColor Yellow
cd "C:\Temp\d365fo.tools\NuGet"
.\nuget sources remove -Name $DevOpsFeedName
#clear nuget cache
#nuget locals all -clear



#Optional
#Updating project file
$TFS_ProjectFile = Join-Path -Path $TFS_FolderWithBuildProject -ChildPath $TFS_ProjectFileName
Write-Host "Updatiing project file" $TFS_ProjectFile -ForegroundColor Yellow
[xml]$TFS_ProjectContent = Get-Content -Path $TFS_ProjectFile
if ($null -eq $TFS_ProjectContent.Project.ItemGroup.Folder)
{
    Write-Host "There is no folders added to the project. Skipping it. Please add it manually." -ForegroundColor Yellow
}
else 
{
    $id = $TFS_ProjectContent.Project.ItemGroup.Folder[0].Clone();
    $id.Attributes[0].Value = $DevOpsFeedName
    $TFS_ProjectContent.Project.ItemGroup.AppendChild($id)
    $TFS_ProjectContent.Save($TFS_ProjectFile)        
}

Write-Host "Please do not forget to add folder" $TFS_Folder "to the code repository"
Write-Host "Then check your pending changes"
