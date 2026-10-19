// Entorno de Container Apps (plan de consumo) y el job programado del extractor.

param location string
param tags object
param deployJob bool
param image string
param registryServer string
param identityId string
param identityClientId string
param keyVaultUri string
param blobEndpoint string

@description('Todos los días a las 06:00 UTC (01:00 en Lima)')
param cronExpression string = '0 6 * * *'

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-conversations'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource environment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-conversations'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logs.properties.customerId
        sharedKey: logs.listKeys().primarySharedKey
      }
    }
  }
}

resource job 'Microsoft.App/jobs@2024-03-01' = if (deployJob) {
  name: 'job-extractor'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityId}': {}
    }
  }
  properties: {
    environmentId: environment.id
    configuration: {
      triggerType: 'Schedule'
      replicaTimeout: 600
      replicaRetryLimit: 1
      scheduleTriggerConfig: {
        cronExpression: cronExpression
        parallelism: 1
        replicaCompletionCount: 1
      }
      registries: [
        {
          server: registryServer
          identity: identityId
        }
      ]
      secrets: [
        {
          // Referencia a Key Vault: el valor nunca pasa por la plantilla
          name: 'source-api-key'
          keyVaultUrl: '${keyVaultUri}secrets/source-api-key'
          identity: identityId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'extractor'
          image: image
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'SOURCE_API_KEY'
              secretRef: 'source-api-key'
            }
            {
              name: 'STORAGE_ACCOUNT_URL'
              value: blobEndpoint
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: identityClientId
            }
          ]
        }
      ]
    }
  }
}

output jobName string = deployJob ? job.name : ''
