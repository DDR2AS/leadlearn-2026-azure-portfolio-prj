#!/usr/bin/env bash
# Borra todos los recursos del proyecto y purga el Key Vault (soft delete) para poder recrearlo.
set -euo pipefail
export MSYS_NO_PATHCONV=1

RG="${RG:-rg-conversations}"

if [[ "$(az group exists --name "$RG")" != "true" ]]; then
  echo "El resource group $RG no existe."
  exit 0
fi

KV="$(az keyvault list -g "$RG" --query "[0].name" -o tsv)"

read -r -p "Se borrará el resource group $RG y todo su contenido. ¿Continuar? (s/N) " answer
[[ "$answer" == "s" || "$answer" == "S" ]] || { echo "Cancelado."; exit 1; }

echo "Borrando $RG (tarda unos minutos)..."
az group delete --name "$RG" --yes

if [[ -n "$KV" ]]; then
  echo "Purgando Key Vault $KV..."
  az keyvault purge --name "$KV"
fi

echo "Listo. No quedan recursos del proyecto."
