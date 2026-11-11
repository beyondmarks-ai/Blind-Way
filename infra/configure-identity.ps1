# Legacy Entra provisioning. Current app uses Google phone OTP; see docs/PHONE_OTP_CHECK.md.
param(
  [Parameter(Mandatory=$true)][string]$TenantId,
  [Parameter(Mandatory=$true)][string]$TenantDomain,
  [string]$Az = 'az'
)
$ErrorActionPreference = 'Stop'
$token = & $Az account get-access-token --tenant $TenantId --resource https://graph.microsoft.com --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Sign in to the External ID tenant with Azure CLI first.' }
$headers = @{ Authorization = "Bearer $token" }
function Graph([string]$Method, [string]$Path, $Body = $null) {
  $parameters = @{ Method=$Method; Uri="https://graph.microsoft.com/v1.0/$Path"; Headers=$headers; ContentType='application/json' }
  if ($null -ne $Body) { $parameters.Body = $Body | ConvertTo-Json -Depth 30 -Compress }
  try { Invoke-RestMethod @parameters } catch {
    # Do not print request headers or tokens on failure.
    if ($_.ErrorDetails.Message) { throw $_.ErrorDetails.Message }
    if ($_.Exception.Response) {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $detail = $reader.ReadToEnd()
      $reader.Dispose()
      throw "Microsoft Graph $Method $Path failed ($($_.Exception.Response.StatusCode)): $detail"
    }
    throw "Microsoft Graph $Method $Path failed: $($_.Exception.Message)"
  }
}
$organization = (Graph GET 'organization').value[0]
if ($organization.tenantType -ne 'CIAM' -or $organization.id -ne $TenantId) {
  throw 'This script requires the specified External ID customer tenant.'
}
function Application([string]$Name, $Properties) {
  $existing = @( (Graph GET "applications?`$filter=displayName eq '$Name'").value )
  if ($existing.Count -gt 1) { throw "Multiple app registrations named $Name; select one explicitly." }
  if ($existing.Count -eq 1) { return $existing[0] }
  $Properties.displayName = $Name
  $Properties.signInAudience = 'AzureADMyOrg'
  Graph POST 'applications' $Properties
}
$api = Application 'Blind Way API' @{ api=@{ requestedAccessTokenVersion=2 } }
$scope = @($api.api.oauth2PermissionScopes | Where-Object value -eq 'access_as_user')
$scopeId = if ($scope.Count) { $scope[0].id } else { [guid]::NewGuid().ToString() }
$mobile = Application 'Blind Way Android' @{
  publicClient=@{redirectUris=@('ai.beyondmarks.blindway://oauthredirect')}
  isFallbackPublicClient=$false
}
Graph PATCH "applications/$($api.id)" @{
  identifierUris=@("api://$($api.appId)")
  api=@{
    requestedAccessTokenVersion=2
    oauth2PermissionScopes=@(@{ id=$scopeId; value='access_as_user'; type='Admin'; isEnabled=$true
      adminConsentDisplayName='Use Blind Way'; adminConsentDescription='Access Blind Way camera assistance and emergency coordination as the signed-in user.' })
  }
} | Out-Null
Graph PATCH "applications/$($mobile.id)" @{
  publicClient=@{redirectUris=@('ai.beyondmarks.blindway://oauthredirect')}
  requiredResourceAccess=@(@{resourceAppId=$api.appId; resourceAccess=@(@{id=$scopeId; type='Scope'})})
} | Out-Null
function Principal([string]$AppId) {
  $existing = @((Graph GET "servicePrincipals?`$filter=appId eq '$AppId'").value)
  if ($existing.Count) { return $existing[0] }
  Graph POST 'servicePrincipals' @{appId=$AppId}
}
$apiPrincipal = Principal $api.appId
$mobilePrincipal = Principal $mobile.appId
$grants = @((Graph GET "oauth2PermissionGrants?`$filter=clientId eq '$($mobilePrincipal.id)'").value | Where-Object { $_.resourceId -eq $apiPrincipal.id -and $_.consentType -eq 'AllPrincipals' })
if (-not $grants.Count) {
  Graph POST 'oauth2PermissionGrants' @{clientId=$mobilePrincipal.id; consentType='AllPrincipals'; resourceId=$apiPrincipal.id; scope='access_as_user'} | Out-Null
}
$flowName = 'Blind Way email sign-up'
$flows = @((Graph GET 'identity/authenticationEventsFlows').value | Where-Object displayName -eq $flowName)
if ($flows.Count -gt 1) { throw 'Multiple Blind Way user flows exist.' }
if ($flows.Count -eq 0) {
  $flow = Graph POST 'identity/authenticationEventsFlows' @{
    '@odata.type'='#microsoft.graph.externalUsersSelfServiceSignUpEventsFlow'
    displayName=$flowName
    onAuthenticationMethodLoadStart=@{
      '@odata.type'='#microsoft.graph.onAuthenticationMethodLoadStartExternalUsersSelfServiceSignUp'
      identityProviders=@(@{id='EmailPassword-OAUTH'})
    }
    onInteractiveAuthFlowStart=@{
      '@odata.type'='#microsoft.graph.onInteractiveAuthFlowStartExternalUsersSelfServiceSignUp'
      isSignUpAllowed=$true
    }
    conditions=@{ applications=@{ includeApplications=@(@{appId=$mobile.appId}) } }
    onAttributeCollection=@{
      '@odata.type'='#microsoft.graph.onAttributeCollectionExternalUsersSelfServiceSignUp'
      attributes=@(@{id='displayName'; displayName='Name'; description='Your name'; userFlowAttributeType='builtIn'; dataType='string'})
      attributeCollectionPage=@{views=@(@{inputs=@(@{attribute='displayName';label='Your name';inputType='text';hidden=$false;editable=$true;writeToDirectory=$true;required=$true})})}
    }
  }
} else { $flow = $flows[0] }
$discoveryUrl = "https://$TenantDomain.ciamlogin.com/$TenantId/v2.0/.well-known/openid-configuration"
$discovery = Invoke-RestMethod $discoveryUrl
$configuration = @{
  ENTRA_CLIENT_ID=$mobile.appId; ENTRA_DISCOVERY_URL=$discoveryUrl
  ENTRA_API_SCOPE="api://$($api.appId)/access_as_user"
  ENTRA_TENANT_ID=$TenantId; ENTRA_ISSUER=$discovery.issuer; ENTRA_JWKS_URI=$discovery.jwks_uri
  ENTRA_API_CLIENT_ID=$api.appId; ENTRA_MOBILE_CLIENT_ID=$mobile.appId
  ENTRA_REQUIRED_SCOPE='access_as_user'; USER_FLOW_ID=$flow.id
}
$destination = Join-Path $PSScriptRoot '../config/azure-identity.json'
$configuration | ConvertTo-Json | Set-Content -LiteralPath $destination -Encoding UTF8
$token = $null
$headers = $null
Write-Output "Configured Blind Way External ID. Settings written to config/azure-identity.json."
