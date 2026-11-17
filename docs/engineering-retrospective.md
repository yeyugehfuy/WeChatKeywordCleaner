# Engineering retrospective

## Scope

The repository history through 2026-11-16 contains 34 commits on `main` and no pull requests. The history repeatedly changed search discovery, result parsing, diagnostics, deletion safety, selection UX, and the entry point. The pattern matters more than the individual commits: the same uncertainty was being rediscovered after each build and phone test.

## Recurring causes and controls

| Pattern | Root cause | Prevention added |
|---|---|---|
| Repeated zero-result builds despite native WeChat search finding messages | Diagnostics reported missing managers or a generic zero count, but did not preserve the exact candidate path used | Successful and failed searches now report the async or direct-index path, candidate counts, and index-query diagnostics |
| A passing Actions run was treated as feature validation | CI compiled and packaged code but had no device evidence contract | `AGENTS.md` requires build/runtime claims to be separated and records a small device verification matrix |
| Search API guesses were added repeatedly | Version-coupled selectors and result object shapes were changed without exact-build evidence | Rules require selector guards and retaining fallbacks until target-device evidence identifies a dead path |
| Delete completion could be reported as success without read-back support | The implementation explicitly returned success if `GetMsg:LocalIDArray:` was absent, despite deletion being unverified | Missing read-back now fails closed; UI reports that deletion was not confirmed |
| Floating-button placement and drag behavior were repeatedly revised before being replaced | Entry-point behavior was not treated as a stable product decision | Keep the current Settings entry unless the user explicitly requests a new placement |
| Small follow-up edits repeatedly triggered full packaging workflows | No source-level safety gate existed before expensive packaging | A focused static contract check now runs before Theos compilation |

## Historical design intent

- FTSFacade, regular-message FTS, intelligent-message FTS, and asynchronous result parsing are compatibility routes. Keep them until device diagnostics show which route is actually usable on the target.
- Exact literal message-content verification and fresh local-ID lookup are deliberate deletion safeguards.
- Per-row selection, select-all for the current result list, scope filtering, confirmation, and grouped delete calls are user-facing behavior; do not simplify them away as cleanup.
- The Settings navigation entry is the current stable launch path after floating-entry iterations.

## Safe cleanup completed

- Removed `__msgWrap` from result dictionaries. It was written but never consumed; delete re-fetches the current message by talker and local ID, so retaining wrapper objects only extended their lifetime.
- Removed the nonexistent `master` push trigger; the repository has only `main`.
- Updated package version/description so the package metadata no longer claims the 8.0.68 bridge headers are unfinished.

## Remaining verification limit

Static checks cannot prove that private WeChat selectors resolve or that the phone's database returns the same search candidates. After each release, test on the target iPhone with WeChat 8.0.68: compare a known native-search hit, cleaner candidate count and route diagnostic, delete a deliberately selected message after backup, then confirm it is absent on a fresh search. Do not call an Actions build a device validation.
