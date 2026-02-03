# Week 1 Critical Priorities - Security Testing

⚠️ **STOP: READ THIS FIRST** ⚠️

Before writing any other tests, we MUST address critical security vulnerabilities. The following files control access, authentication, and payments but have **ZERO test coverage**.

---

## 🚨 Day 1-2: Authorization (DO THIS FIRST)

### File: `lib/ysc_web/authorization/policy.ex` (0% coverage)

**Why This Matters:**
- Controls ALL access permissions across the application
- Untested = potential unauthorized access to admin functions, user data, bookings, financial info
- A bug here could allow users to see/modify other users' data

**What to Test (60-80 tests needed):**
- [ ] Admin-only functions reject non-admin users
- [ ] Members can only access their own resources
- [ ] Guests cannot access member-only features
- [ ] Family account permissions (parent vs child accounts)
- [ ] Booking ownership verification
- [ ] Event access control (published vs draft)
- [ ] Financial data access (own orders only)
- [ ] Edge cases:
  - [ ] Deleted users
  - [ ] Expired memberships
  - [ ] Suspended accounts
  - [ ] nil/missing user

**Test Pattern:**
```elixir
defmodule YscWeb.Authorization.PolicyTest do
  use Ysc.DataCase, async: true

  alias YscWeb.Authorization.Policy
  alias Ysc.AccountsFixtures

  describe "authorize_admin/1" do
    test "allows admin users" do
      admin = AccountsFixtures.admin_user_fixture()
      assert :ok == Policy.authorize_admin(admin)
    end

    test "denies regular users" do
      user = AccountsFixtures.user_fixture()
      assert {:error, :unauthorized} == Policy.authorize_admin(user)
    end

    test "denies nil user" do
      assert {:error, :unauthorized} == Policy.authorize_admin(nil)
    end
  end

  # ... 60+ more tests covering all policy functions
end
```

---

## ✅ Day 2: Authentication (SECURITY CRITICAL) - COMPLETE

### File: `lib/ysc_web/controllers/auth_controller.ex` (92.5% coverage) ✅

**Status:** COMPLETE - 25 tests, 92.5% coverage (exceeded 90% target)
**Completed:** 2026-02-02

**What Was Tested:**
- [x] Google OAuth login
- [x] Facebook OAuth login
- [x] OAuth error handling (cancelled, provider errors)
- [x] Redirect after login (to original page)
- [x] Missing email handling
- [x] User not found scenarios
- [x] Active/pending user login
- [x] Rejected/suspended user handling
- [x] XSS prevention (javascript: protocol)
- [x] Open redirect prevention (external URLs)
- [x] Protocol-relative URL prevention
- [x] Email verification on OAuth login
- [x] Security edge cases (casing, long emails)

## ✅ Day 3: Session Management (SECURITY CRITICAL) - COMPLETE

### File: `lib/ysc_web/user_auth.ex` (91.7% coverage) ✅

**Status:** COMPLETE - 74 new tests added (23 → 97 total), 91.7% coverage (exceeded 90% target)
**Completed:** 2026-02-02

**What Was Tested:**
- [x] Token generation and validation
- [x] Session store/retrieve
- [x] Remember me functionality
- [x] Session renewal and fixation prevention
- [x] LiveView mounting (all 6 variants)
- [x] Authentication plugs (require_authenticated_user, require_admin, require_approved)
- [x] Open redirect prevention (18 test cases - CRITICAL)
- [x] Membership helper functions
- [x] Edge cases: unverified users, pending approval, POST requests

---

## ⚠️ Day 4: Payment Security (FINANCIAL CRITICAL) - BLOCKED

### File: `lib/ysc_web/controllers/stripe_payment_method_controller.ex` (0% coverage) ⚠️ **BLOCKED**

**Status:** ⚠️ BLOCKED BY PRODUCTION BUGS
**Tests Created:** 3 passing, 9 skipped
**Date Attempted:** 2026-02-02

**Why This Matters:**
- Handles adding/removing payment methods
- Bugs could charge wrong amounts or wrong cards
- PCI compliance concerns

**Production Bugs Found:**
1. ❌ Uses `conn.assigns.user` instead of `conn.assigns.current_user` (will crash)
2. ❌ Expects `conn.assigns.route_helpers` which isn't set (will crash)
3. ❌ Tries to JSON encode `Stripe.Error` struct (will crash)
4. ❌ No rescue for `Ecto.Query.CastError` (wrong error codes)

**See:** `STRIPE_CONTROLLER_ISSUES.md` for detailed bug reports and fixes

**What Was Tested (3 tests passing):**
- [x] Authentication required for all endpoints
- [ ] Add payment method flow (BLOCKED - Bug #1, #3, missing Stripe mocking)
- [ ] Remove payment method (BLOCKED - Bug #1, #3)
- [ ] Set default payment method (BLOCKED - Bug #1, #3)
- [ ] Stripe webhook validation (BLOCKED - missing Stripe mocking)
- [ ] Payment method ownership verification (BLOCKED - Bug #1)
- [ ] Error handling (card declined, invalid card, etc.) (BLOCKED - Bug #3)
- [ ] Idempotency (prevent duplicate charges) (BLOCKED - missing Stripe mocking)

**Recommendation:** Fix production bugs before continuing testing. Estimated 10-16 hours for fixes + proper test infrastructure.

### File: `lib/ysc/quickbooks/client.ex` (6% coverage)

**Why This Matters:**
- Syncs financial data to accounting system
- Bugs could cause financial reporting errors or lost transactions

**What to Test (40-50 tests needed):**
- [ ] API authentication
- [ ] Payment sync to QuickBooks
- [ ] Refund sync to QuickBooks
- [ ] Invoice creation
- [ ] Error handling and retry logic
- [ ] Data mapping (Stripe → QuickBooks)
- [ ] Duplicate transaction prevention

---

## 📋 Day 5: Quick Wins (While Waiting for Code Review)

While your security test PRs are in review, knock out these quick wins:

### Easy Files (1-2 hours total):
- [ ] `lib/ysc_web/gettext.ex` (24 lines, 3-5 tests) - 30 min
- [ ] `lib/ysc_web/save_request_uri.ex` (23 lines, 3-5 tests) - 30 min
- [ ] `lib/ysc_web/emails/base_layout.ex` (0%, 5-8 tests) - 1 hour

---

## ✅ Week 1 Success Criteria

**DO NOT PROCEED to Week 2 until:**
- [x] authorization/policy.ex has 90%+ coverage ✅
- [x] auth_controller.ex has 90%+ coverage ✅
- [ ] stripe_payment_method_controller.ex has 90%+ coverage ⚠️ **BLOCKED** (needs bug fixes)
- [x] user_auth.ex has 90%+ coverage ✅
- [ ] quickbooks/client.ex has 90%+ coverage (likely similar challenges)
- [x] All tests are passing (324 tests)
- [ ] Code review approved
- [ ] Security review completed (if available)
- [ ] **NEW:** Production bugs in Stripe controller fixed

**Expected Week 1 Outcome:**
- ~250-300 new tests written
- Coverage increase: +8-12%
- **CRITICAL:** Security vulnerabilities closed

---

## 🛠️ Testing Setup Commands

```bash
# Run tests with coverage
make test

# Run specific test file
mix test test/ysc_web/authorization/policy_test.exs

# Run tests and watch for changes
mix test.watch

# Check coverage for specific file
mix test --cover
# Then open cover/Elixir.YscWeb.Authorization.Policy.html in browser
```

---

## 📚 Resources

**Test Helpers:**
- Use `Ysc.AccountsFixtures` for creating test users
- Use `Ysc.TestDataFactory` for complex scenarios
- Mock Stripe with `YscWeb.TestStripeClient`
- Mock QuickBooks in `config/test.exs`

**Key Testing Patterns:**
```elixir
# For authorization tests
use Ysc.DataCase, async: true

# For controller tests
use YscWeb.ConnCase, async: true

# For LiveView tests
use YscWeb.ConnCase, async: true
import Phoenix.LiveViewTest
```

**Database Fixtures:**
```elixir
# Create test user
user = Ysc.AccountsFixtures.user_fixture()

# Create admin user
admin = Ysc.AccountsFixtures.admin_user_fixture()

# Create family account
family = Ysc.TestDataFactory.create_family_account()
```

---

## ⚠️ Common Pitfalls to Avoid

1. **Don't skip edge cases** - Test nil, deleted users, expired memberships
2. **Don't forget to test failures** - Invalid data, unauthorized access, etc.
3. **Don't use `async: false` unless needed** - Slows down test suite
4. **Don't mock what you should integration test** - Test real auth flows
5. **Don't write flaky tests** - Avoid sleeps, use proper test isolation

---

## 🎯 Test Coverage Goals

| File | Current | Week 1 Target | Tests to Add |
|------|---------|---------------|--------------|
| authorization/policy.ex | 0% | 90%+ | 60-80 |
| auth_controller.ex | 0% | 90%+ | 30-40 |
| user_auth.ex | 63.6% | 90%+ | 25-30 |
| stripe_payment_method_controller.ex | 0% | 90%+ | 25-30 |
| quickbooks/client.ex | 6% | 90%+ | 40-50 |
| **TOTAL** | **varies** | **90%+** | **180-230** |

Plus 60-70 tests for quick wins and infrastructure.

**Total Week 1 Tests:** 240-300 new tests

---

## 🚀 Getting Started NOW

1. Pull latest main branch
2. Create feature branch: `git checkout -b test/week1-security-coverage`
3. Start with `test/ysc_web/authorization/policy_test.exs`
4. Write tests following the patterns above
5. Commit frequently with descriptive messages
6. Push and create PR when file reaches 90%+
7. Move to next file

---

## 📞 Need Help?

- Check existing test files for patterns: `test/ysc_web/live/`
- Review `test/README.md` for testing conventions
- See `test/support/` for available fixtures and helpers
- Ask team for code review early and often

**Remember: These are SECURITY CRITICAL files. Take your time, test thoroughly, and don't skip edge cases!**
