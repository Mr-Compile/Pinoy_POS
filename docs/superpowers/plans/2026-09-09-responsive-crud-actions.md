# Responsive CRUD Action Placement — Implementation Plan

> Implemented inline in session. All tasks complete.

**Goal:** Move every primary Add/Create action out of the global `AppHeader` and into a reusable responsive pattern — FAB on compact-portrait, in-content toolbar button on all other layouts.

**Architecture:** `lib/ui/widgets/responsive_create_action.dart` now provides `ResponsiveCreateAction` (FAB only on compact+portrait; `contentAction` toolbar button otherwise) and `CrudToolbar` (search + scrollable controls + pinned controls + primary action). FAB and toolbar button are mutually exclusive — one action visible at a time.

## Global Constraints (applied)

- No builds/APK; `flutter analyze` + `flutter test` only.
- Permission gating at call sites via `hasPermission` — never inside the widget.
- FAB: extended ≥360px, circular below; tooltip = label; per-label `heroTag`.
- `ResponsiveCreateAction.fabClearance` (88) added to list bottom padding on FAB layouts.
- Theme tokens only (`AppButton`, `AppSemanticColors`, `Spacing`).

## Audit Result

- `AppHeader` create actions were on: products, categories, users, staff_management, stock, report_submissions (Import), announcements — all removed.
- `ai_quota_management_page`: extended FAB rendered at ALL widths — now responsive (warning color).
- Non-CRUD screens (sales, trash, activity logs, notifications, AI config/advisor, backup, POS, sale detail) had no create-in-header violations; trash keeps its contextual selection bar.

## Tasks — all done

- [x] T1: Rewrote `responsive_create_action.dart` — `isFabLayout`, `contentAction`, `fab` (extended/circular), `contentBottomClearance`, `color`, `tooltip`; added `CrudToolbar`.
- [x] T2–T8: Updated the 7 call sites; FAB bottom clearance on every list.
- [x] T9: `ai_quota_management_page` — `ResponsiveCreateAction` (warning) for Reset All Usage.
- [x] T10: `test/responsive_create_action_test.dart` — 6 tests.
- [x] T11: `flutter analyze` clean; `flutter test` 433/433 pass; `AGENTS.md` updated.
