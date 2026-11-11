param([string]$ResourceGroup='blind-way-rg', [string]$FunctionApp='blindway-api-win-d7ofaubf')
$ErrorActionPreference='Stop'
if (-not $env:SARVAM_API_KEY) { throw 'Set SARVAM_API_KEY in this process before running. The key stays on the server.' }
$settingsFile=Join-Path $env:TEMP ('blindway-sarvam-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  @{SARVAM_API_KEY=$env:SARVAM_API_KEY;SARVAM_STT_MODEL='saaras:v4';SARVAM_TTS_MODEL='bulbul:v3';SARVAM_TTS_SPEAKER='ritu'} |
    ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding utf8
  az functionapp config appsettings set --resource-group $ResourceGroup --name $FunctionApp --settings "@$settingsFile" --output none
  if($LASTEXITCODE -ne 0) { throw 'Could not configure Sarvam on Azure.' }
} finally { if(Test-Path -LiteralPath $settingsFile) { Remove-Item -LiteralPath $settingsFile } }
Write-Output 'Sarvam configured on the Azure API. No key is included in the APK.'
