# SDD ledger — plan: docs/superpowers/plans/2026-10-02-task-widget.md

Worktree: .claude/worktrees/task-widget-impl, branch worktree-task-widget-impl, base 30a2b4d
Spec: docs/superpowers/specs/2026-10-02-task-widget-design.md (reachable)
Models: implementer sonnet (plan carries full code), task reviewer opus, re-review sonnet, final review opus (user rule: Fable only for controller judgment)

## Pre-flight scan (2026-10-02, before Task 1)

Cross-task interface pairs (producer → consumer):
| Pair | Produces | Consumes | Found |
|---|---|---|---|
| T1→all | Package.swift test target `.copy("Fixtures")` | T6/T8/T9/T12 fixtures via `Bundle.module` subdirectory "Fixtures" | OK (T1 creates Fixtures/.gitkeep) |
| T2→T3 | `Todo(title:createdAt:dueDate:)`, `DayKey.date(from:calendar:)` | DueBadge tests/impl | OK |
| T2→T8/T10/T11 | `ActivityRecord(ts:event:session:cwd:text:)` + `.project` | ActivityLog, SummaryPrompt, SummaryService | OK |
| T5→T13/T15/T17 | `SettingsKey.*`, `Settings.shared`, `defaultJiraBaseURL` | @AppStorage keys, FloatingPanel, JiraSection, SettingsView | OK (test pins key strings) |
| T6→T15 | `fetchMyOpenIssues(jql:) -> Page`, `Page.truncated`, `grouped -> [Group]` | AppState.refreshJira, JiraSection | OK (patched in review) |
| T7→T9/T11 | `ProcessRunner.run(executable:arguments:stdin:currentDirectory:environment:timeout:)` | GitActivity, ClaudeRunner | OK |
| T8→T11/T13/T17 | `ActivityLog.records(on:from:calendar:)`, `handleHook(input:)` | SummaryService.collect, main.swift, SettingsView count | OK |
| T9→T11/T16 | `Worklog.raw/entries(on:dir:calendar:)`, `fileURL(for:)` | SummaryService, SummaryView | OK |
| T10→T11 | `SummaryInput(... worklogSectionCount:activityDropped:projects:)` defaults, `filterActivity`, `isEmpty`, `build` | SummaryService.collect/generate + tests | OK |
| T11→T16/T18 | `SummaryService(runner:)`, `existing(for:)`, `generate(for:force:)`, `SummaryError.userMessage`, `ClaudeRunner(configuredPath:model:)` | AppState, Scheduler | OK |
| T12→T17 | `ClaudeIntegration(executablePath:)`, hook/skill status+install+remove | SettingsView | OK |
| T13→T14/15/16/17 | `AppState` base, `EnvironmentValues.fontScale`, `.openSettings`, `FloatingPanel` type | views (T15 guard uses `$0 is FloatingPanel`) | OK |
| T14 self | `SectionHeader` generic init with default `{ EmptyView() }` | T14/T15 call sites without trailing | DEFECT: generic param not inferable from default arg → compile error |
| T16→T18 | `summaryGenerating`, `summaryDay`, `summaryError`, `loadSummary`, `generateSummary` | Scheduler | OK |

Per-task self-consistency: tests vs code traced for T2–T12 during plan review (workflow wf_1b320cbb, 9 confirmed findings applied). T13–T18 are build+manual; no asserting-nothing tests, no mandated duplication.

Ruling: T14 SectionHeader — replaced default generic argument with `extension SectionHeader where Trailing == EmptyView { init(title:count:collapsed:) }` in the plan — Swift cannot infer a generic parameter from a default argument — costs nothing if wrong beyond a one-line revert.
Ruling: sandbox refuses `bash <skill script>` and awk in this worktree session — replicated task-brief as `.superpowers/sdd/2026-10-02-task-widget/brief.py`, review packages built with plain git commands — no behavioral difference — cost: none.

## Task log
Task 1: implementer aaecdc06fdf07c5f5 (sonnet), reviewer a02558468df6b0298 (sonnet, 5KB diff)
Task 1: minor (deferred): Makefile `BIN_DIR := $(shell swift build ...)` runs on every make invocation (plan-mandated)
Task 1: minor (deferred): Paths.dataDir force-indexes urls(for:)[0] (plan-mandated)
Task 1: minor (deferred): Paths.ensureDirectories untested, Paths not injectable
Task 1: note: implementer commits carry `Co-Authored-By: Claude Sonnet 5.5` (accurate — sonnet did the work); not amending
Task 1: complete (commits a089833..4dc3562, review clean)
Task 2: implementer af09f19b0d54ee17b (sonnet), reviewer aedfba0486dcb2da7 (opus)
Task 2: minor (deferred): DayKey.date accepts non-canonical strings (`2026-1-2`, `+2026-10-02`); fix = `guard string(from: d, calendar: calendar) == key` (Models.swift ~L105). Not load-bearing: app only writes dueDate via DayKey.string.
Task 2: minor (deferred): ISO8601 drops sub-second precision → Todo not == after save/load (test hides with accuracy:1)
Task 2: minor (deferred): TodoStore.load treats any read error as missing; failed backup move silently ignored → possible overwrite on next save
Task 2: minor (deferred): DayKey default Calendar.current follows region calendar (non-Gregorian risk); prefer gregorian + current TZ
Task 2: minor (deferred): tests: DayKey TZ injection untested; corrupt-file backup content/extension unchecked
Task 2: complete (commits 4dc3562..6af509a, review clean)
Task 3+4 (batched): implementer a5cf57cce0705295c (sonnet), reviewer a17c9eb8b095a995e (opus)
Task 3: minor (deferred): DueBadge.sorted compares raw strings; non-canonical/invalid dueDate sorts wrong (plan-mandated; app writer always canonical). Fix: sort on DayKey.date, invalid→nil
Task 3: minor (deferred): `?? 0` in day diff hides failure as 오늘 (cosmetic)
Task 3: minor (deferred): tests lack non-Seoul DST zone, year rollover, D+n>1 cases
Task 4: minor (deferred): DST-gap fire time drifts +1h (plan-mandated; Seoul unaffected). Fix: `calendar.nextDate(after:matching:matchingPolicy:.nextTime)`
Task 3: complete (commit 345a2f0, review clean)
Task 4: complete (commit 773f2c5, review clean)
Task 5+6 (batched): implementer aadb618bf1dd6ba69 (sonnet), reviewer a3623c11588334995 (opus)
Task 6: minor (deferred): 200 with non-JSON body throws raw DecodingError (not JiraError); AppState generic catch in T15 surfaces localizedDescription — acceptable
Task 6: minor (deferred): URLError.cancelled → `.network("cancelled")` false error (plan-mandated). POINTER for T15 dispatch: refreshJira should ignore cancellation errors
Task 6: minor (deferred): unparseable `updated` → .distantPast silently
Task 6: minor (deferred): same status name in two categories → duplicate group headers / duplicate ForEach ids (rare)
Task 5: minor (deferred): Keychain.get hides OSStatus (locked/denied == missing); delete ignores status (plan-mandated)
Task 5: minor (deferred): defaults duplicated between Settings getters and later @AppStorage literals; `register(defaults:)` would unify
Task 5: minor (deferred): non-integral Double under Int key reads nil → default
Task 5: minor (deferred): only 3/18 SettingsKey strings pinned by test
Task 5: complete (commit 0f96d88, review clean)
Task 6: complete (commit 3e64342, review clean)
Task 7+8 (batched): implementer a9d17a17d0244eda0 (sonnet), reviewer a404e2d6ef1304d4b (opus) → Needs fixes (2 Important, plan-mandated)
Task 7: Ruling: ProcessRunner timeout must bound the whole call (stdin write + drain), not just the wait — spec §9.3 says 180s timeout; plan code let a child that never reads stdin hang the app forever — fix: deadline before I/O, stdin write on background queue, bounded drain both paths, read DataBox only on drain success — cost if wrong: a slightly slower normal path.
Task 8: Ruling: records() must survive invalid UTF-8 bytes — spec §8.4 "깨진 줄은 건너뜀"; plan's String(contentsOf:encoding:) returns nil for whole file — fix: Data + String(decoding:as:UTF8) — cost if wrong: none.
Task 8: Ruling: hook stdin read must not raise (spec §8.1 "어떤 오류든 exit 0") — fix main.swift `(try? FileHandle.standardInput.readToEnd()) ?? Data()` — cost: none.
Task 8: Ruling: smoke-test line written to real activity.jsonl by plan Step 7 — remove that one line (test artifact, would pollute today's summary).
Task 7: minor (deferred): SIGKILL reaches direct child only; grandchild `sleep 30` lingers; test could use `exec sleep 30`; process-group kill needs posix_spawn
Task 7: minor (deferred): GitActivity `calendar` param doesn't control git's TZ window
Task 7: minor (deferred): GitActivityTests depend on global git config (gpgsign/hooksPath)
Task 8: minor (deferred): write loop maps all errors to EIO, no EINTR retry
Task 8: minor (deferred): data-dir exclusion is plain prefix (no symlink resolve, no boundary)
Task 8: minor (deferred): "activity.jsonl"/"logs/" literals duplicated vs Paths
Task 8: minor (deferred): hook.log fallback could reuse O_APPEND open
Task 7+8: fix round 1/5 (4 addressed, 0 open — timeout bound, UTF-8 records, hook readToEnd, smoke line removed; commits e0e96ec..22e4448; re-reviewer a263b860ac20eef9a sonnet)
Task 7: minor (deferred): grandchild holding pipes after child exit → status -1/timedOut true with empty output (callers treat timedOut as no output)
Task 7: minor (deferred): reader/writer threads may outlive run() while orphaned grandchild holds pipes
Task 8: minor (deferred): records() split on "\n" treats CRLF as one Character (writer emits \n only)
Task 7: complete (commits 17b9634 + e203081, review clean after round 1)
Task 8: complete (commits e0e96ec + 22e4448, review clean after round 1)
Task 9+10 (batched): implementer a483840701901c8a9 (sonnet), reviewer aae0a3ded3b1ae1ba (opus) → Needs fixes (1 Important, plan-mandated)
Task 9: Ruling: Worklog.parse must only accept headers matching spec §8.4 `^## (\d{2}:\d{2}) · (.+)$` — plan code accepted any `## x · y` and traps on `## · x` (reviewer reproduced, exit 133) — fix: regex check on time + non-empty project, else body; add tests — cost if wrong: a stricter header rule, none.
Task 9: Ruling: Worklog.raw must survive invalid UTF-8 (user-editable file; same class as T8 fix) — Data + String(decoding:) — cost: none.
Task 10: minor (deferred): total-cap test doesn't pin kept count (66) or first kept index
Task 10: minor (deferred): hhmm timestamp not pinned in build test ([23:13] in Seoul for epoch 1_790_000_000)
Task 10: minor (deferred): removeFirst() loop O(n²)
Task 10: minor (deferred): section header shows only recs[0].cwd when two cwds share a project name
Task 9+10: fix round 1/5 (2 addressed, 0 open — header regex, UTF-8 raw; commits ec07bf8..dc26123; re-reviewer ae1dfb52f6a3587ee sonnet)
Task 9: minor (deferred): String(decoding:) keeps a leading UTF-8 BOM → first header fails hasPrefix (regression vs String(contentsOf:); macOS editors rarely emit BOM); strip \u{FEFF} in raw if wanted
Task 9: complete (commits 240e217 + dc26123, review clean after round 1)
Task 10: complete (commit ec07bf8, review clean)
Task 11+12 (batched): implementer a539ba3f78aeca005 (sonnet), reviewer a30c74b3ee6d90616 (opus) → Needs fixes (1 Important, plan-mandated)
Task 12: Ruling: installHook must never replace an unreadable settings.json without a backup — spec §8.2 "다른 훅/키는 손대지 않는다", §8.2 parse-failure → write nothing; plan's `try? Data(contentsOf:)` treated unreadable as missing and `try? copyItem` swallowed the failed backup — fix: `[:]` only when file does not exist, else throw; backup is `try` — cost if wrong: install fails loudly on a weird file instead of silently, acceptable.
Task 12: Ruling: resolve symlinks for settings.json before backup/write (dotfile-managed configs) — cost: none.
Task 12: Ruling: removeSkill deletes only SKILL.md and removes the dir only if empty (never delete user files) — cost: none.
Task 12: minor (deferred): hookStatus counts across events; 2 entries in one event + 0 in other → installed; install doesn't dedupe
Task 12: minor (deferred): malformed group (`hooks` not array / non-object element) gets replaced with [] — other tool's hook lost (malformed input only)
Task 12: minor (deferred): backup name collision within same second skipped silently; DateFormatter lacks en_US_POSIX; install/remove always write even if unchanged
Task 12: minor (deferred): JSON round trip reformats user's file (0.1 → 0.10000000000000001, key order)
Task 12: minor (deferred): isOurs matching loose (any command containing TaskWidget ending --hook)
Task 11: minor (deferred): locate accepts a directory as binary (isExecutableFile true for dirs)
Task 11: minor (deferred): PATH uses real home not injected `home`; configured binary's dirname not added to PATH (nvm shebang risk)
Task 11: minor (deferred): claudeFailed message uses stderr only; empty when error on stdout
Task 11: minor (deferred): summary log overwritten per attempt; summary-file write failure not logged
Task 11: minor (deferred): cwds in same repo/worktree → duplicate commits under multiple project keys (user works in worktrees) — dedupe by --show-toplevel or hash. Candidate for final review.
Task 11: minor (deferred): no tests for .busy, PATH prefix, collect commits
Task 11: note: "오늘 기록 없음" placeholder sticks for the day (force:false returns it) — spec-mandated to stop catch-up loops; manual "다시 생성" overrides
Task 11+12: fix round 1/5 (3 addressed, 0 open — unreadable settings.json safe, symlink target, removeSkill scoped, + backup -N suffix; commits 2131e69..7a605f6; re-reviewer a685aac4b504b790e sonnet)
Task 12: minor (deferred): unreadable settings reuses .invalidSettingsJSON (UI says "invalid JSON" for permission problem)
Task 12: minor (deferred): backups accumulate unbounded (every install/remove writes one)
Task 12: minor (deferred): .atomic write drops original permission bits (0600 settings.json)
Task 12: minor (deferred): removeSkill leaves dir if .DS_Store remains
Task 11: complete (commit 1787720, review clean)
Task 12: complete (commits 2131e69 + 7a605f6, review clean after round 1)
--- Core library complete: 101 tests ---
Task 13: implementer afacd803f8f411057 (sonnet), reviewer a44729d9a6180a39e (opus)
Task 13: Ruling: observer closure wraps panel call in `MainActor.assumeIsolated` (queue: .main) — accepted, silences isolation warning, no behavior change — cost: none.
Task 13: note: screencapture blocked (no screen-recording permission) → all visual/interaction checks (status icon, click toggle/menu, sheet, close-hides, hover opacity, first-launch center, no Dock icon) UNVERIFIED — user manual checklist at the end
Task 13: minor (deferred): RootView header may sit below titlebar safe-area inset; `.ignoresSafeArea(.container, edges: .top)` if so (confirm by eye)
Task 13: minor (deferred): hovering flag stuck true after orderOut → alpha 1.0 on next show. POINTER for T17 (opacity): reset hovering=false before orderOut
Task 13: minor (deferred): defaults observer re-applies appearance on every defaults write (frame autosave during drag)
Task 13: minor (deferred): frame restore order relies on AppKit internals; prefer setFrameUsingName then setFrameAutosaveName
Task 13: minor (deferred): Ctrl-click toggles instead of menu
Task 13: minor (deferred): toggle hides a visible-but-buried panel when alwaysOnTop off
Task 13: minor (deferred): .sheet applied after .environment(fontScale) → settings sheet doesn't inherit fontScale. POINTER for T17
Task 13: minor (deferred): canBecomeKey override redundant; NSApp.activate(ignoringOtherApps:) soft-deprecated
Task 13: complete (commit 6e12a3c, review clean)
Task 14+15 (batched): implementer afb3aa274957d2dc5 (sonnet)
Task 14+15: reviewer a96a75118d80fed3b (opus) → Needs fixes (1 Important, plan-mandated)
Task 14: Ruling: DuePopover — add "오늘" quick button (spec §6.1 listed 내일/다음 주 월/마감 없음; amended) and dismiss only from quick buttons; calendar selection saves immediately but keeps the popover open — undated todo starts at Date() so clicking today fires no onChange, and month arrows could auto-commit — cost if wrong: one extra button, none.
Task 15: minor (deferred): generic-catch cancellation guard unreachable (JiraClient wraps all); merge catches; better: Core rethrows cancellation
Task 15: minor (deferred): jiraConfigured false on first render → setup button flashes; compute in init
Task 15: minor (deferred): invalid jiraBaseURL fails silently (no jiraError)
Task 15: minor (deferred): in-flight refresh holds jiraLoading → new .task's immediate refresh skipped
Task 15: minor (deferred): stale jiraIssues/count when email removed; clear when not configured
Task 15: minor (deferred): browse link double slash if baseURL ends with "/"; use appendingPathComponent
Task 15: minor (deferred): no refresh on panel re-show (spec-compliant, time shown)
Task 15: note: Keychain.get is synchronous on MainActor each refresh; ad-hoc re-sign triggers keychain prompt — POINTER for T17 manual check
Task 15: note: `formatted(time: .shortened)` → "오후 3:05" in ko locale (brief expected HH:mm) — cosmetic
Task 15: note: after token saved in T17, section shows setup button until next refresh tick — T17 calls refreshJira after save (already in brief)
Task 14: minor (deferred): save failure only NSLog'd (plan-mandated)
Task 14: minor (deferred): badges/sort computed at render from Date(); stale after midnight until redraw; done list shows overdue badge
Task 14: minor (deferred): fontScale not applied to setup button, 비우기, DuePopover
Task 14+15: fix round 1/5 (1 addressed, 0 open — 오늘 button, calendar keeps popover open, startOfDay init; commits 75bacb6..41ea8c7; re-reviewer ad25ac627d1b849ec sonnet)
Task 14: minor (deferred): garbled Korean comment in DuePopover.swift:10
Task 14: note: UNVERIFIED by anyone — popover dismiss via dismiss(), calendar pick keeps popover open, 4-button row fit, month arrows don't commit
Task 14: complete (commits 0afc97a + 41ea8c7, review clean after round 1)
Task 15: complete (commit 75bacb6, review clean)
Task 16+17 (batched): implementer a92e3cae73a56e6f7 (sonnet), reviewer abe708c43bed801aa (opus) → Needs fixes (1 Important — my own ruling incomplete)
Task 17: Ruling: replace the two `hovering = false` insertions with `override func orderOut(_:) { hovering = false; applyAppearance(); super.orderOut(sender) }` — alpha is only computed in applyAppearance, so the flag reset alone left the panel at 1.0 on re-show — cost: none.
Task 17: Ruling: trim whitespace from the pasted Jira token before Keychain.set (trailing newline → confusing 401) — cost: none.
Task 16: minor (deferred): summaryError not scoped to day (plan-mandated); clear in loadSummary when day changes
Task 16: minor (deferred): Timer.publish stored in struct re-created per RootView render → 30s refresh can stretch; replace with .task(id: day) loop
Task 16: minor (deferred): 로그 button opens nothing for .busy / write-failure (no log written)
Task 16: minor (deferred): Task.detached captures non-Sendable SummaryService/Summary — Swift 6 hazard only
Task 16: minor (deferred): 복사 enabled for whitespace-only worklog; DateFormatter per render
Task 17: minor (deferred): activity.jsonl decoded on main thread on every sheet open/toggle
Task 17: minor (deferred): "토큰 없음" shown for invalid URL; minute picker blank for non-multiple-of-5 saved value
Task 17: minor (deferred): 460×600 sheet overhangs 320×520 panel (plan-mandated, visual)
Task 17: note: UNVERIFIED — sheet typing on nonactivating panel, @EnvironmentObject reaching sheet (crash on 저장 if missing), live effect of each setting, login item, hook/skill install
Task 16+17: fix round 1/5 (2 addressed, 0 open — orderOut override, token trim; commits ce574a2..3058664; re-reviewer a1fe624bb7e8bdbbd sonnet)
Task 17: minor (deferred): whitespace-only token leaves whitespace in field; jiraEmail/jiraBaseURL not trimmed
Task 16: complete (commit f223a6c, review clean)
Task 17: complete (commits ce574a2 + 3058664, review clean after round 1)
Task 18+19 (batched): implementer a6a96246bfbe83c61 (sonnet), reviewer afe7d8f81b993b1c1 (opus) → Needs fixes (1 Important, plan-mandated)
Task 18: Ruling: wake observer must `reschedule()` then `catchUp()` — CFRunLoopTimer deadline is mach_absolute_time which stops during sleep, so a timer pending across a lid-close fires the next morning and writes an empty "today" summary — cost if wrong: none.
Task 18: Ruling: settings-change catch-up debounced ~3s (cancellable Task) so hour-then-minute edits don't trigger a generation at the half-edited time; reschedule stays immediate — cost if wrong: catch-up 3s later than before.
Task 19: Ruling: README checklist must include Task 18 Step 3 manual items (permission prompt, past-time → immediate generation, time change with existing file → no regen, 요약 지금 생성 → tab switch + force, 요약 실패 notification) — docs only.
Task 18: minor (deferred): scheduled run skipped when another generation is in progress → no retry until next trigger
Task 18: minor (deferred): generateNow doesn't switch SummaryView.day to today if user is browsing another day
Task 18: minor (deferred): no UNUserNotificationCenterDelegate willPresent → banners silent while app active; first-run notify may race the permission grant
Task 18: minor (deferred): NSLog prints fire date in UTC
Task 18: note: smoke launch registered a notification-permission request for com.lsm0506.TaskWidget (build/ bundle) — user may not see a fresh prompt; check System Settings > Notifications
Task 18+19: fix round 1/5 (3 addressed, 0 open — wake reschedule, debounce, README checklist; commits 12ecce5..8cbd698; re-reviewer ab3cecf904627c990 sonnet)
Task 18: minor (deferred): fire() has no "now >= scheduled" guard (stale timer firing before wake handler)
Task 18: minor (deferred): README says "요약 실패: {이유}" but notification is title "요약 실패" + body reason
Task 18: complete (commits 0546cd6 + 8cbd698, review clean after round 1)
Task 19: complete (commit 12ecce5 + 8cbd698 README part, review clean after round 1)
--- All 19 tasks complete. HEAD 8cbd698, merge-base 30a2b4d ---
Final review: reviewer a1cbb472bbd59cf8c (opus) → With fixes (0 Critical, 4 Important, 7 Minor; triage: fix L176 + L106 before merge, defer 82)
Final: Ruling: catch-up also covers the previous 7 days on launch/wake (oldest first, generate only when collect() is non-empty, never write the "기록 없음" placeholder for past days, one at a time) — spec §10.2 said "today" but its purpose is recovering missed runs; lid-close at 17:50 loses the day otherwise — cost if wrong: up to 7 extra claude -p runs after a long absence.
Final: Ruling: fire() → catchUp() then reschedule() (guard now >= scheduled) — closes L176 — cost: none.
Final: Ruling: ClaudeRunner args become `-p --output-format text --tools "" --strict-mcp-config --no-session-persistence [--model X]` — unattended run over untrusted session text must not have tools/MCP; flags verified in `claude --help` (2.1.287); claudeFailed message falls back to stdout tail when stderr empty (L104) — cost if wrong: if a future CLI drops a flag the run fails loudly (claudeFailed) and the user sees it in the 요약 tab.
Final: Ruling: GitActivity filters `--author=<git config user.email>` when non-empty; SummaryService.collect dedupes commit lines by short hash across cwds (L106) — teammates' pulled commits were credited as the user's work — cost if wrong: commits authored under a different email are omitted.
Final: Ruling: hook record requires non-empty `cwd` (Review Focus #1) — cost: none.
Final: Ruling: README checklist gains "activity.jsonl has prompt+stop lines after a session" and "keychain prompt → 항상 허용" — docs.
Final fix wave: implementer a170e79a04ee13e1e (sonnet) commit a058b4c (107 tests); re-reviewer a4c97eaeb24d529df (opus) → all 6 addressed, 3 new Minor
Final: Ruling: implementer's addition "stop at first past-day failure" accepted, BUT today must never be blocked by past days — follow-up: on a past-day failure skip remaining past days and still run today; after the loop re-check whether today is due (generateIfMissing when now >= scheduled) so a timer that fired during a long catch-up isn't lost — cost if wrong: one extra existing() check.
Final: Ruling: `--author=<email>` anchored as `<email>` to avoid substring matches (kim@ vs jkim@) — cost: none.
Final: Ruling: spec §9.3/§10.2 text updated to the ruled behavior (claude flags, 7-day catch-up) — docs.
Final follow-up: commit 37f6d5f (today never blocked by past days, author anchor, spec/README); re-reviewer a46eafe74550531fc (sonnet) → all addressed, 0 Critical/Important
Final: minor (deferred): spec §10.2 trigger list omits "설정 시각 변경(3초 디바운스)"; spec notification text doesn't mention past-day "{date} 요약 완료" wording
Final: minor (deferred): past days with no file and no activity re-run collect() on every trigger (by design, cheap)
Final: note: manual "요약 지금 생성" overlapping the 18:00 timer → today waits for next trigger (next day's catch-up fills it) — acceptable
--- Branch ready: HEAD 37f6d5f, 107 tests ---
Final: deferred (82) per reviewer triage; top follow-ups: L158 activity.jsonl growth/main-thread decode, L42 TodoStore unreadable→overwrite, L77/78 grandchild pipes, L170 busy-skip retry, Minor #2 single-quote hook path, #3 skill marker, #4 heading check on claude output, #5 testNotFound non-hermetic (candidate paths injectable), #6 keychain token cache, #7 SKILL.md date check step.
Task 15: Ruling: refreshJira ignores cancellation — guard in generic catch (CancellationError / URLError.cancelled) AND `if Task.isCancelled { return }` in the JiraError catch, because JiraClient.get wraps URLError.cancelled into .network — accepted; cleaner fix (Core rethrows cancellation unwrapped) deferred to final review — cost if wrong: a cancelled refresh silently shows stale data, acceptable.
