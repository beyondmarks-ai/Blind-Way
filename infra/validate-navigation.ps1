param([string]$ResourceGroup='blind-way-rg',[string]$FunctionApp='blindway-api-win-d7ofaubf')
$ErrorActionPreference='Stop'
$functionKey=az functionapp keys list -g $ResourceGroup -n $FunctionApp --query functionKeys.default -o tsv
if($LASTEXITCODE -ne 0 -or -not $functionKey){throw 'Cannot access the validation key.'}
try {
  Invoke-RestMethod -Method Post -Uri "https://$FunctionApp.azurewebsites.net/api/ops/navigation/validate" -Headers @{'x-functions-key'=$functionKey} -TimeoutSec 60 | ConvertTo-Json
} catch {
  if($_.Exception.Response){$reader=[IO.StreamReader]::new($_.Exception.Response.GetResponseStream());try{Write-Output $reader.ReadToEnd()}finally{$reader.Dispose()}}
  throw
} finally {$functionKey=$null}
