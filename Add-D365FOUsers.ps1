# https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Add-D365FOUsers.ps1
$AccountList = @("john.doe@ciellos.com", "Maria.Ivanova@ciellos.com", "test@ciellos.com") #Add more emails to the list
$DefaultDataAreaId = 'USMF' #Update default company if it necessary

foreach($account in $AccountList)
{
    Write-Host "Working on account email is" $account -ForegroundColor Yellow
    $UserId = $account.Split("@")[0]
    $UserName = $UserId.Replace("."," ")
    $UserName = (Get-Culture).TextInfo.ToTitleCase($UserName)

    Write-Host "   Id  =" $UserId -ForegroundColor Yellow
    Write-Host "   Name=" $UserName -ForegroundColor Yellow

    Import-D365ExternalUser -Id $UserId -Name $UserName -Email $account -Company $DefaultDataAreaId
    #Remove-D365User -Email $account
}
