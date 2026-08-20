---
id: money
always_apply: false
---
# Money

- `Decimal` in Python, integer minor units or `Decimal` in TS. `float` is banned in any code path touching a currency amount.
- Store currency alongside every amount. There is no default currency.
- Splits and allocations must sum to exactly the total. Assert it; do not trust rounding.
- Rounding rule is declared once, applied everywhere, and tested at boundaries (half-cent, negative, zero).
- Every calculation path has a property test asserting conservation of value.
- Every charge, refund, and payout uses an idempotency key.
- NEVER trust a client-supplied price, quantity, or discount. Recompute server-side from stored records.
- Payment webhooks are verified and deduped like all webhooks; a duplicate must never double-charge or double-pay.
