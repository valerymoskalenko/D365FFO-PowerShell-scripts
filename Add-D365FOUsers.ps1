# https://github.com/valerymoskalenko/D365FFO-PowerShell-scripts/blob/master/Add-D365FOUsers.ps1
$AccountList = @("john.doe@ciellos.com", 
                "Maria.Ivanova@ciellos.com", 
                "test@ciellos.com"         
      ) #Add more emails to the list
$DefaultDataAreaId = 'USMF' #Update default company if it necessary

Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module d365fo.tools -Force -ErrorAction SilentlyContinue
foreach($account in $AccountList)
{
    Remove-D365User -Email $account -ErrorAction SilentlyContinue
    
    Write-Host "Working on account email is" $account -ForegroundColor Yellow
    $UserIdTmp = $account.Split("@")[0]
    $UserId = $UserIdTmp.Split(".")[0].Substring(0,1) + "." + $UserIdTmp.Split(".")[1]
    
    $UserName = $UserIdTmp.Replace("."," ")
    $UserName = (Get-Culture).TextInfo.ToTitleCase($UserName)
    
    Write-Host "   Id  =" $UserId -ForegroundColor Yellow
    Write-Host "   Name=" $UserName -ForegroundColor Yellow
    Import-D365ExternalUser -Id $UserId -Name $UserName -Email $account -Company $DefaultDataAreaId
}
