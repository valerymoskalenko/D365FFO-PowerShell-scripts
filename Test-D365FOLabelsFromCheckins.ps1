#https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Test-D365FOLabelsFromCheckins.ps1
Set-StrictMode -Version Latest
Set-Location -Path C:\Scripts

[string]$DevOpsURL = 'https://contoso.visualstudio.com'   #https://dev.azure.com/Fleet-Complete/FLEX
[string]$DevOpsProject = 'Contoso-Project'
[string]$DevOpsUsername = 'valery.moskalenko@contoso.com'
[string]$DevOpsPassword = 'iax45*************************56fuq'
[string]$DevOpsLabelFile = '$/Contoso-Project/Trunk/DEV/Metadata/ContosoCustomization/Contoso Customization/AxLabelFile/LabelResources/en-US/Contoso.en-US.label.txt'
[string]$tempFile = Join-Path -Path $env:TEMP -ChildPath 'temp.txt'

$uriChangesetsList = "$($DevOpsURL)/$($DevOpsProject)/_apis/tfvc/changesets?searchCriteria.itemPath=$DevOpsLabelFile&api-version=5.0"

$pair = "${DevOpsUsername}:${DevOpsPassword}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)

$headers = @{
    "Accept" = "application/json"
    "Accept-Charset" = "UTF-8"
    "Authorization"= "Basic $base64"
}

$wcChangesetsList = Invoke-WebRequest -Uri $uriChangesetsList -Method Get -Headers $headers -Verbose
$jsonChangesetsList = $wcChangesetsList.Content | ConvertFrom-Json
$jsonChangesetsList.value | Select changesetId, createdDate, comment | FT

$headersChangeset = @{
    "Accept" = "text/plain"
    "Accept-Charset" = "UTF-8"
    "Authorization"= "Basic $base64"
}

$AllLabels = @{}  #init hash table with all Labels

foreach ($changeset in $jsonChangesetsList.value)
{
    [string]$changesetId = $changeset.changesetId
    Write-Host "Working on Changeset" $changesetId "by" $changeset.author.displayName $changeset.comment -ForegroundColor Yellow

    [string]$LabelFileChangeset = Join-Path -Path $env:TEMP -ChildPath "LabelFile_$changesetId.txt"
    if (Test-Path $LabelFileChangeset) {Remove-Item -Path $LabelFileChangeset -Force}

    $uriLabelFileChangeset = "$($DevOpsURL)/$($DevOpsProject)/_apis/tfvc/items/$DevOpsLabelFile" + "?versionType=Changeset&version=$changesetId"
    $wcLabelFileChangeset = Invoke-WebRequest -Uri $uriLabelFileChangeset -Headers $headersChangeset # -OutFile $LabelFileChangeset
    
    #Process Label File
    $wcLabelFileChangeset.Content | Set-Content -Path $LabelFileChangeset
    foreach($row in Get-Content -Path $LabelFileChangeset| Select-String -Pattern '^(?! ;).*=.*' )
    {
        $labelId = '';
        $labelText = '';
        $labelId, $labelText = $row -split '='
        If (-not $AllLabels.ContainsKey($labelId))
        {
            $AllLabels.Add($labelId, $labelText); #insert
        } <#else {
            $AllLabels[$labelId] = $labelText; #update
        }#>
    }
}

#Get latest changeset
[string]$LabelFileLatest = Join-Path -Path $env:TEMP -ChildPath "LabelFile_LATEST.txt"
if (Test-Path $LabelFileLatest) {Remove-Item -Path $LabelFileLatest -Force}
$uriLabelFileLatest = "$($DevOpsURL)/$($DevOpsProject)/_apis/tfvc/items/$DevOpsLabelFile" 
$wcLabelFilelatest = Invoke-WebRequest -Uri $uriLabelFileLatest -Headers $headersChangeset # -OutFile $LabelFileChangeset
$wcLabelFilelatest.Content | Set-Content -Path $LabelFileLatest

#Compare Label File
Write-Host "Compare labels: All labels vs Latest Labels:" -ForegroundColor Green
$LatestLabels = @{}  #init hash table with Latest Labels
foreach($row in Get-Content -Path $LabelFileLatest| Select-String -Pattern '^(?! ;).*=.*' )
{
    $labelId = '';
    $labelText = '';
    $labelId, $labelText = $row -split '='
    If (-not $LatestLabels.ContainsKey($labelId))
    {
        $LatestLabels.Add($labelId, $labelText); #insert
    } else {
        $LatestLabels[$labelId] = $labelText; #update
        Write-Host "Duplicate label Id:" $labelId "? in Latest Labels" -ForegroundColor Red
    }

    If (-not $AllLabels.ContainsKey($labelId))
    {
        Write-Host "Missing label in All Labels: $labelId=$($LatestLabels[$labelId])" -ForegroundColor Red
    }
}

foreach($label in $AllLabels.Keys)
{
    if (-not $LatestLabels.ContainsKey($label))
    {
        Write-Host "Missing label in Latest Labels: $label=$($AllLabels[$label])" -ForegroundColor Red
        #Write-host "..with text:" $AllLabels[$label]
    }

}
