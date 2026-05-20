// Azure Communication Services (ACS) Email — transactional email.
// Three quirks baked in:
//   1. location is the literal string 'global', not a real Azure region
//   2. dataLocation uses plain English ('Australia'), not 'australiaeast'
//   3. Declare order: emailService → domain → ACS; NO dependsOn anywhere

param baseName string
param tags object = {}

@description('Data residency. Plain English — e.g. "Australia", "Europe", "United States".')
param dataLocation string = 'Australia'

@description('Use Azure-managed domain (random hash) or set up a customer-managed domain.')
@allowed(['AzureManaged', 'CustomerManaged'])
param domainManagement string = 'AzureManaged'

var emailServiceName = '${baseName}-emailsvc'
var acsName          = '${baseName}-acs'

// Email service — no dependencies
resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: emailServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: dataLocation
  }
}

// Domain — child of emailService
resource emailDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'
  location: 'global'
  tags: tags
  properties: {
    domainManagement: domainManagement
    userEngagementTracking: 'Disabled'
  }
}

// Comms service — links to the domain
resource acs 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: acsName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: dataLocation
    linkedDomains: [ emailDomain.id ]
  }
}

// Outputs — the workflow uses the connection string and the dynamic from-address
#disable-next-line outputs-should-not-contain-secrets
output connectionString string = acs.listKeys().primaryConnectionString
output acsName string = acs.name
output emailServiceName string = emailService.name
output emailDomainName string = emailDomain.name
// Note: the actual from-address (DoNotReply@<hash>.azurecomm.net) is only
// available post-deploy via `az communication email domain show ... --query fromSenderDomain`.
// The workflow should fetch it and set EMAIL_FROM as an app setting.
