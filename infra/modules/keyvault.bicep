@description('Name of the Key Vault')
param keyVaultName string

@description('Location for Key Vault')
param location string

@description('Tenant ID for access policies')
param tenantId string

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    tenantId: tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

// Outputs
output keyVaultName string = keyVault.name
