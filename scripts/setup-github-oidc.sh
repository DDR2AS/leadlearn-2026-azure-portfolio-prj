#!/usr/bin/env bash
# Crea la identidad que usa GitHub Actions para desplegar (OIDC, sin secretos).
# Ejecutar una vez, después del primer deploy.sh.
#
#   ./scripts/setup-github-oidc.sh <usuario>/<repo>
set -euo pipefail
export MSYS_NO_PATHCONV=1

REPO="${1:?Uso: setup-github-oidc.sh <usuario>/<repo>}"
RG="${RG:-rg-conversations}"
APP_NAME="github-${REPO//\//-}"

RG_ID="$(az group show --name "$RG" --query id -o tsv)"

APP_ID="$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv)"
if [[ -z "$APP_ID" ]]; then
  APP_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
  az ad sp create --id "$APP_ID" --output none
fi
SP_ID="$(az ad sp show --id "$APP_ID" --query id -o tsv)"

# GitHub puede enviar el subject con los IDs numéricos del dueño y del repo
# (repo:usuario@123/repo@456:...), así que se registran ambos formatos.
IDS="$(curl -s "https://api.github.com/repos/$REPO" | grep -oE '"id": [0-9]+' | head -2 | grep -oE '[0-9]+' | tr '\n' ' ')"
read -r REPO_NUM OWNER_NUM <<< "$IDS"
SUBJECTS=("main=repo:$REPO:ref:refs/heads/main")
[[ -n "$OWNER_NUM" ]] && SUBJECTS+=("main-ids=repo:${REPO%%/*}@$OWNER_NUM/${REPO##*/}@$REPO_NUM:ref:refs/heads/main")

for entry in "${SUBJECTS[@]}"; do
  name="${entry%%=*}"; subject="${entry#*=}"
  if [[ -z "$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$name'].name" -o tsv)" ]]; then
    az ad app federated-credential create --id "$APP_ID" --output none --parameters "{
      \"name\": \"$name\",
      \"issuer\": \"https://token.actions.githubusercontent.com\",
      \"subject\": \"$subject\",
      \"audiences\": [\"api://AzureADTokenExchange\"]
    }"
  fi
done

# Solo sobre el resource group del proyecto. RBAC Administrator es necesario porque el Bicep crea role assignments.
for role in "Contributor" "Role Based Access Control Administrator"; do
  az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
    --role "$role" --scope "$RG_ID" --output none
done

cat <<EOF

Listo. En GitHub → Settings → Secrets and variables → Actions → Variables, crea:

  AZURE_CLIENT_ID        $APP_ID
  AZURE_TENANT_ID        $(az account show --query tenantId -o tsv)
  AZURE_SUBSCRIPTION_ID  $(az account show --query id -o tsv)
  ALERT_EMAIL            <tu correo>
EOF
