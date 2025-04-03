@description('The name of the environment (dev, staging, prod)')
param environmentName string = 'dev'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The Azure AD tenant ID')
param tenantId string

@description('Feature flags as comma-separated values')
param featureFlags string = ''

@description('Base name for resources (will be suffixed with environment name)')
param baseName string = 'fastapi-app'

var resourceSuffix = '-${environmentName}'
var resourceBaseName = '${baseName}${resourceSuffix}'
var registryName = replace('${baseName}acr${environmentName}', '-', '')

// Define log level based on environment
var logLevel = environmentName == 'dev' ? 'DEBUG' : (environmentName == 'staging' ? 'INFO' : 'WARNING')

// Container Registry
module registry 'modules/registry.bicep' = {
  name: 'registryDeploy'
  params: {
    acrName: registryName
    location: location
  }
}

// Key Vault with Access Policies
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyVaultDeploy'
  params: {
    keyVaultName: '${resourceBaseName}-kv'
    location: location
    tenantId: tenantId
  }
}

// App Service with container and Managed Identity
module appService 'modules/app-service.bicep' = {
  name: 'appServiceDeploy'
  params: {
    appServiceName: resourceBaseName
    location: location
    acrName: registryName
    featureFlags: featureFlags
    logLevel: logLevel
    tenantId: tenantId
    keyVaultName: keyVault.outputs.keyVaultName
  }
  dependsOn: [
    registry
  ]
}

// Output important information
output appServiceName string = appService.outputs.appServiceName
output appServiceUrl string = appService.outputs.appServiceUrl
output keyVaultName string = keyVault.outputs.keyVaultName
output containerRegistryName string = registry.outputs.acrName
output containerRegistryLoginServer string = registry.outputs.acrLoginServer
