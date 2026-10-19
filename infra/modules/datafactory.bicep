// Data Factory: convierte cada CSV que llega a raw/ en Parquet dentro de processed/.
// Si la copia falla, lee la URL de la Logic App desde Key Vault y envía la alerta.

param name string
param location string
param tags object
param storageAccountId string
param dfsEndpoint string
param keyVaultUri string

var keyVaultResource = 'https://${substring(environment().suffixes.keyvaultDns, 1)}'
var copyActivity = 'CopyCsvToParquet'

resource factory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

resource dataLake 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: factory
  name: 'LS_DataLake'
  properties: {
    type: 'AzureBlobFS'
    // Sin credenciales: usa la Managed Identity de la factory
    typeProperties: {
      url: dfsEndpoint
    }
  }
}

resource rawCsv 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: factory
  name: 'DS_Raw_Csv'
  properties: {
    type: 'DelimitedText'
    linkedServiceName: {
      referenceName: dataLake.name
      type: 'LinkedServiceReference'
    }
    parameters: {
      folderPath: { type: 'string' }
      fileName: { type: 'string' }
    }
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileSystem: 'raw'
        folderPath: { value: '@dataset().folderPath', type: 'Expression' }
        fileName: { value: '@dataset().fileName', type: 'Expression' }
      }
      columnDelimiter: ','
      quoteChar: '"'
      escapeChar: '\\'
      firstRowAsHeader: true
      encodingName: 'UTF-8'
    }
  }
}

resource processedParquet 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: factory
  name: 'DS_Processed_Parquet'
  properties: {
    type: 'Parquet'
    linkedServiceName: {
      referenceName: dataLake.name
      type: 'LinkedServiceReference'
    }
    parameters: {
      folderPath: { type: 'string' }
      fileName: { type: 'string' }
    }
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileSystem: 'processed'
        folderPath: { value: '@dataset().folderPath', type: 'Expression' }
        fileName: { value: '@dataset().fileName', type: 'Expression' }
      }
      compressionCodec: 'snappy'
    }
  }
}

// Tipos de destino en el Parquet (en el CSV todo llega como texto)
var columns = [
  { name: 'conversation_id', type: 'String' }
  { name: 'fecha', type: 'String' }
  { name: 'started_at', type: 'DateTime' }
  { name: 'channel', type: 'String' }
  { name: 'customer_id', type: 'String' }
  { name: 'agent_id', type: 'String' }
  { name: 'topic', type: 'String' }
  { name: 'first_message', type: 'String' }
  { name: 'duration_sec', type: 'Int32' }
  { name: 'satisfaction', type: 'Int32' }
]

resource pipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: factory
  name: 'PL_Conversations'
  properties: {
    parameters: {
      folderPath: { type: 'string' } // p. ej. raw/conversations/fecha=2026-10-01
      fileName: { type: 'string' } //   p. ej. conversations_2026-10-01.csv
    }
    activities: [
      {
        name: copyActivity
        type: 'Copy'
        policy: {
          timeout: '0.00:10:00'
          retry: 1
          retryIntervalInSeconds: 60
        }
        inputs: [
          {
            referenceName: rawCsv.name
            type: 'DatasetReference'
            parameters: {
              folderPath: { value: '@replace(pipeline().parameters.folderPath, \'raw/\', \'\')', type: 'Expression' }
              fileName: { value: '@pipeline().parameters.fileName', type: 'Expression' }
            }
          }
        ]
        outputs: [
          {
            referenceName: processedParquet.name
            type: 'DatasetReference'
            parameters: {
              folderPath: { value: '@replace(pipeline().parameters.folderPath, \'raw/\', \'\')', type: 'Expression' }
              fileName: { value: '@replace(pipeline().parameters.fileName, \'.csv\', \'.parquet\')', type: 'Expression' }
            }
          }
        ]
        typeProperties: {
          source: {
            type: 'DelimitedTextSource'
            storeSettings: { type: 'AzureBlobFSReadSettings', recursive: false }
            formatSettings: { type: 'DelimitedTextReadSettings' }
          }
          sink: {
            type: 'ParquetSink'
            storeSettings: { type: 'AzureBlobFSWriteSettings' }
            formatSettings: { type: 'ParquetWriteSettings' }
          }
          enableStaging: false
          translator: {
            type: 'TabularTranslator'
            typeConversion: true
            typeConversionSettings: {
              allowDataTruncation: false
              treatBooleanAsNumber: false
            }
            mappings: [
              for column in columns: {
                source: { name: column.name, type: 'String' }
                sink: { name: column.name, type: column.type }
              }
            ]
          }
        }
      }
      {
        name: 'GetAlertUrl'
        type: 'WebActivity'
        dependsOn: [{ activity: copyActivity, dependencyConditions: ['Failed'] }]
        policy: { secureOutput: true, timeout: '0.00:02:00' }
        typeProperties: {
          url: '${keyVaultUri}secrets/logicapp-alert-url?api-version=7.4'
          method: 'GET'
          authentication: {
            type: 'MSI'
            resource: keyVaultResource
          }
        }
      }
      {
        name: 'SendAlert'
        type: 'WebActivity'
        dependsOn: [{ activity: 'GetAlertUrl', dependencyConditions: ['Succeeded'] }]
        policy: { secureInput: true, timeout: '0.00:02:00' }
        typeProperties: {
          url: { value: '@activity(\'GetAlertUrl\').output.value', type: 'Expression' }
          method: 'POST'
          headers: { 'Content-Type': 'application/json' }
          // El error va en base64 para que comillas o saltos de línea no rompan el JSON
          body: {
            value: '{"pipeline":"@{pipeline().Pipeline}","runId":"@{pipeline().RunId}","file":"@{pipeline().parameters.fileName}","error":"@{base64(activity(\'${copyActivity}\').error.message)}"}'
            type: 'Expression'
          }
        }
      }
      {
        // Mantiene el run en estado "Failed" aunque la alerta se haya enviado
        name: 'FailPipeline'
        type: 'Fail'
        dependsOn: [{ activity: 'SendAlert', dependencyConditions: ['Completed'] }]
        typeProperties: {
          message: 'Falló la conversión CSV → Parquet'
          errorCode: '500'
        }
      }
    ]
  }
}

resource trigger 'Microsoft.DataFactory/factories/triggers@2018-06-01' = {
  parent: factory
  name: 'TR_RawCsvCreated'
  properties: {
    type: 'BlobEventsTrigger'
    typeProperties: {
      scope: storageAccountId
      events: ['Microsoft.Storage.BlobCreated']
      blobPathBeginsWith: '/raw/blobs/conversations/'
      blobPathEndsWith: '.csv'
      ignoreEmptyBlobs: true
    }
    pipelines: [
      {
        pipelineReference: {
          referenceName: pipeline.name
          type: 'PipelineReference'
        }
        parameters: {
          folderPath: '@triggerBody().folderPath'
          fileName: '@triggerBody().fileName'
        }
      }
    ]
  }
}

output name string = factory.name
output principalId string = factory.identity.principalId
output triggerName string = trigger.name
