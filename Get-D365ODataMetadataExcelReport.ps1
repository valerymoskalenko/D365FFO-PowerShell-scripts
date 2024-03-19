Import-module -Name d365fo.integrations
Import-Module -Name ImportExcel

#Configure D365 OData
#Add-D365ODataConfig -Name Test -Tenant ciellos.com -url https://usnconeboxax1aos.cloud.onebox.dynamics.com -ClientId 37ba221e-0000-0000-0000-19a5ecfaafa7 -ClientSecret LLm8***************************a2F
# Test D365 OData
#$entity = Get-D365ODataPublicEntity -EntityName CustomersV3

$ErrorActionPreference = "Stop"

$EntitiesToProcess = @(
"SalesInvoiceHeadersV2","SalesInvoiceLines",
"SalesOrderHeadersV2","SalesOrderLines",
"CustomersV3",
#"VendorsV3","EmployeesV2",
#"TradeAgreementJournalNames","OpenTradeAgreementJournalHeadersV2","SalesPriceAgreements",
#"MultilineDiscountCustomerGroups","LineDiscountProductGroups","LineDiscountCustomerGroups",
"PriceCustomerGroups",
"DeliveryTerms","PaymentTerms","CustomerGroups","ProductGroups"
"SellableReleasedProducts","ReleasedDistinctProductsV2","ProductTranslations",
"ProductCategories","ProductCategoryHierarchies",

"DimAttributeInventItemGroups","DimAttributeCustGroups","DimAttributeCustTables","DimAttributeFinancialTags","DimAttributeHcmWorkers",
#"DimAttributeProjTables",
"SalesOrderOriginCodes","SalesOrderPools",
"BusinessDocumentMarkupTransactions"
)

##

[string]$getODataTop = '$top=30'
$df = Get-Date -Format "yyyy-MM-dd hhmmssffff"
$ExcelFile = "C:\Temp\DataEntitiesPS_"+$df+".xlsx"
[uri]$uri = ''

#Preparing for the GetLabels 
[uri]$uriHost = $(Get-D365ODataConfig).url
$headers = @{
    "Accept" = "application/xml"
    "Accept-Charset" = "UTF-8"
    "Authorization" = Get-D365ODataToken
    "Host" = $uriHost.Host
}

#Get Label string by Label Id
function Get-FSCLabel {
    param (
        #[Parameter(Mandatory=$true)]
        [string]$LabelId,
        [string]$LanguageId = 'en-us'
    )
    
    [string]$labelValue = "";

    if (($LabelId.Length -gt 1) -and ($LabelId.Contains('@')))
    {
        Write-Host "  Working on Label $LabelId ..." -ForegroundColor Gray
        [uri]$uri = $uriHost.AbsoluteUri + "metadata/Labels(Id='"+ $LabelId +"',Language='"+$LanguageId+"')";
        $resultREST = Invoke-RestMethod -Method Get -Uri $uri.AbsoluteUri -Headers $headers -ContentType 'application/json; charset=utf-8' #-Verbose
        $labelValue = $resultREST.Value
    }
    else
    {
        #Return Label Id as is -- do not process
        $labelValue = $LabelId
    }

    return $labelValue
}


# Loop through the Data Entities
$entitesHeaders = [System.Collections.ArrayList]@()
$xl = $entitesHeaders | Export-Excel -Path $ExcelFile -PassThru -WorksheetName "Header"
foreach($entityName in $EntitiesToProcess)
{
    # Get OData metadata
    Write-Host "Working on entity $entityName ..."-ForegroundColor Yellow
    $entityProperties = Get-D365ODataPublicEntity -EntityName $entityName -EnableException -Verbose

    [string]$labelValue = Get-FSCLabel -LabelId $entityProperties.LabelId


    #Add line to the Headers 
    $entitesHeaders += [pscustomobject]@{"Name" = $entityProperties.Name; "Entity Set Name" = $entityProperties.EntitySetName; "Description" = $labelValue; "Is Read Only" = $entityProperties.IsReadOnly; "Configuration Enabled" = $entityProperties.ConfigurationEnabled}

    #Loop for the Labels
    foreach($singleProperty in $entityProperties.Properties)
    {
        $singleProperty.LabelId = Get-FSCLabel -LabelId $singleProperty.LabelId
    }

    $dataExample = Get-D365ODataEntityData -EntityName $entityName -ODataQuery $getODataTop -Verbose

    #Export to Excel
    [string]$xlWorksheetName = $entityProperties.Name[0..30] -join ""
    $xl = $entityProperties.Properties | Export-Excel -ExcelPackage $xl -WorksheetName $xlWorksheetName -TableName $($entityProperties.Name+"_Fields") -AutoSize -PassThru
    
    $propertiesCount = $entityProperties.Properties.Count + 4
    if ($dataExample -ne $null)
    {
        $xl = $dataExample| Export-Excel -ExcelPackage $xl -WorksheetName $xlWorksheetName -TableName $($entityProperties.Name+"_Data") -StartRow $propertiesCount -TableStyle Medium17 -MaxAutoSizeRows 60 -NoNumberConversion * -PassThru #-AutoSize
    }
    #$xl = Set-ExcelColumn -ExcelPackage $xl -WorksheetName $xlWorksheetName -Column 1 -Width 40 -PassThru
}


#Generate Header sheet
$xl = $entitesHeaders | Export-Excel -ExcelPackage $xl -WorksheetName "Header" -TableName "Header" -AutoSize -PassThru

#Save Excel
Close-ExcelPackage $xl -Show
