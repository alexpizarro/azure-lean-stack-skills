---
name: adding-azure-communication-services-email
description: Adds transactional email to an Azure web app via Azure Communication Services (ACS) Email — verification emails, password resets, notifications. Encodes the three ACS quirks that consistently break Bicep deploys (location:'global' literal, dataLocation in plain English not Azure region IDs, declare-order to avoid circular dependency), and the safeSend() wrapper that prevents email failures from crashing HTTP handlers. Use when adding email sending to a project, fixing ACS Bicep deployment errors, or migrating off SendGrid/Mailgun.
---

# Adding Azure Communication Services Email

Transactional email via Azure Communication Services. **Free tier: 100 emails/day**, then $0.00025/email. Cheaper than SendGrid for low-volume projects.

## When to use ACS Email

| Need | Use |
|------|-----|
| Account verification, password reset, transactional notifications | **ACS Email** (this skill) |
| Marketing campaigns, newsletters, A/B testing | A marketing-focused provider (Mailchimp, etc.) — ACS doesn't do that |
| High-volume bulk send (>100k/day) | SendGrid Pro or Mailgun (ACS gets expensive at scale) |

## The three ACS quirks

### 1. `location: 'global'` (literal string, not a real Azure region)

```bicep
resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: emailServiceName
  location: 'global'                  // ← NOT 'australiaeast', NOT location param
  properties: { dataLocation: 'Australia' }
}
```

If you pass the project's `location` param (`australiaeast`), Azure rejects the deploy.

### 2. `dataLocation` uses plain English

The values for `dataLocation` are not Azure region IDs. They're region groupings:

| `dataLocation` value | Where data is stored |
|---------------------|---------------------|
| `'Australia'` | AU data centres |
| `'Europe'` | EU |
| `'United States'` | US |
| `'Asia Pacific'` | APAC excluding AU |
| `'Africa'` | Africa |
| `'Brazil'` | Brazil |
| `'Canada'` | Canada |
| `'France'` | France |
| `'Germany'` | Germany |
| `'India'` | India |
| `'Japan'` | Japan |
| `'Korea'` | Korea |
| `'Norway'` | Norway |
| `'Switzerland'` | Switzerland |
| `'UAE'` | UAE |
| `'United Kingdom'` | UK |

Use `'Australia'` — not `'australiaeast'`, not `'au'`, not `'aus'`.

### 3. Declare-order — no `dependsOn` on email service + domain

ACS resources have an awkward circular dependency: the ACS resource needs to know about the domain, but `linkedDomains` + `dependsOn` causes deployment failures.

**Declare in this order, with no `dependsOn`:**

```bicep
// 1. Email service (no dependencies)
resource emailService 'Microsoft.Communication/emailServices@2023-04-01' = {
  name: emailServiceName
  location: 'global'
  properties: { dataLocation: 'Australia' }
}

// 2. Domain — child of emailService
resource emailDomain 'Microsoft.Communication/emailServices/domains@2023-04-01' = {
  parent: emailService
  name: 'AzureManagedDomain'        // or your custom domain
  location: 'global'
  properties: {
    domainManagement: 'AzureManaged'    // or 'CustomerManaged'
    userEngagementTracking: 'Disabled'
  }
}

// 3. Comms service — links to the domain via linkedDomains
resource acs 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: acsName
  location: 'global'
  properties: {
    dataLocation: 'Australia'
    linkedDomains: [ emailDomain.id ]
  }
}
```

No `dependsOn` blocks anywhere — the implicit dependency through `parent:` and `linkedDomains:` is enough.

## The Azure-managed domain has an unknown name

When using `AzureManagedDomain`, the actual sending address looks like:

```
DoNotReply@<random-hash>.azurecomm.net
```

You can't predict the hash before deployment. Retrieve it post-deploy:

```bash
az communication email domain show \
  --resource-group "$RG" \
  --email-service-name "$EMAIL_SERVICE_NAME" \
  --name AzureManagedDomain \
  --query "fromSenderDomain" -o tsv
```

Set `EMAIL_FROM` as a SWA / Function App setting after the first deploy.

## The `safeSend()` wrapper

`@azure/communication-email` uses an async poller — `beginSend()` returns immediately, you call `pollUntilDone()`. If pollUntilDone() throws (network error, quota, etc.), your HTTP handler crashes with a 500.

Wrap it:

```typescript
import { EmailClient } from '@azure/communication-email';

const client = new EmailClient(process.env.ACS_CONNECTION_STRING!);

export async function safeSend(message: {
  senderAddress: string;
  recipients: { to: { address: string }[] };
  content: { subject: string; plainText?: string; html?: string };
}): Promise<{ ok: true; messageId: string } | { ok: false; error: string }> {
  try {
    const poller = await client.beginSend(message);
    const result = await poller.pollUntilDone();
    if (result.status === 'Succeeded') {
      return { ok: true, messageId: result.id };
    }
    return { ok: false, error: result.error?.message ?? `status=${result.status}` };
  } catch (err: any) {
    // Log but never throw — email failure must not crash the HTTP handler
    console.error('Email send failed:', err);
    return { ok: false, error: err.message ?? String(err) };
  }
}
```

Then call from your handler:

```typescript
const result = await safeSend({
  senderAddress: process.env.EMAIL_FROM!,
  recipients: { to: [{ address: user.email }] },
  content: {
    subject: 'Verify your email',
    html: renderVerifyEmail(token),
  },
});

if (!result.ok) {
  ctx.warn(`Email send failed for ${user.email}: ${result.error}`);
  // Continue — perhaps queue for retry, but don't fail the user's signup
}
```

## Custom domains

To send from `noreply@yourdomain.com`, set `domainManagement: 'CustomerManaged'`. Then:

1. ACS gives you DNS records (SPF, DKIM, DMARC) to add
2. After DNS propagates, run `az communication email domain initiate-verification`
3. Use the custom sender address in `senderAddress`

The Azure-managed domain is fine for prototypes and internal tools.

## Pricing

- 100 emails/day free
- $0.00025/email above that
- Attachments billed extra at $0.0002/MB

For a 1000-user app doing ~5 transactional emails/user/month (5k/month), cost is ~$1.25/month.

## Composes with

- [scaffolding-azure-bicep-infrastructure](../scaffolding-azure-bicep-infrastructure/SKILL.md) — add ACS as an optional module
- [deploying-azure-static-web-apps](../deploying-azure-static-web-apps/SKILL.md) — the API calls `safeSend()` from a managed function
- [diagnosing-azure-deployment-failures](../diagnosing-azure-deployment-failures/SKILL.md) — for ACS-specific deploy errors

## Templates

| File | Purpose |
|------|---------|
| [templates/acs.bicep](templates/acs.bicep) | Email service + Azure-managed domain + ACS resource |
