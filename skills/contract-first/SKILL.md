---
name: contract-first
description: Define or change a cross-repo contract — API endpoint, webhook event, or shared schema — in the contract repo first, then propagate generated types to consumers. Use whenever a payload, event, or endpoint shape is added or changed in a multi-repo project, or when the user says "add an event", "change the payload", "new endpoint between services".
---

# Contract First

The order is not negotiable: **spec → generate → pin → implement.** Implementing first and back-filling the spec is how five services end up disagreeing.

## Adding or changing a shape

1. **Write the spec** in the contract repo — JSON Schema for events, OpenAPI for endpoints.
   Every event carries: `event_id` (UUIDv7), `occurred_at`, `event_type`, `version`.
2. **Classify the change:**
   - Adding an optional field → minor
   - Adding a required field, removing a field, retyping a field, renaming an event → **major**, and every consumer must be listed and checked
3. **Generate bindings:**
   ```
   npx openapi-typescript openapi/<svc>.yaml -o codegen/ts/<svc>.d.ts
   uvx datamodel-code-generator --input schemas/ --input-file-type jsonschema \
     --output-model-type pydantic_v2.BaseModel --output codegen/py/models.py
   ```
4. **Version and publish** the contract package. Commit generated output as generated.
5. **Pin in each consumer** — its own commit, its own PR, per repo.
6. **Implement** against the generated type. Never re-declare the shape locally.
7. **Run `contract-drift-checker`** in every affected repo before merging.

## Signature convention for webhooks

- Header: `X-{ORG}-Signature: sha256={hmac}`, plus `X-{ORG}-Sender` and `X-{ORG}-Timestamp`
- Sign `{timestamp}.{raw_body}`; reject over 5 minutes old
- Pick one org-level prefix at setup and use it in every repo. Do not name the header after one sender — every service both sends and receives eventually
