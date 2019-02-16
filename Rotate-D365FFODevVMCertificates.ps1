Write-Output "Rotating Certificates on OneBox VM"
Set-Location -Path "cert:\LocalMachine\My"
foreach($OldCert in Get-ChildItem -path Cert:\LocalMachine\My | Where {$_.NotAfter -lt $(get-date).AddMonths(2)})
{
    $OldCert
    $NewCert = New-SelfSignedCertificate -CloneCert $OldCert -NotAfter (Get-Date).AddMonths(999)
 
    (Get-Content 'C:\AOSService\webroot\web.config').Replace($OldCert.Thumbprint, $NewCert.Thumbprint) | Set-Content 'C:\AOSService\webroot\web.config'
    (Get-Content 'C:\AOSService\webroot\wif.config').Replace($OldCert.Thumbprint, $NewCert.Thumbprint) | Set-Content 'C:\AOSService\webroot\wif.config'
    (Get-Content 'C:\AOSService\webroot\wif.services.config').Replace($OldCert.Thumbprint, $NewCert.Thumbprint) | Set-Content 'C:\AOSService\webroot\wif.services.config'
}
Write-Output "IIS Reset..."
iisreset 
