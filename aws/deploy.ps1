param(
  [string]$Profile = 'rideguardian-admin',
  [string]$Region = 'ap-south-1',
  [string]$StackName = 'blind-way',
  [string]$GcpProjectId = 'blind-way-vision-2026',
  [string]$FirebaseProjectId = 'blind-way-beyondmarks-2026',
  [string]$GeminiModel = 'gemini-3.5-flash-lite'
)

$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\.."
$backend = Join-Path $root 'aws_backend'
$federationConfig = Join-Path $backend 'gcp-wif.json'
if (-not (Test-Path -LiteralPath $federationConfig)) {
  throw 'Run google-cloud/setup-aws-federation.ps1 before deploying AWS.'
}
if ([string]::IsNullOrWhiteSpace($env:SARVAM_API_KEY)) {
  throw 'SARVAM_API_KEY is not present in the current environment.'
}

Push-Location $backend
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw 'Backend dependencies could not be installed.' }
  npm run build
  if ($LASTEXITCODE -ne 0) { throw 'Backend compilation failed.' }
  $packagePath = Join-Path $env:TEMP 'blind-way-aws.zip'
  $stagingPath = Join-Path $env:TEMP "blind-way-lambda-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $stagingPath | Out-Null
  Copy-Item 'dist\index.js' (Join-Path $stagingPath 'index.js')
  Copy-Item 'dist\speech-stream.js' (Join-Path $stagingPath 'speech-stream.js')
  Copy-Item 'gcp-wif.json' (Join-Path $stagingPath 'gcp-wif.json')
  Copy-Item 'lambda-package.json' (Join-Path $stagingPath 'package.json')
  Compress-Archive -Path "$stagingPath\*" -DestinationPath $packagePath -Force
} finally {
  Pop-Location
}

$accountId = (aws sts get-caller-identity --profile $Profile --query Account --output text).Trim()
if (-not $accountId) { throw 'AWS authentication is required.' }
$bucket = "blind-way-deploy-$accountId-$Region"
$existingBucket = aws s3api list-buckets --profile $Profile --query "Buckets[?Name=='$bucket'].Name | [0]" --output text
if (-not $existingBucket -or $existingBucket -eq 'None') {
  aws s3api create-bucket --bucket $bucket --region $Region --create-bucket-configuration LocationConstraint=$Region --profile $Profile --output json | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'The deployment bucket could not be created.' }
  aws s3api put-bucket-encryption --bucket $bucket --profile $Profile --server-side-encryption-configuration 'Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]' | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Deployment bucket encryption could not be enabled.' }
  aws s3api put-public-access-block --bucket $bucket --profile $Profile --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  if ($LASTEXITCODE -ne 0) { throw 'Deployment bucket public access could not be blocked.' }
}

$hash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
$key = "lambda/blind-way-$hash.zip"
aws s3 cp $packagePath "s3://$bucket/$key" --profile $Profile --region $Region --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'The Lambda package upload failed.' }

aws cloudformation deploy `
  --template-file "$PSScriptRoot\template.yaml" `
  --stack-name $StackName `
  --region $Region `
  --profile $Profile `
  --capabilities CAPABILITY_NAMED_IAM `
  --no-fail-on-empty-changeset `
  --parameter-overrides `
    CodeBucket=$bucket `
    CodeKey=$key `
    GcpProjectId=$GcpProjectId `
    FirebaseProjectId=$FirebaseProjectId `
    GeminiModel=$GeminiModel `
    SarvamApiKey=$env:SARVAM_API_KEY
if ($LASTEXITCODE -ne 0) { throw 'AWS CloudFormation deployment failed.' }

$apiUrl = aws cloudformation describe-stacks --stack-name $StackName --region $Region --profile $Profile --query "Stacks[0].Outputs[?OutputKey=='ApiBaseUrl'].OutputValue" --output text
$speechStreamUrl = aws cloudformation describe-stacks --stack-name $StackName --region $Region --profile $Profile --query "Stacks[0].Outputs[?OutputKey=='SpeechStreamUrl'].OutputValue" --output text
Write-Output "API_BASE_URL=$apiUrl"
Write-Output "SPEECH_STREAM_URL=$speechStreamUrl"
