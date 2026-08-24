param(
  [string]$ProjectId = 'blind-way-vision-2026',
  [string]$FirebaseProjectId = 'blind-way-beyondmarks-2026',
  [string]$AwsAccountId = '267653921876',
  [string]$AwsRoleName = 'blind-way-api-role'
)

$ErrorActionPreference = 'Stop'
$gcloud = "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
$pool = 'blind-way-aws'
$provider = 'blind-way-lambda'
$serviceAccountName = 'blind-way-aws'
$serviceAccount = "$serviceAccountName@$ProjectId.iam.gserviceaccount.com"

& $gcloud services enable aiplatform.googleapis.com cloudresourcemanager.googleapis.com iamcredentials.googleapis.com sts.googleapis.com --project=$ProjectId
if ($LASTEXITCODE -ne 0) { throw 'Google APIs could not be enabled. Confirm that project billing is active.' }

$existingServiceAccount = & $gcloud iam service-accounts list --project=$ProjectId --filter="email:$serviceAccount" --format='value(email)'
if (-not $existingServiceAccount) {
  & $gcloud iam service-accounts create $serviceAccountName --project=$ProjectId --display-name='Blind Way AWS runtime'
}

& $gcloud projects add-iam-policy-binding $ProjectId --member="serviceAccount:$serviceAccount" --role='roles/aiplatform.user' --condition=None --quiet --format=none

$existingPool = & $gcloud iam workload-identity-pools list --project=$ProjectId --location=global --filter="name:$pool" --format='value(name)'
if (-not $existingPool) {
  & $gcloud iam workload-identity-pools create $pool --project=$ProjectId --location=global --display-name='Blind Way AWS'
}

$existingProvider = & $gcloud iam workload-identity-pools providers list --project=$ProjectId --location=global --workload-identity-pool=$pool --filter="name:$provider" --format='value(name)'
if (-not $existingProvider) {
  & $gcloud iam workload-identity-pools providers create-aws $provider `
    --project=$ProjectId `
    --location=global `
    --workload-identity-pool=$pool `
    --account-id=$AwsAccountId `
    --attribute-mapping="google.subject=assertion.arn,attribute.aws_role=assertion.arn.extract('assumed-role/{role}/')" `
    --attribute-condition="attribute.aws_role == '$AwsRoleName'"
}

$projectNumber = & $gcloud projects describe $ProjectId --format='value(projectNumber)'
$member = "principalSet://iam.googleapis.com/projects/$projectNumber/locations/global/workloadIdentityPools/$pool/attribute.aws_role/$AwsRoleName"
& $gcloud iam service-accounts add-iam-policy-binding $serviceAccount --project=$ProjectId --role='roles/iam.workloadIdentityUser' --member=$member --quiet --format=none

& $gcloud services enable fcm.googleapis.com --project=$FirebaseProjectId
if ($LASTEXITCODE -eq 0) {
  & $gcloud projects add-iam-policy-binding $FirebaseProjectId --member="serviceAccount:$serviceAccount" --role='roles/firebasecloudmessaging.admin' --condition=None --quiet --format=none
} else {
  Write-Warning 'Firebase Cloud Messaging could not be enabled. Emergency polling still works, but push notifications need this permission.'
}

$providerResource = "projects/$projectNumber/locations/global/workloadIdentityPools/$pool/providers/$provider"
$outputFile = Join-Path $PSScriptRoot '..\aws_backend\gcp-wif.json'
& $gcloud iam workload-identity-pools create-cred-config $providerResource --service-account=$serviceAccount --aws --output-file=$outputFile
if ($LASTEXITCODE -ne 0) { throw 'The Google external-account credential configuration could not be generated.' }

Write-Output "Created keyless AWS-to-Google federation: $outputFile"
