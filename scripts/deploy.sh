#!/usr/bin/env bash
# Despliega (o actualiza) toda la solución. Idempotente: se puede ejecutar las veces que haga falta.
#
#   ALERT_EMAIL=tu@correo.com ./scripts/deploy.sh
#
# Variables opcionales: RG, LOCATION, IMAGE_TAG
set -euo pipefail
export MSYS_NO_PATHCONV=1 # Git Bash en Windows: no convertir /subscriptions/... en rutas locales

RG="${RG:-rg-conversations}"
LOCATION="${LOCATION:-eastus2}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"
ALERT_EMAIL="${ALERT_EMAIL:?Define ALERT_EMAIL (correo para alertas)}"

# pwd -W da la ruta en formato Windows (C:/...) en Git Bash; en Linux (GitHub Actions) no existe y se usa pwd
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
TRIGGER="TR_RawCsvCreated"

step() { echo -e "\n==> $*"; }

deploy_infra() { # $1 = deployJob (true/false)
  az deployment group create \
    --resource-group "$RG" \
    --name "main-$(date +%Y%m%d%H%M%S)" \
    --template-file "$ROOT/infra/main.bicep" \
    --parameters alertEmail="$ALERT_EMAIL" imageTag="$IMAGE_TAG" deployJob="$1" \
    --query properties.outputs -o json
}

trigger_action() { # $1 = start|stop ; $2 = data factory name
  az rest --method post --output none \
    --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG/providers/Microsoft.DataFactory/factories/$2/triggers/$TRIGGER/$1?api-version=2018-06-01"
}

step "Resource group $RG ($LOCATION)"
az group create --name "$RG" --location "$LOCATION" --tags project=conversations env=demo --output none

# Un trigger activo no se puede modificar: se detiene antes de desplegar y se reinicia al final
ADF="$(az resource list -g "$RG" --resource-type Microsoft.DataFactory/factories --query "[0].name" -o tsv)"
if [[ -n "$ADF" ]]; then
  step "Deteniendo trigger de Data Factory"
  trigger_action stop "$ADF" || true
fi

# El job necesita que la imagen y el secreto existan: en el primer despliegue se crea la base sin job
JOB_EXISTS="$(az resource list -g "$RG" --resource-type Microsoft.App/jobs --query "length(@)" -o tsv)"
if [[ "$JOB_EXISTS" == "0" ]]; then
  step "Infraestructura base (primer despliegue, sin job)"
  deploy_infra false > /dev/null
fi

name_of() { az resource list -g "$RG" --resource-type "$1" --query "[0].name" -o tsv; }
KV="$(name_of Microsoft.KeyVault/vaults)"
ACR="$(name_of Microsoft.ContainerRegistry/registries)"
ADF="$(name_of Microsoft.DataFactory/factories)"
KV_ID="$(az resource list -g "$RG" --resource-type Microsoft.KeyVault/vaults --query "[0].id" -o tsv)"

# Se consulta por el plano de control (ARM): no requiere permisos de lectura de secretos
if ! az resource show --ids "$KV_ID/secrets/source-api-key" --output none 2>/dev/null; then
  step "Generando la API key del sistema origen en Key Vault"
  az deployment group create -g "$RG" --name "secret-source-api-key" \
    --template-file "$ROOT/infra/secret.bicep" \
    --parameters keyVaultName="$KV" sourceApiKey="$(openssl rand -hex 24)" --output none
fi

step "Construyendo la imagen extractor:$IMAGE_TAG en ACR ($ACR)"
az acr build --registry "$ACR" --image "extractor:$IMAGE_TAG" --image "extractor:latest" "$ROOT/conversation-generator-bb" --output none

step "Desplegando la infraestructura completa (con job)"
OUTPUTS="$(deploy_infra true)"

step "Iniciando trigger de Data Factory"
trigger_action start "$ADF"

step "Listo"
echo "$OUTPUTS"
