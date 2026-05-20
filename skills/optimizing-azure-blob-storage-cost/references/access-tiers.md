# Storage account access tiers, SKUs, and redundancy

## Account-level access tier

Set on the storage account itself; affects new blobs unless overridden by lifecycle rules:

```bicep
properties: { accessTier: 'Hot' }   // or 'Cool'
```

| When | Set account `accessTier` to |
|------|---------------------------|
| Most blobs accessed regularly | `Hot` (default) |
| Most blobs written once and rarely read | `Cool` |
| Mixed: use `Hot` + lifecycle rules to age down |

## SKU (replication)

| SKU | Cost vs LRS | Replication | When |
|-----|-------------|-------------|------|
| `Standard_LRS` | 1× | 3 copies within one datacenter | Default. Most projects. |
| `Standard_ZRS` | ~1.5× | 3 copies across AZs in one region | Critical data within a region |
| `Standard_GRS` | ~2× | LRS + async copy to a paired region | DR/compliance |
| `Standard_RAGRS` | ~2.1× | GRS + read access to secondary | Active-passive multi-region read |
| `Standard_GZRS` | ~2.5× | ZRS + async copy to a paired region | Highest standard tier |
| `Premium_LRS` | ~10× per IOP | SSD-backed | High-IOPS workloads (rare for blob) |

**Default to `Standard_LRS`** unless you have a written DR requirement.

## Performance tier

| Tier | Use |
|------|-----|
| `Standard` | Default — HDD-backed, cheapest |
| `Premium` | SSD-backed, low latency, higher cost per GB but cheaper per IOP |

Premium is mostly for page blobs (VM disks) — block blobs don't usually need it.

## Cost rough order

For a 100 GB workload with light access:

| Configuration | Approx monthly storage cost |
|---------------|----------------------------|
| Hot LRS | $2 |
| Cool LRS | $1 |
| Cold LRS | $0.40 |
| Hot GRS | $4 |
| Premium LRS | $20+ |

Reads/writes/operations add a small per-transaction cost; usually negligible at low volumes.

## Don't bother with

- **Reserved capacity** for low-volume projects — only worth it at >100 TB scale
- **Object replication** — adds operational complexity rarely justified
- **Premium block blob storage** — only if you're hitting IOPS limits on Standard, which is rare

## Public access flags

Two layers:

| Setting | Where | What it does |
|---------|-------|--------------|
| `allowBlobPublicAccess` | account | Master switch. If `false`, NO container can have public access |
| `publicAccess` | container | Per-container: `None` / `Blob` (read individual blobs) / `Container` (list+read) |

The default scaffold sets `allowBlobPublicAccess: true` only when at least one public-read container exists (e.g. `branding`); otherwise sets it to `false` for defence in depth.

## Verifying current state

```bash
# Tier of a specific blob
az storage blob show --account-name "$SA" --container-name "$C" --name "$B" \
  --query "{tier:properties.blobTier,size:properties.contentLength}" -o json

# All containers + their public-access settings
az storage container list --account-name "$SA" \
  --query "[].{name:name, publicAccess:properties.publicAccess}" -o table
```
