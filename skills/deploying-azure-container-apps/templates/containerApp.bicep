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

resource app 'Microsoft.App/containerApps@2024-03-01' = {
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
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: string(concurrentRequests)
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
output name string = app.name
output id string = app.id
