$tenantDomain = 'contoso.com' 
[uri]$url =  'https://contoso-integration-435634563456devaos.cloudax.dynamics.com'
$ApplicationClientId = '699ee32d-a000-0000-0000-445a3dc7f0fb' 
$ApplicationClientSecretKey = '+mоji458h45hoerh89eh8w4589tfn49t8hwethw547gtc='; 

$DataEntity = 'LegalEntities'  #'LegalEntities' #'Customers'#'LegalEntities'

$ErrorActionPreference = 'Stop'
Write-Host "Authorization..." -ForegroundColor Yellow
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web
    #Cloud
    $absoluteURL = [System.Web.HttpUtility]::UrlEncodeUnicode($url.AbsoluteUri.Remove($url.AbsoluteUri.Length-1,1));
    $encodedURL = [System.Web.HttpUtility]::UrlEncodeUnicode($url.AbsoluteUri.Remove($url.AbsoluteUri.Length-1,1))
    $encodedApplicationClientId = [System.Web.HttpUtility]::UrlEncodeUnicode($ApplicationClientId)
    $encodedApplicationClientSecretKey = [System.Web.HttpUtility]::UrlEncodeUnicode($ApplicationClientSecretKey)

    $Body =@"
    resource=$encodedURL&client_id=$encodedApplicationClientId&client_secret=$encodedApplicationClientSecretKey&grant_type=client_credentials
"@
$login = $null
$Body
$login = Invoke-RestMethod -Method Post -Uri "https://login.windows.net/$tenantDomain/oauth2/token" -Body $Body -ContentType 'application/x-www-form-urlencoded' -Verbose

$Bearer = $null
[string]$Bearer = $login.access_token  #.ToString()
 
Write-Host "Getting data..." -ForegroundColor Yellow
 
$headers = @{
    "OData-Version" = "4.0"
    "OData-MaxVersion" = "4.0"
    "Accept" = "application/json;odata.metadata=minimal"
    "Accept-Charset" = "UTF-8"
    "Authorization" = "Bearer $Bearer"
    "Host" = "$($url.Host)"
}
 
[System.UriBuilder] $ListRecordsURL = $url
$ListRecordsURL.Path = "/data/$DataEntity"
#$ListRecordsURL.Query = '$filter dataAreaId eq ''MTA''';
#$ListRecordsURL.Query += '&$cross-company=true' # '$skip=3&$top=2'
#$ListRecordsURL.Query += '$skip=3&$top=2'


$resultREST=$null
$resultREST = Invoke-RestMethod -Method Get -Uri $ListRecordsURL.Uri.AbsoluteUri `
    -Headers $headers -ContentType 'application/json;odata.metadata=minimal' -Verbose
 
#Write-Host "Plain results..." -ForegroundColor Yellow
#$resultREST.value 

Write-Host "Results..." -ForegroundColor Yellow
$resultREST.value | Select LegalEntityId, Name, FullPrimaryAddress | Format-Table -AutoSize -Wrap 
#$resultREST.value | select DataAreaID, AccountID, AccountStructure | Format-Table -AutoSize -Wrap 

$tempFile = $env:TEMP + 'temp.txt'
$resultREST.value | ConvertTo-Json -Depth 5  | Set-Content -Path $tempFile -Force
notepad $tempFile
