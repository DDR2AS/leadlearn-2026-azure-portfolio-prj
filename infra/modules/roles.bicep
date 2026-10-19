// Asignaciones RBAC con mínimo privilegio, acotadas al recurso (o contenedor) que cada identidad necesita.

param storageAccountName string
param keyVaultName string
param registryName string
param jobPrincipalId string
param dataFactoryPrincipalId string

var roleIds = {
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName

  resource blobService 'blobServices' existing = {
    name: 'default'

    resource raw 'containers' existing = {
      name: 'raw'
    }

    resource processed 'containers' existing = {
      name: 'processed'
    }
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

// --- Job extractor: descarga su imagen, lee la API key y escribe solo en raw/ ---

resource jobAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, jobPrincipalId, roleIds.acrPull)
  scope: registry
  properties: {
    principalId: jobPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.acrPull)
  }
}

resource jobSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, jobPrincipalId, roleIds.keyVaultSecretsUser)
  scope: vault
  properties: {
    principalId: jobPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultSecretsUser)
  }
}

resource jobRawWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage::blobService::raw.id, jobPrincipalId, roleIds.storageBlobDataContributor)
  scope: storage::blobService::raw
  properties: {
    principalId: jobPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataContributor)
  }
}

// --- Data Factory: lee raw/, escribe processed/ y lee la URL de alertas ---

resource adfRawReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage::blobService::raw.id, dataFactoryPrincipalId, roleIds.storageBlobDataReader)
  scope: storage::blobService::raw
  properties: {
    principalId: dataFactoryPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataReader)
  }
}

resource adfProcessedWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage::blobService::processed.id, dataFactoryPrincipalId, roleIds.storageBlobDataContributor)
  scope: storage::blobService::processed
  properties: {
    principalId: dataFactoryPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.storageBlobDataContributor)
  }
}

resource adfSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, dataFactoryPrincipalId, roleIds.keyVaultSecretsUser)
  scope: vault
  properties: {
    principalId: dataFactoryPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleIds.keyVaultSecretsUser)
  }
}
