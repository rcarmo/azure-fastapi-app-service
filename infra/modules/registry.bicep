@description('Name of the container registry')
param acrName string

@description('Location for container registry')
param location string

resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// Outputs
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer

