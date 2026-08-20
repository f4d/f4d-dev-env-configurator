---
id: determinism
always_apply: false
---
# Determinism & Content Addressing

- Canonicalize before hashing. JCS (RFC 8785). Python: `jcs`. TS: `canonicalize`.
- Hash = SHA-256 over canonical bytes. Never hash a dict or object directly.
- FORBIDDEN inside any hashed payload: timestamps, UUIDs generated at call time, file paths, absolute URLs, map iteration order, floats, locale-formatted values.
- Every function producing a hash or content ID has a golden-fixture test: fixed input bytes, exact expected output string, committed.
- Changing a hashing path means a NEW version (v2), never an edit to the existing fixture. Old outputs must remain reproducible forever.
- Pin the encoding explicitly — codec, base, case. Never rely on a library default.
