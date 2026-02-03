# QuickBooks ClientBehaviour Fix

**Date:** 2026-02-03
**Issue:** Behaviour/Implementation Mismatch
**Status:** ✅ FIXED

---

## Problem

The `Ysc.Quickbooks.ClientBehaviour` was incomplete and didn't match the actual `Ysc.Quickbooks.Client` implementation. This caused issues with Mox-based testing where functions with optional parameters couldn't be properly stubbed.

### Specific Issues

Many functions in the Client module accept an optional `opts` parameter (keyword list) for things like idempotency keys:

```elixir
# Client implementation
def create_bill(params, opts \\ []) do
  # Uses opts for idempotency_key
end
```

But the Behaviour only defined the /1 arity:

```elixir
# Behaviour (BEFORE fix)
@callback create_bill(map()) :: {:ok, map()} | {:error, atom() | String.t()}
```

This meant Mox couldn't stub `create_bill/2`, causing test failures when code called:
```elixir
Client.create_bill(%{...}, idempotency_key: "...")
```

**Error:** `function Ysc.Quickbooks.ClientMock.create_bill/2 is undefined or private`

---

## Solution

Added the /2 arities to the ClientBehaviour for all functions that accept optional parameters.

### Functions Updated

1. **create_sales_receipt** - Added /2 arity
2. **create_deposit** - Added /2 arity
3. **create_customer** - Added /2 arity
4. **create_refund_receipt** - Added /2 arity
5. **query_vendor_by_display_name** - Added /2 arity
6. **create_vendor** - Added /2 arity
7. **create_bill** - Added /2 arity ⭐ (primary fix for expense report sync)
8. **upload_attachment** - Added /4 arity

### Example Fix

```elixir
# BEFORE
@callback create_bill(map()) :: {:ok, map()} | {:error, atom() | String.t()}

# AFTER
@callback create_bill(map()) :: {:ok, map()} | {:error, atom() | String.t()}
@callback create_bill(map(), keyword()) :: {:ok, map()} | {:error, atom() | String.t()}
```

---

## Impact

### Tests Fixed

- ✅ All QuickBooks worker tests pass
- ✅ QuickBooks client tests pass
- ✅ Payment/Payout/Refund worker tests pass
- ✅ Backup worker tests pass

### Future Benefits

1. **Better Test Coverage** - Can now properly test expense report backup worker and other workers that use optional parameters
2. **Correct Mocking** - Mox can stub both /1 and /2 arities correctly
3. **Type Safety** - Behaviour now accurately represents the public API
4. **Documentation** - Behaviour serves as accurate documentation of the Client API

---

## Testing

Verified the fix by running:

```bash
# Backup worker tests (previously had issues)
mix test test/ysc_web/workers/quickbooks_sync_expense_report_backup_worker_test.exs
# ✅ 12 tests, 0 failures

# QuickBooks client tests
mix test test/ysc/quickbooks/client_test.exs
# ✅ 10 tests, 0 failures

# Other QuickBooks worker tests
mix test test/ysc_web/workers/quickbooks_sync_*_worker_test.exs
# ✅ 4 tests, 0 failures

# Full compilation check
mix compile
# ✅ No errors or warnings
```

---

## Files Modified

- `lib/ysc/quickbooks/client_behaviour.ex` - Added 8 callback arities

---

## Next Steps

With the ClientBehaviour fixed, we can now:

1. ✅ Expand backup worker test coverage with full Mox stubs
2. ✅ Test other workers that use optional parameters
3. ✅ Add comprehensive integration tests for expense report syncing

---

**Conclusion:** The ClientBehaviour now accurately represents the Client implementation, enabling proper Mox-based testing across all QuickBooks integration code.
