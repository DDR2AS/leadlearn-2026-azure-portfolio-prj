#!/usr/bin/env bash
# Ejecuta el extractor a demanda para una fecha (simulación / backfill).
#
#   ./scripts/run-job.sh 2026-10-01        # cantidad aleatoria
#   ./scripts/run-job.sh 2026-10-01 500    # 500 conversaciones
set -euo pipefail
export MSYS_NO_PATHCONV=1

DATE="${1:?Uso: run-job.sh YYYY-MM-DD [cantidad]}"
COUNT="${2:-}"
RG="${RG:-rg-conversations}"
JOB="job-extractor"

# Al iniciar con overrides, Container Apps reemplaza la definición del contenedor:
# hay que reenviar imagen y variables de la configuración actual.
container() { az containerapp job show -n "$JOB" -g "$RG" --query "properties.template.containers[0].$1" -o tsv; }
IMAGE="$(container image)"
STORAGE_URL="$(container "env[?name=='STORAGE_ACCOUNT_URL'].value | [0]")"
CLIENT_ID="$(container "env[?name=='AZURE_CLIENT_ID'].value | [0]")"

ENV_VARS=(
  "SOURCE_API_KEY=secretref:source-api-key"
  "STORAGE_ACCOUNT_URL=$STORAGE_URL"
  "AZURE_CLIENT_ID=$CLIENT_ID"
  "EXTRACT_DATE=$DATE"
)
[[ -n "$COUNT" ]] && ENV_VARS+=("EXTRACT_COUNT=$COUNT")

EXECUTION="$(az containerapp job start -n "$JOB" -g "$RG" \
  --container-name extractor --image "$IMAGE" --cpu 0.25 --memory 0.5Gi \
  --env-vars "${ENV_VARS[@]}" --query name -o tsv)"

echo "Ejecución iniciada: $EXECUTION"
echo "Estado:  az containerapp job execution show -n $JOB -g $RG --job-execution-name $EXECUTION --query properties.status -o tsv"
echo "Logs:    az containerapp job logs show -n $JOB -g $RG --execution $EXECUTION --container extractor"
