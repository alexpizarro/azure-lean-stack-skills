#!/usr/bin/env bash
# Create or update an Azure Logic App (Consumption tier) that POSTs to an
# endpoint on a recurring schedule with a shared-secret header.
#
# Idempotent: if the Logic App already exists, the definition is updated.
#
# Required env vars:
#   ORG, PROJECT, ENV               — used to derive the resource group + Logic App name
#   ENDPOINT                        — full URL the scheduler will POST to
#   SCHEDULER_KEY                   — shared secret for the x-scheduler-key header
# Optional env vars:
#   INTERVAL                        — recurrence interval (default 5)
#   FREQUENCY                       — Minute | Hour | Day | Week (default Minute)
#   LOCATION                        — Azure region (default australiaeast)
#   LOGIC_APP_NAME                  — override the derived name
#   RESOURCE_GROUP                  — override the derived RG
#
# Proven pattern: trg-directory-website/scripts/create-recrawl-scheduler.sh

set -euo pipefail

: "${ORG:?ORG required (e.g. acme)}"
: "${PROJECT:?PROJECT required}"
: "${ENV:?ENV required (e.g. test, prod)}"
: "${ENDPOINT:?ENDPOINT required (URL the scheduler will POST to)}"
: "${SCHEDULER_KEY:?SCHEDULER_KEY required (shared secret for x-scheduler-key header)}"

INTERVAL="${INTERVAL:-5}"
FREQUENCY="${FREQUENCY:-Minute}"
LOCATION="${LOCATION:-australiaeast}"
LOGIC_APP_NAME="${LOGIC_APP_NAME:-${ORG}-${PROJECT}-sched-${ENV}}"
RESOURCE_GROUP="${RESOURCE_GROUP:-${ORG}-${PROJECT}-rg-${ENV}}"

case "$FREQUENCY" in Minute|Hour|Day|Week) ;; *)
  echo "ERROR: FREQUENCY must be Minute | Hour | Day | Week (got '$FREQUENCY')" >&2
  exit 1
  ;;
esac

cat <<EOF
─────────────────────────────────────────────────────────────────
Azure Logic Apps Consumption scheduler — provision
  Resource Group : $RESOURCE_GROUP
  Logic App      : $LOGIC_APP_NAME
  Endpoint       : $ENDPOINT
  Recurrence     : every $INTERVAL $FREQUENCY
─────────────────────────────────────────────────────────────────
EOF

# Build the workflow definition. Endpoint + secret are substituted via sed
# (not jq) to avoid a dependency on jq in CI runners.
TEMP_DEF=$(mktemp /tmp/scheduler-def.XXXXXX.json)
trap 'rm -f "$TEMP_DEF"' EXIT

cat > "$TEMP_DEF" <<JSONEOF
{
  "definition": {
    "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "triggers": {
      "Recurrence": {
        "type": "Recurrence",
        "recurrence": {
          "frequency": "$FREQUENCY",
          "interval": $INTERVAL
        }
      }
    },
    "actions": {
      "Call_Endpoint": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "$ENDPOINT",
          "headers": {
            "x-scheduler-key": "$SCHEDULER_KEY",
            "Content-Type": "application/json"
          },
          "body": {}
        },
        "runAfter": {}
      }
    }
  }
}
JSONEOF

if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
  echo "Logic App exists — updating definition..."
  az logic workflow update \
    --name "$LOGIC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --definition "$TEMP_DEF" \
    --output none
else
  echo "Creating new Logic App..."
  az logic workflow create \
    --name "$LOGIC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --definition "$TEMP_DEF" \
    --output none
fi

cat <<EOF

✓ Done.

  az logic workflow show --name $LOGIC_APP_NAME --resource-group $RESOURCE_GROUP \\
    --query "{state:state, accessEndpoint:accessEndpoint}" -o table

  Disable: az logic workflow update --name $LOGIC_APP_NAME --resource-group $RESOURCE_GROUP --state Disabled
  Enable:  az logic workflow update --name $LOGIC_APP_NAME --resource-group $RESOURCE_GROUP --state Enabled

Cost estimate at recurrence $INTERVAL $FREQUENCY: ~\$$(python3 -c "
freq='$FREQUENCY'; interval=$INTERVAL
per_month = { 'Minute': (60*24*30)//interval, 'Hour': (24*30)//interval, 'Day': 30//interval, 'Week': 4//interval }.get(freq, 0)
print(f'{per_month*0.000025:.2f}')
")/month for 1 HTTP action.
EOF
