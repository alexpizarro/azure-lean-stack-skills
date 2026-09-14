// HTTP Container App on the Consumption workload profile with scale-to-zero.
// Secrets are wired with placeholder values — GitHub Actions sets the real values
// post-deploy via `az containerapp secret set`.

param name string
param location string
param tags object = {}
param managedEnvironmentId string

@description('Container image (e.g. ghcr.io/org/app:0.5.0).')
param image string

@description('Container target port for ingress.')
param targetPort int = 8000

@description('Min replicas. 0 = scale-to-zero (lowest cost, cold-start latency).')
param minReplicas int = 0

@description('Max replicas.')
param maxReplicas int = 3

@description('CPU cores per container (decimal).')
param cpu string = '0.5'

@description('Memory per container.')
param memory string = '1Gi'

@description('Concurrent requests per replica before scaling up.')
param concurrentRequests int = 10

// "The second minReplicas" (cost-guardrails Guardrail #12b, gotcha #42). Seconds the
// last replica stays alive after traffic stops. If this exceeds your mean inter-arrival
// time the app NEVER scales to zero, invisibly. Leave at the 300s default; for a known
// busy window use the optional KEDA cron rule below instead of raising this.
@description('Scale-to-zero cooldown (seconds). Keep at 300 — raising it is a hidden always-on replica.')
param cooldownPeriod int = 300

// Optional warm window — a KEDA `cron` rule that pins `warmReplicas` between two cron
// expressions in an IANA timezone (DST handled by the platform). KEDA takes max(rules),
// so HTTP scaling still works inside the window and the app sleeps at 0 outside it.
// Proven: bcci-app (BC Quick Check In) — replaced a 7200s cooldown that cost A$56/mo
// with a Tue 17:45–23:30 window costing ~A$0.02/day.
@description('Optional warm window: cron start expression (e.g. "45 17 * * 2"). Empty = no cron rule.')
param warmWindowStart string = ''

@description('Warm window: cron end expression (e.g. "30 23 * * 2"). Required together with warmWindowStart.')
param warmWindowEnd string = ''

@description('Warm window: IANA timezone (e.g. "Australia/Sydney").')
param warmWindowTimezone string = 'Australia/Sydney'

@description('Warm window: replicas to hold during the window.')
param warmReplicas int = 1

@description('Ingress external (public) or internal (env-only).')
param ingressExternal bool = true

@description('Plain (non-secret) env vars as a name→value object.')
param envVars object = {}

@description('Secret names that will be set via az CLI post-deploy. Bicep creates placeholder values.')
param secretNames array = []

@description('Env var → secret name mapping (e.g. {API_KEY: "api-key"}).')
param secretEnvVars object = {}

@description('Optional ACR registry server (e.g. myacr.azurecr.io). Leave empty for public images.')
param registryServer string = ''

@description('Optional managed identity for ACR pull (Bicep resource id of the UAMI).')
param registryIdentity string = ''

var plainEnv = [for k in items(envVars): {
  name: k.key
  value: k.value
}]

var secretEnv = [for k in items(secretEnvVars): {
  name: k.key
  secretRef: k.value
}]

var httpRule = {
  name: 'http-scaling'
  http: {
    metadata: {
      concurrentRequests: string(concurrentRequests)
    }
  }
}

var cronRule = {
  name: 'warm-window'
  custom: {
    type: 'cron'
    metadata: {
      timezone: warmWindowTimezone
      start: warmWindowStart
      end: warmWindowEnd
      desiredReplicas: string(warmReplicas)
    }
  }
}

// The cron rule is only emitted when BOTH start and end are set (KEDA rejects an empty end).
var scaleRules = (empty(warmWindowStart) || empty(warmWindowEnd)) ? [httpRule] : [httpRule, cronRule]

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: name
  location: location
  tags: tags
  identity: !empty(registryIdentity) ? {
    type: 'UserAssigned'
    userAssignedIdentities: { '${registryIdentity}': {} }
  } : null
  properties: {
    managedEnvironmentId: managedEnvironmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: ingressExternal
        targetPort: targetPort
        transport: 'auto'
      }
      registries: empty(registryServer) ? [] : [
        {
          server: registryServer
          identity: registryIdentity
        }
      ]
      secrets: [for s in secretNames: {
        name: s
        #disable-next-line use-secure-value-for-secure-inputs
        value: 'set-by-github-actions'
      }]
    }
    template: {
      containers: [
        {
          name: name
          image: image
          env: concat(plainEnv, secretEnv)
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          probes: [
            {
              type: 'liveness'
              httpGet: { path: '/health', port: targetPort }
              initialDelaySeconds: 10
              periodSeconds: 30
            }
            {
              type: 'readiness'
              httpGet: { path: '/health', port: targetPort }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        cooldownPeriod: cooldownPeriod
        // Non-HTTP scale rules (cron) require activeRevisionsMode: 'Single' (set above).
        rules: scaleRules
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output name string = app.name
output id string = app.id
