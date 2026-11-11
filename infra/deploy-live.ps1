param(
  [string]$Project='project-8eeef9d3-080a-4f49-95e',
  [string]$Region='us-central1',
  [string]$Model='gemini-3.8-live',
  [string]$AzureApiBaseUrl='https://blindway-api-win-d7ofaubf.azurewebsites.net/api'
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$values=@{GOOGLE_CLOUD_PROJECT=$Project;VERTEX_LOCATION=$Region;VERTEX_LIVE_MODEL=$Model;AZURE_API_BASE_URL=$AzureApiBaseUrl}
$values['FIREBASE_PROJECT_ID']=$Project
$file=Join-Path $root 'config/live-env.json'
$values | ConvertTo-Json | Set-Content -LiteralPath $file -Encoding utf8
Push-Location (Join-Path $root 'live_backend')
try {npm ci --no-audit --no-fund;if($LASTEXITCODE -ne 0){throw 'Dependency install failed'};npm test;if($LASTEXITCODE -ne 0){throw 'Live tests failed'}} finally {Pop-Location}
gcloud run deploy blindway-live --source="$root/live_backend" --project=$Project --region=$Region --service-account="blindway-live@$Project.iam.gserviceaccount.com" --env-vars-file=$file --allow-unauthenticated --timeout=3600 --concurrency=20 --max-instances=2 --min-instances=0 --memory=512Mi --cpu=1 --quiet
if($LASTEXITCODE -ne 0){throw 'Cloud Run deployment failed'}
$url=gcloud run services describe blindway-live --project=$Project --region=$Region --format='value(status.url)'
$configFile=Join-Path $root 'config/app_config.json'
$config=Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
$config | Add-Member -NotePropertyName GEMINI_LIVE_URL -NotePropertyValue ($url.Replace('https://','wss://')+'/live') -Force
$config | ConvertTo-Json | Set-Content -LiteralPath $configFile -Encoding utf8
Write-Output "Live relay deployed: $url. Build the APK with config/app_config.json."
