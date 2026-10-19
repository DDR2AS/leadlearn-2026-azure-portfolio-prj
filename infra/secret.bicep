// Crea la API key del sistema origen en Key Vault (solo la primera vez, desde scripts/deploy.sh).

param keyVaultName string

@secure()
param sourceApiKey string

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'source-api-key'
  properties: {
    value: sourceApiKey
  }
}
