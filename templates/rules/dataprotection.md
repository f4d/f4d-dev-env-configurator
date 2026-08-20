---
id: dataprotection
always_apply: false
---
# Data Protection

- Maintain a PII inventory in the README: which tables and fields hold personal data.
- PII never appears in: logs, storage keys, URLs, query strings, error messages, analytics events, or committed fixtures.
- Fixtures derived from real data are redacted in the same commit that creates them. Never "redact later."
- Retention and deletion paths exist before the data does. A record you cannot delete is a liability.
- Encrypt at rest by default; encrypt in transit always.
- Access to personal data is logged.
