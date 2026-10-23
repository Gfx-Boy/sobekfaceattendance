# Sobek / Inukta recovery and Review 3 reapplication

Local implementation completed and deployed to AWS on 2026-10-20. A fresh Android APK was built and uploaded for testing. No device installation was performed.

## Recovery

- Web baseline: `3d57cd2` (2026-10-06), before `d0d59ee` (2026-10-18).
- Mobile baseline: `99c3de9` (2026-10-06), before `c89f6bc` (2026-10-18).
- Both October 18 commits remain available in Git history.
- Additional source archives: `/private/tmp/sobek-web-before-recovery-d0d59ee.tar.gz` and `/private/tmp/sobek-mobile-before-recovery-c89f6bc.tar.gz`. These do not contain ignored credentials, uploaded files, or database backups.
- The two Review 3 PDFs are identical. The two Addons Free RAR archives are also identical. The supplied archive contains AIBusinessAdvisor, NoticeBoard, SmartDashboardAnalytics, SmartReports, and SuggestionBox.

## Review 3 implementation

| Item | Local implementation |
| --- | --- |
| 1 | Larger header branding and a compact Inukta SVG favicon with no surrounding whitespace. |
| 2 | Inukta loading text and initial browser title; legacy Sobek browser-title fallback removed. |
| 3 | Role filter available in login history without requiring role-management permission; filter values reflect actual user types. |
| 4 | All five supplied add-ons included and compiled. Installation runs migrations and permission seeders, activates them for existing/new companies, clears module/route caches, and skips demo data. Optional LandingPage marketplace dependency is guarded. |
| 5 | Web company images use the correct media URL in mobile responses; legacy private profile images use signed URLs. |
| 6 | Persisted, rotating refresh tokens; cached mobile identity survives transient network errors; revoked sessions clear identity. Workspace login no longer revokes attendance tokens. |
| 7 | Mobile branch edits write the same branches table used by web; synthetic company branches also update the company address. |
| 8 | Company edit includes image/location fields; company forms omit departments. |
| 9 | Web branch forms persist addresses. Company owners can manage location from their profile. |
| 10 | Branch-admin defaults are HR/Admin; existing salary is serialized and retained. |
| 11 | Company image and coordinates are mandatory in company create/edit requests; edit fields are prefilled from the shared employee profile. Mobile image uploads also update the shared web user avatar. |
| 12 | Superadmin accounts excluded from mobile and HRM employee directories. |
| 13 | Position inputs removed from mobile add/edit forms; existing stored positions retained. |
| 14 | Mobile-created employee ownership is attached to the active company; an HRM employee record is created immediately. |
| 15 | Shared Staff/HR/Warehouse/Sales/Accountant mapping, canonical department options, web role editing, mobile department defaults, and an idempotent existing-profile repair command. |
| 16 | Accounting customers selectable in Project Payments using a distinct accounting_customer_id; existing user-linked payments remain supported. |
| 17 | Attendance can be changed to absent without clock times, hours/overtime reset appropriately, edit/delete controls retained, and unassigned shifts no longer default to an arbitrary shift ID. |
| 18 | Bugs page receives project/stage/member data and safely handles missing optional values. |
| 19 | Pay Now opens the vendor payment form with vendor preselected. |
| 20 | Promotion department/designation lookups tolerate missing IDs and arrays. |
| 21 | Transfer department/designation lookups tolerate missing IDs and arrays. |
| 22 | Default support categories are initialized when no categories exist. |
| 23 | View Invoices opens a dedicated vendor-invoices URL/view using the existing authorized invoice table. |

## Shared backend and routes

Both mobile base URLs resolve to `https://app.inukta.com/api`; the workspace URL references the attendance base URL directly. Laravel's configured database is used for both web and API writes. Users, employees, departments, branches, and attendance use the same records rather than periodic copying into a second database.

The obsolete scheduled S3 import/export and web-user push are disabled. S3 can still hold images; it is not the authoritative employee database. The legacy Node backend remains in the repository for recovery/history and is not the configured mobile endpoint.

Web page routes and mobile JSON routes have different response formats. They use one backend and shared database records. Existing package API controllers serve CRM and shifts; duplicate adapters from the previous change batch were removed because they overrode those working routes.

Ancillary mobile workflows retain their existing mobile_* tables inside the same Laravel database; this work does not merge those separate workflow schemas into their web module equivalents.

## Validation

- 51 affected backend tests passed, 193 assertions, against the dedicated `sobek_saas_test` schema.
- Three Flutter session regression tests passed.
- TypeScript checking and Vite production build passed; all five add-on page groups appear in the manifest.
- Flutter analyzer: zero errors; 51 existing warnings/informational findings remain across the project.
- 404 PHP files passed syntax checking. Route enumeration, shell syntax, and whitespace checks passed.
- Coverage includes token rotation/revocation, workspace/attendance coexistence, shared roles/ownership, branch addresses, image uploads, company validation, attendance correction/deletion, add-on activation, and repeatable profile repair preserving salary and face data.
- Full browser/device acceptance of every PDF scenario remains to be performed. Live deployment checks are recorded below; full interactive browser/device acceptance remains outstanding.

## Deployment preparation

`Sobek_Saas_Project/deploy.sh` builds assets and backs up the remote database before syncing. Its migration stage now runs `addons:install-free` and `review3:repair-profiles` before rebuilding caches. Those commands were validated against test data before being run in production. The production deployment and APK artifact are recorded below.

## AWS deployment and APK (2026-10-20)

- Deployed to the EC2 server serving https://app.inukta.com.
- Verified pre-deployment database backup: `/home/ubuntu/db-backups/sobek-20261020-140800.sql.gz`.
- Verified code backup: `/home/ubuntu/app-backups/sobek-20261020-140800.tar.gz`.
- Ran both new migrations, installed/activated all five add-ons, repaired existing profiles, rebuilt Laravel caches, and reloaded PHP-FPM.
- Live database check confirmed MySQL connectivity and a single database for users/employees/branches/attendance. Both company accounts have all five free add-ons (10 assignments).
- The initial deployment process was stopped during a slow recursive ownership change. Deployment then completed from that step with ownership changes limited to Laravel runtime directories.
- APK: Inukta 1.1.3, version code 6; Android package `com.attendance.face_attendance`; minimum Android 7.0.
- Artifact: `output/apk/Inukta-2026-10-20-v1.1.3-build6.apk` (98,508,172 bytes).
- URL: https://app.inukta.com/downloads/Inukta-2026-10-20-v1.1.3-build6.apk
- SHA-256: `b74463f5790d5f4bf07be2d798a90910575706bb9b6c2760bfbcd145b8353b3e`. The local and server copies match.
- APK signature verified with the existing project signing configuration (Android debug certificate); this is a direct-install test build, not a Play Store upload.

## User Management / HRM edit correction (2026-10-21)

The screenshot report exposed a missed integration path: standard user roles could retain stale departments, and the HRM form assumed branch IDs and optional HR fields were populated. Both screens already linked to the same database records, but their edit behavior was inconsistent.

- HRM Edit now loads and updates the linked account's name, email, phone, and permitted role together with HR fields in a transaction.
- Standard role/department changes are mapped consistently from either Users or HRM. Stale submitted departments no longer override a changed role.
- Sparse profiles normalize nullable fields; company-wide departments/designations remain selectable without null-ID crashes, including list filters.
- Incomplete HR details can be saved without requiring unrelated banking information.
- HRM creation enriches an existing linked employee instead of creating another row, retaining its employee ID and face reference.
- Shared addresses are maintained across account/employee updates. Missing branch assignments use the owning company's branch.
- Cross-company changes and unpermitted role changes are rejected; failed account/profile updates roll back together.
- Validation: 41 backend tests (194 assertions), three frontend regression tests, and the production frontend build passed.
- AWS deployment completed with backups `sobek-20261021-021221.sql.gz` and `sobek-20261021-021221.tar.gz` in the existing server backup directories.
- Live checks confirmed one linked profile each for ABC_company, Karim Wael, and Mohamed Wael. All three authenticated HRM Edit requests returned HTTP 200, the expected component, and the correct linked user ID. Mohamed's role/type/department are warehouse/warehouse/Ware-House; Karim's are hr/general/HR. Both employee branches are ABC_company.
- Interactive browser rendering was not verified in this session; backend response and frontend regression checks are recorded above.
