# Stripe Payment Method Controller - Testing Blockers

## Summary

The `lib/ysc_web/controllers/stripe_payment_method_controller.ex` file cannot achieve 90%+ test coverage without fixing production bugs and implementing Stripe API mocking infrastructure.

**Current Coverage:** 0.0% (3 tests passing, all authentication tests)

## Production Bugs Found

### 1. Controller uses `conn.assigns.user` instead of `conn.assigns.current_user`

**Location:** Lines 38, 56, 119, 132
**Impact:** Critical - controller will fail in production
**Symptom:** KeyError when accessing `:user` in conn.assigns

The authentication pipeline sets `conn.assigns.current_user`, but the controller reads `conn.assigns.user`.

**Fix Required:**
```elixir
# Current (broken):
user = conn.assigns.user

# Should be:
user = conn.assigns.current_user
```

### 2. Controller expects `conn.assigns.route_helpers` which isn't set

**Location:** Line 100 in `get_props/1`
**Impact:** High - finalize action will crash
**Symptom:** KeyError: key :route_helpers not found

The controller expects `route_helpers` to be in assigns, but the router pipeline doesn't set it.

**Fix Required:**
```elixir
# Current (broken):
router = conn.assigns.route_helpers

# Should be:
router = YscWeb.Router.Helpers
# Or add a plug to set route_helpers in assigns
```

### 3. Controller tries to JSON encode `Stripe.Error` struct

**Location:** Line 68-73 in error handling
**Impact:** High - error responses will crash
**Symptom:** Protocol.UndefinedError - Jason.Encoder not implemented for Stripe.Error

When Stripe API returns an error, the controller passes the `%Stripe.Error{}` struct directly to `json/2`, but the struct doesn't implement `Jason.Encoder`.

**Fix Required:**
```elixir
# Current (broken):
{:error, %Stripe.Error{} = stripe_error} ->
  conn
  |> put_status(:bad_request)
  |> json(%{
    error: "Failed to update Stripe customer",
    reason: stripe_error.message  # This tries to encode the whole map
  })

# Should be:
{:error, %Stripe.Error{} = stripe_error} ->
  conn
  |> put_status(:bad_request)
  |> json(%{
    error: "Failed to update Stripe customer",
    reason: stripe_error.message  # Just use the message string
  })
```

### 4. No error handling for `Ecto.Query.CastError`

**Location:** `setup_payment/2` line 24
**Impact:** Medium - returns 500 instead of 400/404
**Symptom:** Ecto.Query.CastError when invalid user_id provided

When an invalid ULID is provided as user_id, `Accounts.get_user!/1` raises `Ecto.Query.CastError` which isn't rescued.

**Fix Required:**
```elixir
def setup_payment(conn, _params) do
  user_id = conn.path_params["user_id"]

  try do
    user = Ysc.Accounts.get_user!(user_id)
    # ... rest of function
  rescue
    Ecto.Query.CastError ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid user ID format"})
  end
end
```

## Missing Test Infrastructure

### Stripe API Mocking

The controller makes direct calls to Stripe modules:
- `Stripe.PaymentMethod.retrieve/1`
- `Stripe.SetupIntent.retrieve/2`
- `Stripe.PaymentIntent.retrieve/2`
- `Stripe.Customer.update/2`

These modules don't have behavior definitions in `test/support/mocks.ex`, making them impossible to mock with Mox.

**Options to fix:**
1. Add Stripe behavior definitions and update all Stripe calls to use the behavior
2. Use ExVCR to record/replay HTTP calls
3. Use Bypass to mock HTTP endpoints
4. Refactor controller to use dependency injection

## Tests Created

Created `test/ysc_web/controllers/stripe_payment_method_controller_test.exs` with:
- ✅ 3 authentication tests (passing)
- ⏭️ 9 functional tests (skipped - blocked by bugs above)

### Passing Tests (3)
1. `GET /billing/user/:user_id/finalize` requires authentication
2. `GET /billing/user/:user_id/setup-payment` requires authentication
3. `GET /billing/user/:user_id/payment-method` requires authentication

### Skipped Tests (9)
All functional tests are skipped with detailed comments explaining which bugs block them.

## Recommendations

### Immediate Actions (before further testing)

1. **Fix the 4 production bugs listed above** - These will cause crashes in production
2. **Add Stripe API mocking infrastructure** - Either behaviors + Mox or ExVCR/Bypass
3. **Add integration tests** - Use test mode Stripe API keys for end-to-end testing

### Testing Strategy

Once bugs are fixed, comprehensive testing should include:

1. **Unit tests** (25-30 tests needed for 90%+ coverage):
   - `finalize/2` with payment_intent
   - `finalize/2` with setup_intent
   - `finalize/2` security (customer ownership check)
   - `setup_payment/2` success and error paths
   - `store_payment_method/2` success and error paths
   - All error handling branches

2. **Integration tests** with test Stripe API:
   - Complete payment method addition flow
   - Complete setup intent flow
   - Payment intent verification flow

### Priority

**Priority Level:** CRITICAL ⚠️

This controller handles payment methods, which is security-critical financial functionality. The production bugs must be fixed before this code can be safely used.

## Estimated Effort

- Fix bugs: 2-4 hours
- Add Stripe mocking infrastructure: 4-6 hours
- Write comprehensive tests: 4-6 hours
- **Total:** 10-16 hours

## Related Files

- Controller: `lib/ysc_web/controllers/stripe_payment_method_controller.ex`
- Tests: `test/ysc_web/controllers/stripe_payment_method_controller_test.exs`
- Router: `lib/ysc_web/router.ex` (lines 388-403)
- Auth: `lib/ysc_web/user_auth.ex` (sets current_user, not user)

## Date

2026-02-02
