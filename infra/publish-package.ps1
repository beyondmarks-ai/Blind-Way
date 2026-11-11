param(
  [Parameter(Mandatory=$true)][string]$Archive,
  [string]$ResourceGroup = 'blind-way-rg'
)
$ErrorActionPreference = 'Stop'
$outputs = az deployment group show -g $ResourceGroup -n main --query properties.outputs -o json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Deployment outputs are unavailable.' }
$functionName = $outputs.functionAppName.value
$storageName = $outputs.storageAccountName.value
$share = az functionapp config appsettings list -g $ResourceGroup -n $functionName --query "[?name=='WEBSITE_CONTENTSHARE'].value | [0]" -o tsv
if ($LASTEXITCODE -ne 0 -or -not $share) { throw 'Function content share is unavailable.' }
$previousKey = $env:AZURE_STORAGE_KEY
$packageName='blind-way-api-'+(Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.Substring(0,16).ToLower()+'.zip'
$packagePointer=Join-Path $env:TEMP ('blindway-package-'+[guid]::NewGuid().ToString('N')+'.txt')
[IO.File]::WriteAllText($packagePointer,$packageName,[Text.UTF8Encoding]::new($false))
try {
  $env:AZURE_STORAGE_KEY = az storage account keys list -g $ResourceGroup -n $storageName --query '[0].value' -o tsv
  if ($LASTEXITCODE -ne 0 -or -not $env:AZURE_STORAGE_KEY) { throw 'Storage credentials unavailable.' }
  az storage directory create --account-name $storageName --share-name $share --name data --output none
  if ($LASTEXITCODE -ne 0) { throw 'Could not prepare Function data directory.' }
  az storage directory create --account-name $storageName --share-name $share --name data/SitePackages --output none
  if ($LASTEXITCODE -ne 0) { throw 'Could not prepare Function package directory.' }
  az storage file upload --account-name $storageName --share-name $share --source $Archive --path "data/SitePackages/$packageName" --validate-content --output none
  if ($LASTEXITCODE -ne 0) { throw 'Function package upload failed.' }
  az storage file upload --account-name $storageName --share-name $share --source $packagePointer --path data/SitePackages/packagename.txt --validate-content --output none
  if ($LASTEXITCODE -ne 0) { throw 'Function package activation failed.' }
} finally { $env:AZURE_STORAGE_KEY = $previousKey }
az functionapp restart -g $ResourceGroup -n $functionName --output none
if ($LASTEXITCODE -ne 0) { throw 'Function restart failed.' }
$functionId=az functionapp show -g $ResourceGroup -n $functionName --query id -o tsv
az rest --method post --url "https://management.azure.com$functionId/syncfunctiontriggers?api-version=2024-11-01" --output none
if ($LASTEXITCODE -ne 0) { throw 'Function trigger synchronization failed.' }
Write-Output "Published package to $functionName."
