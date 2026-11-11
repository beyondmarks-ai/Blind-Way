@description('Globally unique External ID tenant domain prefix.')
param tenantName string

resource customerDirectory 'Microsoft.AzureActiveDirectory/ciamDirectories@2023-05-17-preview' = {
  name: tenantName
  location: 'Asia Pacific'
  sku: { name: 'Standard', tier: 'A0' }
  properties: {
    createTenantProperties: {
      countryCode: 'IN'
      displayName: 'Blind Way Customers'
    }
  }
}

output tenantId string = customerDirectory.properties.tenantId
