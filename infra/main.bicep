// Infraestructura del pipeline de conversaciones.
// Se despliega a nivel de resource group: az deployment group create -g <rg> -f infra/main.bicep

@description('Región de los recursos')
param location string = resourceGroup().location

@description('Correo para alertas de presupuesto y fallos del pipeline')
param alertEmail string

@description('Tag de la imagen del extractor en ACR')
param imageTag string = 'latest'

@description('Crear el Container Apps Job (requiere que la imagen y el secreto ya existan)')
param deployJob bool = false

@description('Presupuesto mensual del resource group en USD')
param budgetAmount int = 9

@description('Inicio del presupuesto (primer día de un mes)')
param budgetStartDate string = utcNow('yyyy-MM-01')

param tags object = {
  project: 'conversations'
  env: 'demo'
}

var suffix = uniqueString(resourceGroup().id)

resource jobIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-extractor'
  location: location
  tags: tags
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: 'stconv${suffix}'
    location: location
    tags: tags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    name: 'kv-conv-${suffix}'
    location: location
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    name: 'acrconv${suffix}'
    location: location
    tags: tags
  }
}

module logicApp 'modules/logicapp.bicep' = {
  name: 'logicapp'
  params: {
    location: location
    tags: tags
    alertEmail: alertEmail
    keyVaultName: keyVault.outputs.name
  }
}

module dataFactory 'modules/datafactory.bicep' = {
  name: 'datafactory'
  params: {
    name: 'adf-conv-${suffix}'
    location: location
    tags: tags
    storageAccountId: storage.outputs.id
    dfsEndpoint: storage.outputs.dfsEndpoint
    keyVaultUri: keyVault.outputs.uri
  }
}

module roles 'modules/roles.bicep' = {
  name: 'roles'
  params: {
    storageAccountName: storage.outputs.name
    keyVaultName: keyVault.outputs.name
    registryName: registry.outputs.name
    jobPrincipalId: jobIdentity.properties.principalId
    dataFactoryPrincipalId: dataFactory.outputs.principalId
  }
}

module containerApps 'modules/containerapps.bicep' = {
  name: 'containerapps'
  dependsOn: [roles]
  params: {
    location: location
    tags: tags
    deployJob: deployJob
    image: '${registry.outputs.loginServer}/extractor:${imageTag}'
    registryServer: registry.outputs.loginServer
    identityId: jobIdentity.id
    identityClientId: jobIdentity.properties.clientId
    keyVaultUri: keyVault.outputs.uri
    blobEndpoint: storage.outputs.blobEndpoint
  }
}

module budget 'modules/budget.bicep' = {
  name: 'budget'
  params: {
    amount: budgetAmount
    startDate: budgetStartDate
    alertEmail: alertEmail
  }
}

output storageAccountName string = storage.outputs.name
output keyVaultName string = keyVault.outputs.name
output registryName string = registry.outputs.name
output dataFactoryName string = dataFactory.outputs.name
output triggerName string = dataFactory.outputs.triggerName
output logicAppName string = logicApp.outputs.name
output jobName string = containerApps.outputs.jobName
