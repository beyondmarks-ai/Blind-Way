param([string]$ResourceGroup = 'blind-way-rg')

$ErrorActionPreference = 'Stop'
$functionName = az deployment group show --resource-group $ResourceGroup --name main --query properties.outputs.functionAppName.value -o tsv
if (-not $functionName) { throw 'Function app deployment output was not found.' }
$storageName = az deployment group show --resource-group $ResourceGroup --name main --query properties.outputs.storageAccountName.value -o tsv
if (-not $storageName) {
  # Older deployments did not expose this output. Select the Function's
  # dedicated storage account from the same resource group.
  $storageName = az storage account list --resource-group $ResourceGroup --query '[0].name' -o tsv
}
if (-not $storageName) { throw 'The Function storage account was not found.' }

Push-Location "$PSScriptRoot\..\backend"
try {
  npm ci
  $distPath = Join-Path (Get-Location) 'dist'
  if (Test-Path -LiteralPath $distPath) {
    Remove-Item -LiteralPath $distPath -Recurse -Force
  }
  npm run build
  npm prune --omit=dev
  Compress-Archive -Path dist,node_modules,host.json,package.json -DestinationPath "$env:TEMP\blind-way-api.zip" -Force
  $contentShare = az functionapp config appsettings list --resource-group $ResourceGroup --name $functionName --query "[?name=='WEBSITE_CONTENTSHARE'].value | [0]" -o tsv
  if (-not $contentShare) { throw 'The Function content share was not found.' }
  $storageKey = az storage account keys list --resource-group $ResourceGroup --account-name $storageName --query '[0].value' -o tsv
  az storage share create --name $contentShare --account-name $storageName --account-key $storageKey --output none
  az storage directory create --share-name $contentShare --name data/SitePackages --account-name $storageName --account-key $storageKey --output none
  az storage file upload --share-name $contentShare --source "$env:TEMP\blind-way-api.zip" --path data/SitePackages/blind-way-api.zip --account-name $storageName --account-key $storageKey --validate-content --output none
  az storage file upload --share-name $contentShare --source "$PSScriptRoot\packagename.txt" --path data/SitePackages/packagename.txt --account-name $storageName --account-key $storageKey --validate-content --output none
  if ($LASTEXITCODE -ne 0) { throw 'Function package upload failed.' }
  az functionapp config appsettings set --resource-group $ResourceGroup --name $functionName --settings WEBSITE_RUN_FROM_PACKAGE=1 --output none
  az functionapp restart --resource-group $ResourceGroup --name $functionName
} finally {
  Pop-Location
}
