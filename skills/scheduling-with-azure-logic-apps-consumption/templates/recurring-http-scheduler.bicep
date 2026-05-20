// Azure Logic App (Consumption tier) — recurring HTTP scheduler.
// Calls an endpoint on a configurable cadence with a shared-secret header.
// Cost: ~8,640 runs/month at 5-minute cadence × $0.000025/action = ~$0.22/month.
//
// Proven pattern: trg-directory-website/scripts/create-recrawl-scheduler.sh
// This Bicep is the IaC equivalent — lives next to the rest of your modules.

@description('Logic App resource name (e.g. {org}-{project}-sched-{env}).')
param name string

@description('Azure region — usually the same as the endpoint resource.')
param location string

@description('Endpoint URL the scheduler will POST to (e.g. https://swa-host/api/_internal/recrawl).')
param endpoint string

@description('Shared secret used for the x-scheduler-key header. Generate per-environment and store as a GitHub secret.')
@secure()
param schedulerSecret string

@description('Recurrence interval value.')
param interval int = 5

@description('Recurrence frequency: Minute | Hour | Day | Week.')
@allowed(['Minute', 'Hour', 'Day', 'Week'])
param frequency string = 'Minute'

@description('Optional JSON body to send with each POST. Default: empty object.')
param requestBody object = {}

@description('Header name carrying the shared secret. Match what the endpoint validates server-side.')
param secretHeaderName string = 'x-scheduler-key'

param tags object = {}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        Recurrence: {
          type: 'Recurrence'
          recurrence: {
            frequency: frequency
            interval: interval
          }
        }
      }
      actions: {
        // Single HTTP POST action with a custom header.
        // If you need additional actions, add them under `actions` with
        // explicit `runAfter` linkage.
        Call_Endpoint: {
          type: 'Http'
          inputs: {
            method: 'POST'
            uri: endpoint
            headers: {
              '${secretHeaderName}': schedulerSecret
              'Content-Type': 'application/json'
            }
            body: requestBody
          }
          runAfter: {}
        }
      }
    }
  }
}

output workflowName string = workflow.name
output workflowId string = workflow.id

// Manual disable/enable from the CLI:
//   az logic workflow update --name <name> --resource-group <rg> --state Disabled
//   az logic workflow update --name <name> --resource-group <rg> --state Enabled
