# Test Coverage Improvement Plan
## Goal: Achieve 90%+ File and Overall Coverage

**Current Coverage:** 43.1%
**Target Coverage:** 90%+
**Gap to Close:** ~47%
**Total Test Files:** 221
**Total Tests:** ~2,695

---

## Executive Summary

This plan outlines a phased approach to increase test coverage from 43.1% to 90%+ across the YSC codebase. The strategy focuses on **security vulnerabilities first**, followed by critical infrastructure, financial systems, and user-facing features.

### 🚨 Critical Security Finding

**IMMEDIATE ACTION REQUIRED:** The codebase has **38 files with 0% test coverage**, including:
- **`lib/ysc_web/authorization/policy.ex`** - Authorization policies (SECURITY CRITICAL)
- **`lib/ysc_web/controllers/auth_controller.ex`** - Authentication (SECURITY CRITICAL)
- **`lib/ysc_web/controllers/stripe_payment_method_controller.ex`** - Payment methods (FINANCIAL CRITICAL)
- **`lib/ysc/quickbooks/client.ex`** - QuickBooks integration (6% coverage, FINANCIAL CRITICAL)
- **`lib/ysc/membership.ex`** - Core membership logic (BUSINESS CRITICAL)

These represent significant security and business risks that must be addressed before other coverage improvements.

### Plan Overview

**Timeline:** 13 weeks (~3.25 months)
**New Tests Required:** 1,750-2,350 tests
**Resource Requirement:** 1-2 dedicated developers

**Phase 1 (Weeks 1-4):** Security & Infrastructure - **CRITICAL PRIORITY**
- Close all security vulnerabilities
- Test authorization, authentication, payment processing
- Cover 38 zero-coverage files
- Target: 58-63% coverage

**Phases 2-5 (Weeks 5-13):** Progressive coverage improvement
- User-facing LiveViews
- Background workers
- Edge cases and polish
- Target: 90%+ coverage

---

## Phase 1: Security, Infrastructure & Zero Coverage Files (Weeks 1-4)
**Target:** 58-63% overall coverage
**Priority:** CRITICAL - Security vulnerabilities and critical infrastructure gaps

### 1.1 Security & Authorization (Week 1) ⚠️ HIGHEST PRIORITY
**⚠️ SECURITY CRITICAL:** These files control access and authentication - must be tested first!

- [ ] `lib/ysc_web/authorization/policy.ex` (0%) ⚠️
  - **Impact:** CRITICAL - Authorization policies for entire application
  - **Security Risk:** Untested authorization = potential unauthorized access
  - **Tests needed:**
    - All policy rules (admin, member, guest access)
    - Resource ownership verification
    - Role-based permissions
    - Edge cases (deleted users, expired memberships)
  - **Estimated tests:** 60-80 tests

- [ ] `lib/ysc_web/controllers/auth_controller.ex` (0%) ⚠️
  - **Impact:** CRITICAL - Authentication flow
  - **Tests needed:** Login, logout, OAuth callbacks, session management
  - **Estimated tests:** 30-40 tests

- [ ] `lib/ysc_web/user_auth.ex` (683 lines, 63.6%)
  - **Impact:** HIGH - Authentication helpers, need to reach 90%+
  - **Current gap:** 53 uncovered lines
  - **Tests needed:** Additional auth edge cases, session validation
  - **Estimated tests:** 25-30 tests

- [ ] `lib/ysc_web/plugs/native_api_key.ex` (79 lines, 21.7%)
  - **Impact:** HIGH - API authentication
  - **Tests needed:** API key validation, error handling, rate limiting
  - **Estimated tests:** 15-20 tests

### 1.2 Payment & Financial Controllers (Week 1) 💰
**CRITICAL:** Payment processing must be thoroughly tested

- [ ] `lib/ysc_web/controllers/stripe_payment_method_controller.ex` (0%)
  - **Impact:** CRITICAL - Stripe payment method management
  - **Tests needed:** Add/remove payment methods, validation, error handling
  - **Estimated tests:** 25-30 tests

- [ ] `lib/ysc/quickbooks/client.ex` (6%)
  - **Impact:** HIGH - QuickBooks integration for accounting
  - **Tests needed:** API calls, error handling, retry logic, data sync
  - **Estimated tests:** 40-50 tests

- [ ] `lib/ysc/ledgers/reconciliation_worker.ex` (0%)
  - **Impact:** HIGH - Financial reconciliation
  - **Tests needed:** Reconciliation logic, discrepancy detection, correction flows
  - **Estimated tests:** 30-40 tests

### 1.3 Core Infrastructure (Week 2)
Essential infrastructure that everything depends on:

- [ ] `lib/ysc/repo.ex` (0%)
  - **Impact:** HIGH - Database repository configuration
  - **Tests needed:** Connection handling, transaction management, query helpers
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc/mailer.ex` (0%)
  - **Impact:** HIGH - Email sending infrastructure
  - **Tests needed:** Email delivery, adapter configuration, error handling
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc/membership.ex` (0%)
  - **Impact:** CRITICAL - Core membership business logic
  - **Tests needed:** Membership validation, state transitions, eligibility checks
  - **Estimated tests:** 40-50 tests

- [ ] `lib/ysc_web/endpoint.ex` (91 lines, 0%)
  - **Impact:** MEDIUM - Phoenix endpoint configuration
  - **Tests needed:** Endpoint configuration, plug pipeline
  - **Estimated tests:** 8-10 tests

- [ ] `lib/ysc_web/telemetry.ex` (178 lines, 0%)
  - **Impact:** MEDIUM - Metrics and monitoring
  - **Tests needed:** Metric emission, event handling
  - **Estimated tests:** 15-20 tests

### 1.4 UI Controllers & Components (Week 2)
Controllers and reusable components with zero coverage:

- [ ] `lib/ysc_web/controllers/trix_uploads_controller.ex` (0%)
  - **Impact:** MEDIUM - Rich text editor uploads
  - **Tests needed:** Upload handling, validation, S3 integration
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/components/autocomplete.ex` (0%)
  - **Impact:** MEDIUM - Autocomplete component
  - **Tests needed:** Search, selection, rendering
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/components/admin_search.ex` (12.6%)
  - **Impact:** MEDIUM - Admin search component
  - **Tests needed:** Search functionality, filtering, results
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/components/events/event_card.ex` (0%)
  - **Impact:** MEDIUM - Event display component
  - **Tests needed:** Rendering different event states
  - **Estimated tests:** 10-15 tests

- [ ] `lib/ysc_web/components/news/news_card.ex` (0%)
  - **Impact:** LOW - News display component
  - **Tests needed:** Rendering variations
  - **Estimated tests:** 8-10 tests

- [ ] `lib/ysc_web/components/image_upload_component.ex` (0%)
  - **Impact:** MEDIUM - Image upload component
  - **Tests needed:** Upload flow, validation, preview
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/components/uploader/file_component.ex` (0%)
  - **Impact:** MEDIUM - File upload component
  - **Tests needed:** Multi-file upload, validation, progress
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/components/uploader/uploads.ex` (10.6%)
  - **Impact:** MEDIUM - Upload handling
  - **Tests needed:** Increase to 90%+
  - **Estimated tests:** 12-15 tests

### 1.5 Critical LiveViews (Week 3)
High-impact pages with zero coverage:

- [ ] `lib/ysc_web/live/admin/admin_events_new.ex` (1,092 lines, 0%)
  - **Impact:** CRITICAL - Event creation is core functionality
  - **Tests needed:** Event creation flow, validation, image uploads, agenda items
  - **Estimated tests:** 50-60 tests

- [ ] `lib/ysc_web/live/payment_success_live.ex` (364 lines, 0%)
  - **Impact:** HIGH - Payment confirmation UX
  - **Tests needed:** Success page rendering, order details, ticket download
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc_web/live/family_invite_acceptance.ex` (176 lines, 0%)
  - **Impact:** HIGH - Family account management
  - **Tests needed:** Invite acceptance, validation, error handling
  - **Estimated tests:** 20-25 tests

### 1.6 Financial Workers & Integrations (Week 3)
Zero-coverage workers that handle money:

- [ ] `lib/ysc_web/workers/quickbooks_sync_expense_report.ex` (163 lines, 0%)
  - **Impact:** HIGH - Financial sync for accounting
  - **Tests needed:** Sync logic, error handling, retry behavior
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc/expense_reports/quickbooks_sync.ex` (8.9%)
  - **Impact:** HIGH - Expense report sync
  - **Tests needed:** Increase to 90%+, full sync workflow
  - **Estimated tests:** 30-40 tests

- [ ] `lib/ysc/expense_reports/scheduler.ex` (0%)
  - **Impact:** MEDIUM - Expense report scheduling
  - **Tests needed:** Scheduling logic, cron jobs
  - **Estimated tests:** 15-20 tests

### 1.7 Email Templates - Critical Communications (Week 4)
Low-coverage emails for important user communications:

- [ ] `lib/ysc_web/emails/ticket_purchase_confirmation.ex` (542 lines, 14.2%)
  - **Impact:** CRITICAL - Ticket purchase confirmations
  - **Tests needed:** Email rendering, ticket details, PDF generation
  - **Estimated tests:** 30-40 tests

- [ ] `lib/ysc_web/emails/ticket_order_refund.ex` (278 lines, 19.6%)
  - **Impact:** HIGH - Refund notifications
  - **Tests needed:** Refund email rendering, partial/full refunds
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc_web/emails/membership_payment_failed.ex` (68 lines, 10%)
  - **Impact:** HIGH - Payment failure alerts
  - **Tests needed:** Payment failure email rendering, retry links
  - **Estimated tests:** 12-15 tests

- [ ] `lib/ysc_web/emails/event_notification.ex` (2.3%)
  - **Impact:** HIGH - Event notifications
  - **Tests needed:** Various event states, reminders, cancellations
  - **Estimated tests:** 30-35 tests

- [ ] `lib/ysc_web/emails/booking_refund_processing.ex` (2.5%)
  - **Impact:** HIGH - Booking refund notifications
  - **Tests needed:** Refund processing emails
  - **Estimated tests:** 25-30 tests

- [ ] `lib/ysc_web/emails/booking_cancellation_confirmation.ex` (3.3%)
  - **Impact:** HIGH - Booking cancellation confirmations
  - **Tests needed:** Cancellation emails, refund info
  - **Estimated tests:** 25-30 tests

- [ ] `lib/ysc_web/emails/booking_cancellation_notification.ex` (4.9%)
  - **Impact:** HIGH - Cancellation notifications to admins
  - **Tests needed:** Admin notification emails
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc_web/emails/outage_notification.ex` (173 lines, 26.2%)
  - **Impact:** MEDIUM - Property outage alerts
  - **Tests needed:** Outage notifications for multiple properties
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/emails/expense_report_treasurer_notification.ex` (10.9%)
  - **Impact:** MEDIUM - Treasurer notifications
  - **Tests needed:** Expense report notifications
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/emails/expense_report_confirmation.ex` (12.2%)
  - **Impact:** MEDIUM - Expense report confirmations
  - **Tests needed:** Confirmation emails
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/emails/base_layout.ex` (0%)
  - **Impact:** LOW - Email layout template
  - **Tests needed:** Layout rendering
  - **Estimated tests:** 5-8 tests

### 1.8 Image Processing & Media (Week 4)
Critical for user-uploaded content:

- [ ] `lib/ysc_web/workers/image_processor.ex` (157 lines, 5.5%)
  - **Impact:** HIGH - Image processing for events/posts
  - **Tests needed:** Image processing, thumbnails, blurhash, S3 upload
  - **Estimated tests:** 25-30 tests

### 1.9 Utility Modules (Week 4)
Small but important utilities:

- [ ] `lib/ysc_web/gettext.ex` (24 lines, 0%)
  - **Impact:** LOW - I18n infrastructure (quick win!)
  - **Tests needed:** Translation loading tests
  - **Estimated tests:** 3-5 tests

- [ ] `lib/ysc_web/save_request_uri.ex` (23 lines, 0%)
  - **Impact:** LOW - Request URI tracking (quick win!)
  - **Tests needed:** URI saving and retrieval
  - **Estimated tests:** 3-5 tests

- [ ] `lib/ysc/encrypted_binary.ex` (0%)
  - **Impact:** MEDIUM - Encryption for sensitive data
  - **Tests needed:** Encryption/decryption, key management
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc/message_passing_events.ex` (0%)
  - **Impact:** LOW - Event system
  - **Tests needed:** Event emission and handling
  - **Estimated tests:** 10-12 tests

- [ ] `lib/ysc/prom_ex.ex` (0%)
  - **Impact:** LOW - Prometheus metrics
  - **Tests needed:** Metric definitions, collection
  - **Estimated tests:** 8-10 tests

- [ ] `lib/ysc/release.ex` (0%)
  - **Impact:** LOW - Release tasks
  - **Tests needed:** Migration running, setup tasks
  - **Estimated tests:** 8-10 tests

### 1.10 Property Outages System (Week 4)
Complete subsystem with zero coverage:

- [ ] `lib/ysc/property_outages/scraper.ex` (0%)
  - **Impact:** MEDIUM - Outage scraping logic
  - **Tests needed:** Web scraping, parsing, error handling
  - **Estimated tests:** 25-30 tests

- [ ] `lib/ysc/property_outages/outage_scraper_worker.ex` (0%)
  - **Impact:** MEDIUM - Outage scraper job
  - **Tests needed:** Worker execution, scheduling
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc/property_outages/scheduler.ex` (0%)
  - **Impact:** MEDIUM - Outage check scheduling
  - **Tests needed:** Schedule management
  - **Estimated tests:** 10-15 tests

- [ ] `lib/ysc/property_outages/defs.ex` (0%)
  - **Impact:** LOW - Type definitions
  - **Tests needed:** Basic validation
  - **Estimated tests:** 5-8 tests

### 1.11 Core Business Logic Gaps (Week 4)
Review and expand existing modules:

- [ ] Review and expand `lib/ysc/payments/` coverage (currently minimal)
  - **Tests needed:** Payment processing, refunds, disputes
  - **Estimated tests:** 40-50 tests

- [ ] Review and expand `lib/ysc/events/` coverage (currently 1 test file)
  - **Tests needed:** Event CRUD, state transitions, capacity management
  - **Estimated tests:** 50-60 tests

- [ ] `lib/ysc/events/defs.ex` (0%)
  - **Impact:** MEDIUM - Event type definitions
  - **Tests needed:** Type validation, serialization
  - **Estimated tests:** 10-15 tests

- [ ] Review and expand `lib/ysc/subscriptions/` coverage
  - **Tests needed:** Subscription lifecycle, renewals, cancellations
  - **Estimated tests:** 40-50 tests

- [ ] `lib/ysc/bookings/defs.ex` (0%)
  - **Impact:** MEDIUM - Booking type definitions
  - **Tests needed:** Type validation
  - **Estimated tests:** 10-15 tests

### 1.12 Behavior Definitions (Week 4)
Interface definitions that need basic tests:

- [ ] `lib/ysc/keila/behaviour.ex` (0%)
  - **Impact:** LOW - Keila client interface
  - **Tests needed:** Behavior contract tests
  - **Estimated tests:** 5-8 tests

- [ ] `lib/ysc/quickbooks/client_behaviour.ex` (0%)
  - **Impact:** LOW - QuickBooks client interface
  - **Tests needed:** Behavior contract tests
  - **Estimated tests:** 5-8 tests

- [ ] `lib/ysc/stripe_behaviour.ex` (0%)
  - **Impact:** LOW - Stripe client interface
  - **Tests needed:** Behavior contract tests
  - **Estimated tests:** 5-8 tests

- [ ] `lib/ysc/stripe_client.ex` (0%)
  - **Impact:** MEDIUM - Stripe client implementation
  - **Tests needed:** API calls, error handling
  - **Estimated tests:** 30-40 tests

- [ ] `lib/ysc.ex` (0%)
  - **Impact:** LOW - Main application module
  - **Tests needed:** Application startup
  - **Estimated tests:** 5-8 tests

**Phase 1 Expected Outcome:** 58-63% coverage, all security holes closed, critical infrastructure tested

### 1.2 Critical Email Templates (Week 2)
Email delivery is critical for user communication:

- [ ] `lib/ysc_web/emails/ticket_purchase_confirmation.ex` (542 lines, 14.2%)
  - **Tests needed:** Email rendering, ticket details, PDF generation
  - **Estimated tests:** 25-30 tests

- [ ] `lib/ysc_web/emails/ticket_order_refund.ex` (278 lines, 19.6%)
  - **Tests needed:** Refund email rendering, partial/full refunds
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/emails/membership_payment_failed.ex` (68 lines, 10%)
  - **Tests needed:** Payment failure email rendering, retry links
  - **Estimated tests:** 10-15 tests

- [ ] `lib/ysc_web/emails/outage_notification.ex` (173 lines, 26.2%)
  - **Tests needed:** Outage notification rendering, multiple properties
  - **Estimated tests:** 15-20 tests

### 1.3 Core Business Logic Gaps (Week 3)
Focus on untested or under-tested core modules:

- [ ] Review and expand `lib/ysc/payments/` coverage (currently minimal)
  - **Tests needed:** Payment processing, refunds, disputes
  - **Estimated tests:** 30-40 tests

- [ ] Review and expand `lib/ysc/events/` coverage (currently 1 test file)
  - **Tests needed:** Event CRUD, state transitions, capacity management
  - **Estimated tests:** 40-50 tests

- [ ] Review and expand `lib/ysc/subscriptions/` coverage
  - **Tests needed:** Subscription lifecycle, renewals, cancellations
  - **Estimated tests:** 30-40 tests

**Phase 1 Expected Outcome:** 55-60% coverage, all critical paths tested

---

## Phase 2: LiveView UI Layer - High Traffic Pages (Weeks 5-7)
**Target:** 73-78% overall coverage
**Priority:** MEDIUM-HIGH - User-facing features

### 2.1 Booking System LiveViews (Weeks 4-5)
Booking system is complex and high-value:

- [ ] `lib/ysc_web/live/booking_checkout_live.ex` (3,000 lines, 13.2%)
  - **Current gap:** 784 uncovered lines
  - **Tests needed:**
    - Checkout flow (guest count, dates, pricing)
    - Payment processing integration
    - Validation (availability, conflicts, restrictions)
    - Error handling (payment failures, inventory conflicts)
  - **Estimated tests:** 60-80 tests

- [ ] `lib/ysc_web/live/booking_receipt_live.ex` (1,795 lines, 46.5%)
  - **Current gap:** 245 uncovered lines
  - **Tests needed:** Receipt rendering, invoice downloads, booking details
  - **Estimated tests:** 30-40 tests

### 2.2 Admin Panel LiveViews (Week 5)
Admin tools need comprehensive testing:

- [ ] `lib/ysc_web/live/admin/admin_bookings_live.ex` (6,956 lines, 15.1%)
  - **Current gap:** 1,768 uncovered lines
  - **Tests needed:**
    - Booking list/filter/search
    - Manual booking creation
    - Booking modifications
    - Cancellations and refunds
    - Export functionality
  - **Estimated tests:** 80-100 tests

- [ ] `lib/ysc_web/live/admin/admin_media_live.ex` (1,184 lines, 12.8%)
  - **Current gap:** 306 uncovered lines
  - **Tests needed:** Media library management, uploads, deletions
  - **Estimated tests:** 40-50 tests

- [ ] `lib/ysc_web/live/admin/admin_money_live.ex` (3,545 lines, 16.7%)
  - **Current gap:** 667 uncovered lines
  - **Tests needed:**
    - Financial dashboard
    - Transaction listings
    - Refund processing
    - Export reports
  - **Estimated tests:** 60-80 tests

### 2.3 Event Management LiveViews (Week 6)
- [ ] `lib/ysc_web/live/event_details_live.ex` (7,021 lines, 33.9%)
  - **Current gap:** 1,418 uncovered lines
  - **Tests needed:**
    - Ticket purchasing flow
    - Waitlist functionality
    - Guest ticket management
    - Member vs non-member pricing
    - Sold out handling
  - **Estimated tests:** 80-100 tests

**Phase 2 Expected Outcome:** 70-75% coverage, all major user flows tested

---

## Phase 3: User Settings & Account Management (Weeks 8-9)
**Target:** 82-86% overall coverage
**Priority:** MEDIUM - User experience and data integrity

### 3.1 User Settings (Week 7)
- [ ] `lib/ysc_web/live/user_settings_live.ex` (4,884 lines, 25.1%)
  - **Current gap:** 946 uncovered lines
  - **Tests needed:**
    - Profile updates
    - Password changes
    - Email verification
    - Phone number management
    - Privacy settings
    - Family account management
  - **Estimated tests:** 80-100 tests

- [ ] `lib/ysc_web/live/account_setup_live.ex` (1,194 lines, 23.8%)
  - **Current gap:** 252 uncovered lines
  - **Tests needed:** Onboarding flow, membership selection, payment setup
  - **Estimated tests:** 40-50 tests

### 3.2 Home & Landing Pages (Week 7)
- [ ] `lib/ysc_web/live/home_live.ex` (2,520 lines, 48.2%)
  - **Current gap:** 318 uncovered lines
  - **Tests needed:** Homepage rendering, dynamic content, call-to-actions
  - **Estimated tests:** 40-50 tests

### 3.3 Family & Invite Management (Week 8)
- [ ] `lib/ysc_web/live/family_management_live.ex` (560 lines, 45.1%)
  - **Current gap:** 68 uncovered lines
  - **Tests needed:** Family member management, invitations, permissions
  - **Estimated tests:** 25-30 tests

**Phase 3 Expected Outcome:** 80-85% coverage, comprehensive user account testing

---

## Phase 4: Background Workers & Async Jobs (Weeks 10-11)
**Target:** 88-90% overall coverage
**Priority:** MEDIUM - Data integrity and automation

### 4.1 Notification Workers (Week 9)
- [ ] `lib/ysc_web/workers/email_notifier.ex` (355 lines, 57.2%)
  - **Current gap:** 53 uncovered lines
  - **Tests needed:** Email queue processing, retry logic, failure handling
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc_web/workers/sms_notifier.ex` (558 lines, 63%)
  - **Current gap:** 37 uncovered lines
  - **Tests needed:** SMS delivery, rate limiting, error handling
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc_web/workers/event_notification_worker.ex` (272 lines, 28.7%)
  - **Current gap:** 52 uncovered lines
  - **Tests needed:** Event reminders, cancellation notifications
  - **Estimated tests:** 25-30 tests

### 4.2 Financial Sync Workers (Week 9)
- [ ] `lib/ysc_web/workers/quickbooks_sync_payment.ex` (123 lines, 68.4%)
  - Increase to 90%+ coverage
  - **Estimated tests:** 10-15 additional tests

- [ ] `lib/ysc_web/workers/quickbooks_sync_payout.ex` (126 lines, 30%)
  - **Current gap:** 14 uncovered lines
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/workers/quickbooks_sync_refund.ex` (123 lines, 47.3%)
  - **Current gap:** 10 uncovered lines
  - **Estimated tests:** 15-20 tests

### 4.3 Booking & User Workers (Week 10)
- [ ] `lib/ysc_web/workers/booking_checkin_reminder.ex` (319 lines, 49.4%)
  - **Current gap:** 46 uncovered lines
  - **Tests needed:** Check-in reminders, timing logic, guest communications
  - **Estimated tests:** 20-25 tests

- [ ] `lib/ysc_web/workers/booking_checkout_reminder.ex` (197 lines, 58.3%)
  - **Current gap:** 20 uncovered lines
  - **Tests needed:** Checkout reminders, property status updates
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/workers/user_exporter.ex` (377 lines, 51.6%)
  - **Current gap:** 58 uncovered lines
  - **Tests needed:** Data export, CSV generation, S3 upload
  - **Estimated tests:** 25-30 tests

**Phase 4 Expected Outcome:** 87-89% coverage, robust background job testing

---

## Phase 5: Edge Cases & Polish (Weeks 12-13)
**Target:** 90%+ overall coverage
**Priority:** LOW-MEDIUM - Final push to goal

### 5.1 Remaining LiveViews (Week 11)
Fill in remaining gaps in LiveViews:

- [ ] `lib/ysc_web/live/expense_report_live.ex` (3,559 lines, 21.8%)
  - **Current gap:** 673 uncovered lines
  - **Tests needed:** Expense report submission, approval workflow, reimbursement
  - **Estimated tests:** 60-80 tests

- [ ] `lib/ysc_web/live/tahoe_booking_live.ex` (7,409 lines, 50.2%)
  - **Current gap:** 848 uncovered lines
  - **Tests needed:** Additional Tahoe-specific booking scenarios
  - **Estimated tests:** 40-60 tests

- [ ] `lib/ysc_web/live/user_booking_detail_live.ex` (681 lines, 34.8%)
  - **Current gap:** 114 uncovered lines
  - **Tests needed:** Booking detail views, modifications, cancellations
  - **Estimated tests:** 25-30 tests

### 5.2 Remaining Workers & Utilities (Week 11)
- [ ] `lib/ysc_web/workers/file_export_clean_up.ex` (64 lines, 45%)
  - **Tests needed:** File cleanup, S3 deletion
  - **Estimated tests:** 10-15 tests

- [ ] `lib/ysc_web/workers/image_reprocessor.ex` (69 lines, 38%)
  - **Tests needed:** Image reprocessing, format conversions
  - **Estimated tests:** 15-20 tests

- [ ] `lib/ysc_web/workers/membership_payment_reminder.ex` (205 lines, 66.6%)
  - Increase to 90%+ coverage
  - **Estimated tests:** 10-15 additional tests

### 5.3 Infrastructure & Plugs (Week 12)
Finish off infrastructure files:

- [ ] `lib/ysc_web/plugs/native_api_key.ex` (79 lines, 21.7%)
  - **Tests needed:** API key validation, error handling
  - **Estimated tests:** 10-15 tests

- [ ] `lib/ysc_web/user_auth.ex` (683 lines, 63.6%)
  - **Current gap:** 53 uncovered lines
  - **Tests needed:** Additional auth edge cases
  - **Estimated tests:** 20-25 tests

- [ ] Complete remaining email templates to 90%+
  - Various email templates with 60-80% coverage
  - **Estimated tests:** 30-40 tests total

### 5.4 Core Module Coverage Review (Week 12)
Review all `lib/ysc/` modules and ensure 90%+ coverage:

- [ ] Audit all core modules for edge cases
- [ ] Add integration tests for cross-module workflows
- [ ] Test error scenarios and boundary conditions
- [ ] **Estimated tests:** 50-75 additional tests

**Phase 5 Expected Outcome:** 90%+ coverage achieved

---

## Testing Strategy & Best Practices

### Test Types by Layer

#### LiveView Tests
```elixir
# Use Phoenix.LiveViewTest
use YscWeb.ConnCase, async: true
import Phoenix.LiveViewTest

# Test structure:
- Mount and initial render
- User interactions (form submissions, button clicks)
- Real-time updates
- Error handling and validation
- Authorization (authenticated vs unauthenticated)
- Edge cases (sold out, capacity limits, etc.)
```

#### Worker/Job Tests
```elixir
# Use Oban.Testing
use Ysc.DataCase, async: true
use Oban.Testing, repo: Ysc.Repo

# Test structure:
- Successful execution
- Error handling and retries
- Idempotency
- External service mocking (Stripe, QuickBooks, etc.)
- Edge cases (missing data, invalid states)
```

#### Email Template Tests
```elixir
# Use Swoosh.TestAssertions
import Swoosh.TestAssertions

# Test structure:
- Correct recipient
- Subject line
- HTML body content
- Text body content
- Attachments (if applicable)
- Variable interpolation
```

#### Core Module Tests
```elixir
# Use DataCase
use Ysc.DataCase, async: true

# Test structure:
- CRUD operations
- Business logic validation
- State transitions
- Error handling
- Database constraints
- Association loading
```

### Coverage Monitoring

#### Daily
- Run `make test` with coverage locally
- Review coverage report for changed files
- Ensure new code has 90%+ coverage

#### Weekly
- Generate full coverage report
- Review files that dropped below 90%
- Create tickets for coverage gaps

#### Monthly
- Review overall coverage trend
- Update this plan based on progress
- Celebrate milestones (60%, 70%, 80%, 90%)

### Continuous Integration

Update `.github/workflows/` to:
1. Run tests with coverage on every PR
2. Fail PR if overall coverage drops below threshold
3. Comment on PR with coverage diff
4. Generate and upload coverage artifacts

Example GitHub Actions step:
```yaml
- name: Run tests with coverage
  run: mix coveralls.github
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    MIX_ENV: test

- name: Coverage threshold check
  run: |
    COVERAGE=$(mix coveralls.json | grep '"total"' | grep -o '[0-9.]*')
    if (( $(echo "$COVERAGE < 90" | bc -l) )); then
      echo "Coverage $COVERAGE% is below 90% threshold"
      exit 1
    fi
```

---

## Success Metrics

### Quantitative Goals
- [ ] Overall coverage: 90%+
- [ ] File coverage: 90%+ for all critical files
- [ ] No files with 0% coverage
- [ ] All LiveViews: 85%+ coverage
- [ ] All workers: 85%+ coverage
- [ ] All core modules: 90%+ coverage
- [ ] All email templates: 85%+ coverage

### Qualitative Goals
- [ ] All critical user paths tested (booking, events, payments)
- [ ] All financial operations tested (payments, refunds, QuickBooks sync)
- [ ] All background jobs tested (emails, SMS, notifications)
- [ ] All error scenarios tested
- [ ] All authorization scenarios tested
- [ ] Comprehensive integration tests for complex workflows

### Test Suite Health
- [ ] Test suite runs in < 5 minutes
- [ ] All tests pass consistently (no flaky tests)
- [ ] Tests are maintainable and well-documented
- [ ] Test data factories are comprehensive
- [ ] Mocks/stubs are up to date

---

## Resource Allocation

### Team Effort Estimate
- **Total estimated new tests:** 1,900-2,400 tests
- **Current tests:** ~2,695
- **Final test count:** ~4,600-5,100 tests
- **Time estimate:** 13 weeks (~3.25 months) with 1-2 developers dedicated

### Phase Breakdown
| Phase | Weeks | Tests Added | Coverage Gain | Priority |
|-------|-------|-------------|---------------|----------|
| 1 (Security & Infrastructure) | 1-4 | 600-750 | +15-20% | CRITICAL |
| 2 (High-Traffic LiveViews) | 5-7 | 400-550 | +15-18% | MEDIUM-HIGH |
| 3 (User Settings & Accounts) | 8-9 | 300-400 | +9-11% | MEDIUM |
| 4 (Background Workers) | 10-11 | 250-350 | +5-7% | MEDIUM |
| 5 (Polish to 90%) | 12-13 | 200-300 | +3-5% | LOW-MEDIUM |
| **Total** | **13** | **1,750-2,350** | **~47-61%** | |

### Parallel Work Opportunities
- Different team members can work on different phases
- Phases 2-4 can have some overlap (e.g., start Phase 3 while finishing Phase 2)
- Workers (Phase 4) can be parallelized with LiveViews (Phases 2-3)

---

## Risk Mitigation

### Potential Blockers
1. **Flaky tests**: Use proper async handling and database sandboxing
2. **Slow test suite**: Optimize fixtures, use `async: true` where possible
3. **Complex mocking**: Invest in robust mock infrastructure early
4. **External dependencies**: Use comprehensive stubs for Stripe, QuickBooks, S3
5. **Time constraints**: Prioritize critical paths first (Phase 1)

### Mitigation Strategies
- Set up test parallelization early
- Create reusable test helpers and factories
- Document testing patterns for consistency
- Regular code reviews to maintain test quality
- Celebrate incremental progress to maintain momentum

---

## Getting Started

### Week 1 - Day 1 Actions
1. Review this plan with team
2. Set up coverage tracking in CI/CD
3. Create tracking board/tickets for each phase
4. Assign ownership for Phase 1 tasks
5. Set up coverage baseline and reporting
6. **START WITH SECURITY FILES** from Phase 1.1

### Week 1 - CRITICAL PRIORITY ⚠️
**SECURITY FIRST:** Do NOT skip ahead - these are security vulnerabilities!

**Day 1-2: Authorization Testing (HIGHEST PRIORITY)**
1. `lib/ysc_web/authorization/policy.ex` ⚠️ CRITICAL
   - Untested authorization = potential data breaches
   - Test ALL policy rules before proceeding

**Day 3-4: Authentication & Payment Security**
2. `lib/ysc_web/controllers/auth_controller.ex` ⚠️
3. `lib/ysc_web/controllers/stripe_payment_method_controller.ex` ⚠️
4. `lib/ysc_web/user_auth.ex` (close remaining gaps)

**Day 5: Quick Wins for Momentum**
While waiting for code review on security tests:
1. `lib/ysc_web/gettext.ex` (24 lines) - 30 minutes
2. `lib/ysc_web/save_request_uri.ex` (23 lines) - 30 minutes
3. `lib/ysc_web/emails/base_layout.ex` - 1 hour

### Critical Success Factor
**DO NOT PROCEED** to Phase 2 until ALL Phase 1.1 and 1.2 files (security and payments) are tested. These are security vulnerabilities that must be addressed immediately.

---

## Maintenance Plan (Post-90%)

### Preventing Coverage Regression
1. **Pre-commit hooks**: Run coverage check locally
2. **PR requirements**: All new code must have 90%+ coverage
3. **Weekly reviews**: Monitor coverage trends
4. **Quarterly audits**: Deep dive into complex areas
5. **Coverage badges**: Display coverage on README for visibility

### Continuous Improvement
- Refactor tests for maintainability
- Update test data factories as schemas evolve
- Keep mocks/stubs in sync with external APIs
- Document testing patterns and conventions
- Share knowledge through team testing workshops

---

## Conclusion

Achieving 90%+ test coverage is ambitious but achievable with a structured, phased approach. By prioritizing **security and critical infrastructure first**, then working systematically through each layer, we can build a robust test suite that provides confidence in deployments and enables rapid feature development.

**⚠️ CRITICAL FINDING:** The most concerning discovery is that authorization/policy.ex has 0% test coverage. This represents a significant security risk that must be addressed immediately before any other work.

**Key Success Factors:**
1. **Security-first mindset** - Never skip security testing
2. Team commitment and dedicated resources
3. Systematic, phased approach
4. Regular progress monitoring
5. Celebration of milestones
6. Continuous improvement mindset

**Timeline:** 13 weeks (~3.25 months) to 90%+ coverage
**Security Milestone:** Week 1 completion closes critical security gaps
**Outcome:** Robust, secure, maintainable test suite covering all critical paths
**Long-term benefit:** Faster development, fewer bugs, confident deployments, reduced security risk
