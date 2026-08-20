---
id: storage
always_apply: false
---
# Object Storage

Configured per project. Do not assume this policy applies elsewhere.

- One bucket per environment. Never share a bucket between dev and prod.
- Key layout is declared here and never improvised:
  `{tenant}/{entity}/{entity_id}/{purpose}/{filename}`
- NEVER put PII, email addresses, or user-supplied names in a key. Use IDs.
- Uploads: presigned URLs, direct to storage. The API never proxies file bytes.
- Enforce max size and allowed content types at presign time, not after upload.
- Store the original untouched. Derivatives (thumbnails, transcodes, waveforms) live under a separate prefix and are regenerable.
- Record for every object: key, size, content type, checksum, uploaded_at, uploader.
- Public access is opt-in per object, never per bucket. Default deny.
- Lifecycle rules are declared in IaC, not clicked in a console.
- Local development uses a compatible local service, never a real bucket.
