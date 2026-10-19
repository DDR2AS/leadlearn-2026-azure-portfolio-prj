// Key Vault en modo RBAC. Guarda la API key del sistema origen y la URL de la Logic App.

param name string
param location string
param tags object

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

output name string = vault.name
output uri string = vault.properties.vaultUri
