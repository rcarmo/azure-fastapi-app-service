@description('Name of the App Service')
param appServiceName string

@description('Location for the App Service')
param location string

@description('Name of the container registry')
param acrName string

@description('Name of the Key Vault')
param keyVaultName string

@description('Tenant ID for EntraID authentication')
param tenantId string

@description('Logging level based on environment')
param logLevel string

@description('Feature flags as comma-delimited list')
param featureFlags string = ''

// Get references to existing resources
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

// Create App Service Plan (Linux)
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${appServiceName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'B1' // Smallest SKU that supports Linux containers. TODO: hoist this as a parameter
    tier: 'Basic'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

// Create App Service
resource appService 'Microsoft.Web/sites@2021-02-01' = {
  name: appServiceName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      minTlsVersion: '1.2'  // Enforce minimum TLS version
      linuxFxVersion: 'DOCKER|mcr.microsoft.com/appsvc/staticsite:latest' // Placeholder until actual image is pushed
      appSettings: [
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acr.properties.loginServer}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: acr.name
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: '@Microsoft.KeyVault(SecretUri=https://${keyVaultName}.vault.azure.net/secrets/acr-password)'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'LOG_LEVEL'
          value: logLevel
        }
        {
          name: 'FEATURE_FLAGS'
          value: featureFlags
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
      ]
    }
  }
}

// Separate auth configuration resource
resource authSettings 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: appService
  name: 'authsettingsV2'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'RedirectToLoginPage'
      requireAuthentication: true  // Require authentication for all requests
      redirectToProvider: 'azureActiveDirectory'  // Default provider
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: !empty(tenantId) ? tenantId : 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' // Replace with actual ID
          openIdIssuer: 'https://sts.windows.net/${tenantId}/'
        }
        validation: {
          allowedAudiences: [
            !empty(tenantId) ? 'api://${tenantId}' : 'api://${appService.name}'
          ]
        }
        login: {
          disableWWWAuthenticate: false
        }
      }
    }
    login: {
      tokenStore: {
        enabled: true
      }
    }
    httpSettings: {
      requireHttps: true  // Additional HTTPS enforcement
    }
  }
}

// Create Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appServiceName}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource webAppConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: appService
  name: 'web'
  properties: {
    minTlsVersion: '1.2'
    httpLoggingEnabled: true
    detailedErrorLoggingEnabled: true
  }
}

// Grant App Service access to Key Vault
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2024-11-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: appService.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Outputs
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output appInsightsKey string = appInsights.properties.InstrumentationKey
