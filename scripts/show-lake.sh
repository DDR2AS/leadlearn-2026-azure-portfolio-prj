#!/usr/bin/env bash
# Lista los archivos de las capas raw y processed del Data Lake.
set -euo pipefail
export MSYS_NO_PATHCONV=1

RG="${RG:-rg-conversations}"
ACCOUNT="$(az storage account list -g "$RG" --query "[0].name" -o tsv)"
KEY="$(az storage account keys list -g "$RG" -n "$ACCOUNT" --query "[0].value" -o tsv)"

for layer in raw processed; do
  echo "== $layer/"
  az storage fs file list -f "$layer" --account-name "$ACCOUNT" --account-key "$KEY" \
    --query "[?!isDirectory].{archivo:name, bytes:contentLength, modificado:lastModified}" -o table
done
