param(
  [string]$ResourceGroup = 'blind-way-rg',
  [string]$Location = 'centralindia',
  [string]$ResourceLocation = 'centralindia',
  [string]$FirebaseProjectId = 'blind-way-beyondmarks-2026'
)

$ErrorActionPreference = 'Stop'

az group create --name $ResourceGroup --location $Location --output none
if ($LASTEXITCODE -ne 0) { throw 'Azure resource group creation failed.' }
az deployment group create `
  --resource-group $ResourceGroup `
  --template-file "$PSScriptRoot\main.bicep" `
  --parameters firebaseProjectId=$FirebaseProjectId location=$ResourceLocation notificationLocation=$ResourceLocation `
  --output table
if ($LASTEXITCODE -ne 0) { throw 'Azure resource deployment failed.' }

$principalId = az deployment group show --resource-group $ResourceGroup --name main --query properties.outputs.functionPrincipalId.value -o tsv
$openAiId = az deployment group show --resource-group $ResourceGroup --name main --query properties.outputs.azureOpenAiResourceId.value -o tsv
if ([string]::IsNullOrWhiteSpace($principalId) -or [string]::IsNullOrWhiteSpace($openAiId)) {
  throw 'Deployment outputs required for the Azure OpenAI role assignment are missing.'
}
az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Cognitive Services OpenAI User' --scope $openAiId --output none
if ($LASTEXITCODE -ne 0) { throw 'Azure OpenAI role assignment failed.' }
