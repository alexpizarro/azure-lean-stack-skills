// Container Apps Job — run-to-completion workload, scale-to-zero by nature.
// Supports Manual, Schedule, and Event triggers.

param name string
param location string
param tags object = {}
param environmentId string

param image string

@allowed(['Manual', 'Schedule', 'Event'])
param triggerType string = 'Manual'

@description('Max wall-clock duration of one replica (seconds).')
param replicaTimeout int = 1800

@description('Retries per replica before the run is considered failed.')
param replicaRetryLimit int = 0

@description('Cron expression — only used when triggerType = Schedule.')
param cronExpression string = '0 2 * * *'

@description('KEDA scale rules — REQUIRED when triggerType = Event (e.g. [{ name: \'queue\', type: \'azure-queue\', metadata: { queueName: \'jobs\', queueLength: \'5\', accountName: \'mystorage\' }, auth: [...] }]). See references/aca-jobs.md.')
param eventScaleRules array = []

@description('Event trigger: max parallel executions.')
param eventMaxExecutions int = 10

@description('Event trigger: seconds between scaler polls.')
param eventPollingInterval int = 30

param cpu string = '0.5'
param memory string = '1Gi'

@description('Plain env vars as name→value object.')
param envVars object = {}

@description('Secret names that will be set via az CLI post-deploy.')
param secretNames array = []

@description('Env var → secret name mapping.')
param secretEnvVars object = {}

@description('Optional ACR registry server.')
param registryServer string = ''

@description('Optional managed identity for ACR pull.')
param registryIdentity string = ''

var plainEnv = [for k in items(envVars): {
  name: k.key
  value: k.value
}]

var secretEnv = [for k in items(secretEnvVars): {
  name: k.key
  secretRef: k.value
}]

// Hoisted: a for-expression is not allowed inside union() (BCP138) — build the list here.
var secretList = [for s in secretNames: {
  name: s
  #disable-next-line use-secure-value-for-secure-inputs
  value: 'set-by-github-actions'
}]

var triggerConfig = triggerType == 'Schedule' ? {
  scheduleTriggerConfig: {
    cronExpression: cronExpression
    parallelism: 1
    replicaCompletionCount: 1
  }
} : (triggerType == 'Event' ? {
  eventTriggerConfig: {
    parallelism: 1
    replicaCompletionCount: 1
    scale: {
      minExecutions: 0
      maxExecutions: eventMaxExecutions
      pollingInterval: eventPollingInterval
      rules: eventScaleRules   // an Event job with no rules never triggers — pass at least one
    }
  }
} : {
  manualTriggerConfig: {
    parallelism: 1
    replicaCompletionCount: 1
  }
})

resource job 'Microsoft.App/jobs@2025-01-01' = {
  name: name
  location: location
  tags: tags
  identity: !empty(registryIdentity) ? {
    type: 'UserAssigned'
    userAssignedIdentities: { '${registryIdentity}': {} }
  } : null
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: union({
      triggerType: triggerType
      replicaTimeout: replicaTimeout
      replicaRetryLimit: replicaRetryLimit
      registries: empty(registryServer) ? [] : [
        { server: registryServer, identity: registryIdentity }
      ]
      secrets: secretList
    }, triggerConfig)
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
        }
      ]
    }
  }
}

output name string = job.name
output id string = job.id
