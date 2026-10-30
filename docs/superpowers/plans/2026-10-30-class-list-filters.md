# Catalog ordering and class list filters

**Goal:** Apply length-first name ordering to catalogs and classes, and combine class grade, subject, status and current-staff filters with existing search/year filtering.

**Architecture:** Extend the existing transactional RPC read boundary; authorize the readable class set before deriving options, filtering, counting and pagination. No new dependencies, tables or permissions. Work sequentially in the current checkout; no commits or deployment requested.

**Requirements:** CAT-01, SCHED-03/05, CLASS-01/03 and UX-01 plus the user's explicit ordering/filter request on 30/10/2026. Length means character count of the display name; equal lengths use the existing normalized name key in deterministic lexical order, then display name and ID. Current staff means assignments effective now, including teacher and assistant. Status supports administrative open/closed and the existing upcoming/running/ended periods.

**UI:** Adapt the inspected live Metis Users search/select toolbar and existing MLedu Bootstrap controls. Wrap into a responsive grid; preserve VI/EN and themes. Browser screenshot API currently times out; inspect existing local desktop/mobile reference captures and local MIT source, then capture actual MLedu with Playwright.

- [x] Add regression tests for contract validation, DB sorting/filter scope/pagination, HTTP forwarding and browser interactions; observe failures.
- [x] Add forward migration for catalog order and extended list RPC; update contracts, API and generated types.
- [x] Extend the existing class toolbar and translations; reset page on filters and workspace changes.
- [x] Run DB, unit, integration and browser checks plus lint/typecheck/build/artifact checks; inspect screenshots and diff.

Review focus: options independent of active filters/pages, archived references retained, revoked assignment/session cannot widen access, duplicate names have deterministic pagination, date status uses Asia/Ho_Chi_Minh. Live screenshot capture remains an explicit limitation if unavailable.

Verification and review: [local evidence](../../developer/decisions/class-list-filters.md). Review corrected fixture dates to use Vietnam business dates. DB/API test prefixes are isolated, and DB suites run sequentially with other writes to the shared test stack.
