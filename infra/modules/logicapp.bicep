// Logic App que envía un correo cuando el pipeline falla.
// La URL de su trigger HTTP se guarda en Key Vault para que Data Factory la lea con su identidad.
// La conexión de Outlook.com debe autorizarse una vez desde el portal (API connections → Authorize).

param location string
param tags object
param alertEmail string
param keyVaultName string

resource outlook 'Microsoft.Web/connections@2016-06-01' = {
  name: 'outlook-alerts'
  location: location
  tags: tags
  properties: {
    displayName: 'outlook-alerts'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'outlook')
    }
  }
}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: 'logic-conv-alerts'
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                pipeline: { type: 'string' }
                runId: { type: 'string' }
                file: { type: 'string' }
                error: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        Send_email: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'outlook\'][\'connectionId\']'
              }
            }
            method: 'post'
            path: '/v2/Mail'
            body: {
              To: alertEmail
              Subject: '[conversations] Falló el pipeline @{triggerBody()?[\'pipeline\']}'
              Body: '<p><b>Pipeline:</b> @{triggerBody()?[\'pipeline\']}</p><p><b>Run ID:</b> @{triggerBody()?[\'runId\']}</p><p><b>Archivo:</b> @{triggerBody()?[\'file\']}</p><p><b>Error:</b> @{base64ToString(triggerBody()?[\'error\'])}</p>'
              Importance: 'High'
            }
          }
        }
      }
    }
    parameters: {
      '$connections': {
        value: {
          outlook: {
            connectionId: outlook.id
            connectionName: outlook.name
            id: outlook.properties.api.id
          }
        }
      }
    }
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource alertUrlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: vault
  name: 'logicapp-alert-url'
  properties: {
    value: listCallbackUrl('${workflow.id}/triggers/manual', '2019-05-01').value
  }
}

output name string = workflow.name
