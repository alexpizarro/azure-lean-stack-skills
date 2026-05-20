# Lifecycle rules — patterns

Lifecycle rules are JSON policies on the storage account that the Storage service evaluates daily. They can: change access tier, delete blobs, delete snapshots/versions.

## Common patterns

### 1. Delete temp blobs after N days

```bicep
{
  name: 'delete-stale-temp-blobs'
  type: 'Lifecycle'
  enabled: true
  definition: {
    filters: {
      blobTypes: ['blockBlob']
      prefixMatch: ['incoming/', 'processor-jobs/', 'tmp/']
    }
    actions: {
      baseBlob: { delete: { daysAfterModificationGreaterThan: 7 } }
    }
  }
}
```

### 2. Tier ageing content from Hot → Cool → Cold (online tiers only)

```bicep
{
  name: 'tier-aging-content'
  type: 'Lifecycle'
  enabled: true
  definition: {
    filters: {
      blobTypes: ['blockBlob']
      prefixMatch: ['videos/', 'images/']
    }
    actions: {
      baseBlob: {
        tierToCool: { daysAfterModificationGreaterThan: 60 }
        tierToCold: { daysAfterModificationGreaterThan: 180 }
        // NO tierToArchive — keeps content instantly accessible
      }
    }
  }
}
```

### 3. Delete versions / snapshots after N days

```bicep
{
  name: 'delete-old-versions'
  type: 'Lifecycle'
  enabled: true
  definition: {
    filters: { blobTypes: ['blockBlob'] }
    actions: {
      version: { delete: { daysAfterCreationGreaterThan: 30 } }
      snapshot: { delete: { daysAfterCreationGreaterThan: 30 } }
    }
  }
}
```

### 4. Tier on read access (less common — needs `daysAfterLastAccessTimeGreaterThan`)

Requires last-access tracking enabled on the account:

```bicep
properties: {
  // On the storage account
  lastAccessTimeTrackingPolicy: {
    enable: true
    name: 'AccessTimeTracking'
    trackingGranularityInDays: 1
  }
}
```

Then:

```bicep
actions: {
  baseBlob: {
    tierToCool: { daysAfterLastAccessTimeGreaterThan: 30 }
  }
}
```

This is more accurate for content where age doesn't predict access pattern but enabling tracking has a small cost.

## When rules fire

- Rules are evaluated **once per day**, not in real time
- Effects: a blob that crosses the boundary at 03:00 doesn't change tier until the next daily run, usually within 24 hours
- Newly created/modified blobs always start in the account's default `accessTier` (usually Hot) — lifecycle then moves them

## Hot vs Cool vs Cold vs Archive

| Tier | Storage cost | Read cost | Latency | Use for |
|------|--------------|-----------|---------|---------|
| **Hot** | Highest | Lowest | Instant | Frequently accessed; default for new content |
| **Cool** | Lower | Higher per read | Instant | Accessed monthly; 30-day minimum retention or early-deletion penalty |
| **Cold** | Lowest online | Higher | Instant | Accessed quarterly; 90-day minimum retention |
| **Archive** | Cheapest by far | Rehydration required | **1–15 hours** | Long-term backups, compliance retention. NOT for playable content. |

Minimums for tiering down:
- Hot → Cool: any time
- Cool → Cold: needs to have been in Cool for some period (early-deletion penalty up to 30 days)
- Cold → anywhere: 90-day minimum or penalty

## Anti-patterns

- **Archive for media**: rehydration kills UX
- **Lifecycle rule conflicts**: two rules touching the same prefix — last-write wins, but behaviour is unpredictable
- **Tiering small blobs**: per-blob tiering overhead can exceed storage savings for blobs <128 KiB
- **Aggressive deletion**: `daysAfterModificationGreaterThan: 1` for temp blobs can race with the actual processor

## Verifying

```bash
# What's the active policy?
az storage account management-policy show \
  --account-name "$STORAGE_NAME" \
  --resource-group "$RG"

# Storage analytics — which blobs were tiered/deleted last 24h?
# (Requires Storage diagnostic logs to a Log Analytics workspace)
```
