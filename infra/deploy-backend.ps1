param([string]$ResourceGroup = 'blind-way-rg')
$ErrorActionPreference = 'Stop'
$functionName = az deployment group show --resource-group $ResourceGroup --name main --query properties.outputs.functionAppName.value -o tsv
if ($LASTEXITCODE -ne 0 -or -not $functionName) { throw 'Function app deployment output was not found.' }
$backendRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../backend'))
Push-Location $backendRoot
try {
  npm ci --no-audit --no-fund
  if ($LASTEXITCODE -ne 0) { throw 'Backend dependency installation failed.' }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw 'Backend build failed.' }
  npm test
  if ($LASTEXITCODE -ne 0) { throw 'Backend tests failed.' }
  $stage = Join-Path $env:TEMP ('BlindWayAzure-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $stage | Out-Null
  Copy-Item -LiteralPath dist -Destination $stage -Recurse
  Copy-Item -LiteralPath host.json,package.json,package-lock.json -Destination $stage
  Push-Location $stage
  try {
    npm ci --omit=dev --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'Deployment dependency installation failed.' }
    $archive = "$stage.zip"
    if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
      tar.exe -a -c -f $archive dist node_modules host.json package.json
      if ($LASTEXITCODE -ne 0) { throw 'ZIP packaging failed.' }
    } else {
      Compress-Archive -Path dist,node_modules,host.json,package.json -DestinationPath $archive
    }
    & "$PSScriptRoot/publish-package.ps1" -ResourceGroup $ResourceGroup -Archive $archive
  } finally { Pop-Location }
} finally { Pop-Location }
Write-Output "Deployed $functionName."
