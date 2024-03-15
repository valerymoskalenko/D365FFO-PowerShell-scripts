Import-module -Name d365fo.integrations
Import-Module -Name ImportExcel

#Configure D365 OData
#Add-D365ODataConfig -Name Test -Tenant ciellos.com -url https://usnconeboxax1aos.cloud.onebox.dynamics.com -ClientId 37ba221e-0000-0000-0000-19a5ecfaafa7 -ClientSecret LLm8***************************a2F
# Test D365 OData
#$entity = Get-D365ODataPublicEntity -EntityName CustomersV3

$ErrorActionPreference = "Stop"

$EntitiesToProcess = @(
"SalesInvoiceHeadersV2","SalesInvoiceLines","SalesOrderHeadersV2","SalesOrderLines",
#"EmployeesV2","CustomersV3","VendorsV3",
#"TradeAgreementJournalNames","OpenTradeAgreementJournalHeadersV2","SalesPriceAgreements",
#"MultilineDiscountCustomerGroups","LineDiscountProductGroups","LineDiscountCustomerGroups","PriceCustomerGroups",
"DeliveryTerms","PaymentTerms","CustomerGroups",
#"SellableReleasedProducts","ReleasedDistinctProductsV2","ProductTranslations",
#"ProductCategories","ProductCategoryHierarchies",

"DimAttributeInventItemGroups","DimAttributeCustGroups","DimAttributeCustTables","DimAttributeFinancialTags","DimAttributeHcmWorkers","DimAttributeProjTables",
"SalesOrderOriginCodes","SalesOrderPools"
)

$df = Get-Date -Format "yyyy-MM-dd hhmmssffff"
$ExcelFile = "C:\Temp\DataEntitiesPS"+$df+".xlsx"
[uri]$uri = ''

#Preparing for the GetLabels 
[uri]$uriHost = $(Get-D365ODataConfig).url
$headers = @{
    "Accept" = "application/xml"
    "Accept-Charset" = "UTF-8"
    "Authorization" = Get-D365ODataToken
    "Host" = $uriHost.Host
}

# Loop through the Data Entities
$entitesHeaders = [System.Collections.ArrayList]@()
$xl = $entitesHeaders | Export-Excel -Path $ExcelFile -PassThru -WorksheetName "Header"
foreach($entityName in $EntitiesToProcess)
{
    # Get OData metadata
    Write-Host "Working on entity $entityName ..."-ForegroundColor Yellow
    $entityProperties = Get-D365ODataPublicEntity -EntityName $entityName -EnableException -Verbose

        #Copy-paste from the loop below.TODO - write function
        [string]$label = $entityProperties.LabelId;
        [string]$labelValue = "";

        if (($label.Length -gt 1) -and ($label.Contains('@')))
        {
            Write-Host "  Working on Label $label ..." -ForegroundColor Gray
            [uri]$uri = $uriHost.AbsoluteUri + "metadata/Labels(Id='"+ $label +"',Language='en-us')";
            $resultREST = Invoke-RestMethod -Method Get -Uri $uri.AbsoluteUri -Headers $headers -ContentType 'application/json; charset=utf-8' #-Verbose
            $labelValue = $resultREST.Value

            #$singleProperty.LabelId = $labelValue;
        }

    #Add a line to the Headers 
    $entitesHeaders += [pscustomobject]@{"Name" = $entityProperties.Name; "Entity Set Name" = $entityProperties.EntitySetName; "Description" = $labelValue; "Is Read Only" = $entityProperties.IsReadOnly; "Configuration Enabled" = $entityProperties.ConfigurationEnabled}

    #Loop for the Labels
    foreach($singleProperty in $entityProperties.Properties)
    {
        [string]$label = $singleProperty.LabelId;
        [string]$labelValue = "";

        if (($label.Length -gt 1) -and ($label.Contains('@')))
        {
            Write-Host "  Working on Label $label ..." -ForegroundColor Gray
            [uri]$uri = $uriHost.AbsoluteUri + "/metadata/Labels(Id='"+ $label +"',Language='en-us')";
            $resultREST = Invoke-RestMethod -Method Get -Uri $uri.AbsoluteUri -Headers $headers -ContentType 'application/json; charset=utf-8' #-Verbose
            $labelValue = $resultREST.Value

            $singleProperty.LabelId = $labelValue;
        }
    }

    $dataExample = Get-D365ODataEntityData -EntityName $entityName -ODataQuery '$top=50'

    #Export to Excel
    $xl = $entityProperties.Properties | Export-Excel -ExcelPackage $xl -WorksheetName $entityProperties.Name -TableName $($entityProperties.Name+"_Fields") -AutoSize -PassThru
    
    $propertiesCount = $entityProperties.Properties.Count + 4
    $xl = $dataExample| Export-Excel -ExcelPackage $xl -WorksheetName $entityProperties.Name -TableName $($entityProperties.Name+"_Data") -StartRow $propertiesCount -TableStyle Medium17 -MaxAutoSizeRows 60 -NoNumberConversion * -PassThru #-AutoSize
    #$xl = Set-ExcelColumn -ExcelPackage $xl -WorksheetName $entityProperties.Name -Column 1 -Width 40 -PassThru
}


#Generate Header sheet
$xl = $entitesHeaders | Export-Excel -ExcelPackage $xl -WorksheetName "Header" -TableName "Header" -AutoSize -PassThru

#Save Excel
Close-ExcelPackage $xl -Show
