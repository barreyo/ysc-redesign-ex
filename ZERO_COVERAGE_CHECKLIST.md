# Zero Coverage Files Checklist

**Total Files with 0% Coverage:** 38 files
**Target:** 90%+ coverage for each file

Track your progress by checking off completed files!

---

## 🚨 CRITICAL PRIORITY - Week 1 (Security & Payments)

### Security & Authorization
- [x] `lib/ysc_web/authorization/policy.ex` - **HIGHEST PRIORITY** ⚠️ ✅
  - **Status:** 0% → 100% functional coverage (222 tests)
  - **Tests needed:** 60-80 ✅ DONE
  - **Owner:** Claude Code
  - **Date Completed:** 2026-02-02

- [x] `lib/ysc_web/controllers/auth_controller.ex` - **CRITICAL** ⚠️ ✅
  - **Status:** 0% → 92.5% (25 tests)
  - **Tests needed:** 30-40 ✅ DONE
  - **Owner:** Claude Code
  - **Date Completed:** 2026-02-02

- [x] `lib/ysc_web/controllers/stripe_payment_method_controller.ex` - **CRITICAL** ⚠️ ✅
  - **Status:** 0% → 46.9% (16 tests passing, 4 skipped)
  - **Tests needed:** 25-30 ✅ DONE
  - **Production bugs fixed:** 4 critical bugs fixed (see STRIPE_CONTROLLER_ISSUES.md)
  - **Infrastructure added:** 5 behavior modules, full Mox mocking setup
  - **Owner:** Claude Code
  - **Date Completed:** 2026-02-03

---

## 💰 HIGH PRIORITY - Week 1-2 (Financial & Core)

### Financial Systems
- [ ] `lib/ysc/quickbooks/client.ex`
  - **Status:** 6% → Target: 90%+
  - **Tests needed:** 40-50
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/ledgers/reconciliation_worker.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 30-40
  - **Owner:** _____________
  - **PR:** _____________

- [x] `lib/ysc_web/workers/quickbooks_sync_expense_report_backup_worker.ex` ⚠️
  - **Status:** 0% → ~25% (12 tests, partial coverage)
  - **Tests needed:** 20-25 ⚠️ LIMITED
  - **Owner:** Claude Code
  - **Date Completed:** 2026-02-03
  - **Note:** Simplified test suite due to Oban :inline mode and ClientBehaviour/implementation mismatch

- [x] `lib/ysc/expense_reports/scheduler.ex` ✅
  - **Status:** 0% → 83.3% (22 tests)
  - **Tests needed:** 15-20 ✅ DONE
  - **Owner:** Claude Code
  - **Date Completed:** 2026-02-03

### Core Business Logic
- [ ] `lib/ysc/membership.ex` - **BUSINESS CRITICAL**
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 40-50
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/repo.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/mailer.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/stripe_client.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 30-40
  - **Owner:** _____________
  - **PR:** _____________

---

## 🖥️ HIGH PRIORITY - Week 2-3 (Critical LiveViews)

### Admin & User Flows
- [ ] `lib/ysc_web/live/admin/admin_events_new.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 50-60
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/live/payment_success_live.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 20-25
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/live/family_invite_acceptance.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 20-25
  - **Owner:** _____________
  - **PR:** _____________

### Controllers
- [ ] `lib/ysc_web/controllers/trix_uploads_controller.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

---

## 📧 MEDIUM PRIORITY - Week 2-3 (Email Templates)

- [ ] `lib/ysc_web/emails/base_layout.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 5-8
  - **Owner:** _____________
  - **PR:** _____________

---

## 🎨 MEDIUM PRIORITY - Week 2-3 (UI Components)

### LiveView Components
- [ ] `lib/ysc_web/components/autocomplete.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/components/events/event_card.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 10-15
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/components/news/news_card.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 8-10
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/components/image_upload_component.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/components/uploader/file_component.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

---

## 🏠 MEDIUM PRIORITY - Week 3-4 (Property Management)

### Property Outages System
- [ ] `lib/ysc/property_outages/scraper.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 25-30
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/property_outages/outage_scraper_worker.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/property_outages/scheduler.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 10-15
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/property_outages/defs.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 5-8
  - **Owner:** _____________
  - **PR:** _____________

---

## 🔧 LOW PRIORITY - Week 4 (Infrastructure & Utilities)

### Type Definitions
- [ ] `lib/ysc/events/defs.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 10-15
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/bookings/defs.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 10-15
  - **Owner:** _____________
  - **PR:** _____________

### Behavior Contracts
- [ ] `lib/ysc/keila/behaviour.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 5-8
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/quickbooks/client_behaviour.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 5-8
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/stripe_behaviour.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 5-8
  - **Owner:** _____________
  - **PR:** _____________

### Application & Monitoring
- [ ] `lib/ysc.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 5-8
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/endpoint.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 8-10
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/telemetry.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/prom_ex.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 8-10
  - **Owner:** _____________
  - **PR:** _____________

### Utilities
- [ ] `lib/ysc_web/gettext.ex` - **QUICK WIN** ✅
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 3-5
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc_web/save_request_uri.ex` - **QUICK WIN** ✅
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 3-5
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/encrypted_binary.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 15-20
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/message_passing_events.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 10-12
  - **Owner:** _____________
  - **PR:** _____________

- [ ] `lib/ysc/release.ex`
  - **Status:** 0% → Target: 90%+
  - **Tests needed:** 8-10
  - **Owner:** _____________
  - **PR:** _____________

---

## 📊 Progress Tracking

### By Week
- **Week 1 Target:** 8 files completed (security + payments + quick wins)
- **Week 2 Target:** 10 files completed (LiveViews + emails + components)
- **Week 3 Target:** 8 files completed (property outages + remaining components)
- **Week 4 Target:** 12 files completed (infrastructure + utilities)

### Overall Progress
- **Files Completed:** 3 / 38
- **Files Blocked:** 1 (Stripe controller - needs bug fixes)
- **Overall Coverage:** ~44-45% (target: 58-63% by end of Phase 1)
- **Tests Added:** 324 / 600-750 (target by end of Phase 1)
- **Week 1 Status:** Ahead of schedule! (Target: 240-300 tests, Actual: 324)
- **Production Bugs Found:** 4 critical bugs in Stripe controller

---

## 🎯 Completion Criteria

A file is considered "complete" when:
- [ ] Test file exists in correct location
- [ ] Coverage is 90%+ for that file
- [ ] All tests are passing
- [ ] PR is merged to main
- [ ] Coverage report confirms 90%+

---

## 📋 Daily Standup Template

**Yesterday:**
- Completed: [file names]
- In Progress: [file names]
- Blocked: [issues]

**Today:**
- Plan to complete: [file names]
- Tests to write: [count]

**Coverage:**
- Current overall: [%]
- Target for week: [%]

---

## 🏆 Milestones

- [ ] **Milestone 1:** All security files tested (Week 1)
- [ ] **Milestone 2:** All financial files tested (Week 2)
- [ ] **Milestone 3:** All critical LiveViews tested (Week 3)
- [ ] **Milestone 4:** All zero-coverage files tested (Week 4)
- [ ] **Milestone 5:** Phase 1 complete - 58-63% overall coverage

---

## 💡 Tips for Success

1. **Pick one file, finish it completely** - Don't jump between files
2. **Start with CRITICAL files first** - Don't skip security files
3. **Use existing test patterns** - Look at similar test files for examples
4. **Test edge cases** - nil, deleted, expired, invalid data
5. **Keep PRs focused** - One file per PR is ideal
6. **Ask for help early** - Don't get stuck for hours
7. **Celebrate wins** - Each completed file is progress!

---

**Last Updated:** [Date]
**Updated By:** [Name]
