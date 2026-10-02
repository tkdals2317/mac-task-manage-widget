# TaskWidget 설계 문서

작성일: 2026-10-02
상태: 2차 개정 (레이아웃 C, 데드라인, 훅+스킬 연동, 설정 확장)

## 1. 목적

macOS에서 다른 창 위에 항상 떠 있는 작은 할 일 위젯. 한 화면에서 본다.

1. 일반 할 일 (로컬 저장, 마감일 포함)
2. 내게 할당된 Jira 미완료 이슈 (읽기 전용)
3. 오늘 한 일 요약. 입력은 (a) 세션 중 `/worklog` 스킬로 Claude가 직접 쓴 업무 일지, (b) Claude Code 훅이 자동으로 쌓은 활동 기록, (c) git 커밋. 지정 시각에 `claude -p`가 셋을 합쳐 최종본 생성.

사용자는 한 명(본인). 서버, 동기화, 멀티 디바이스 없음. 요약은 개인 기록용이며 외부 게시 없음.

## 2. 범위

### 포함

- 메뉴바 상주 앱, 플로팅 패널 토글
- Todo CRUD + 마감일 (추가, 완료 토글, 삭제, 마감 설정/해제, 완료 항목 일괄 정리)
- Jira 미완료 이슈 목록 조회, 상태별 그룹, 클릭 시 브라우저로 열기
- Claude Code 연동: 훅(자동 활동 기록) + `/worklog` 스킬(수동 일지). 설정에서 원클릭 설치/제거
- 지정 시각에 하루 요약 자동 생성, 수동 생성/재생성, 날짜별 열람, 복사
- 설정 화면 (외관, 창, Jira, 요약, Claude 연동, 데이터)

### 제외 (필요해지면 추가)

- 전역 단축키
- Jira 상태 전이, 이슈 생성, 코멘트
- 요약 프롬프트 템플릿 편집
- 여러 날 묶음 요약, 주간 요약
- Slack/Confluence 게시
- iCloud/서버 동기화
- 훅 설치 이전 날짜의 과거 세션 복원 (트랜스크립트 파싱 안 함)

## 3. 기술 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 언어/UI | Swift 5 language mode, SwiftUI + AppKit(NSPanel) | 항상-위 창을 NSPanel 설정 몇 줄로 해결. 설치 의존성 없음 |
| 빌드 | SwiftPM (Xcode 프로젝트 없음) | 파일 적고 CLI로 빌드/테스트 가능 |
| 배포 타깃 | macOS 14 | 현재 머신 macOS 26, SDK 15.2 |
| Claude 활동 기록 | Claude Code 훅 `UserPromptSubmit` + `Stop` → 앱 바이너리 `--hook` 모드 | 공식 훅 입력(`prompt`, `last_assistant_message`, `session_id`, `cwd`)만 사용. 문서가 트랜스크립트 직접 파싱 대신 이 필드 사용을 권장. jq 등 외부 의존 없음 |
| 수동 일지 | `~/.claude/skills/worklog/SKILL.md` | 세션 컨텍스트를 아는 Claude가 가장 정확한 요약을 씀 |
| 요약 생성 | `claude -p` CLI 호출 | API 키 불필요, 기존 구독 사용 |
| Jira 호출 | URLSession + Basic Auth | 의존성 없음 |
| 토큰 저장 | Keychain (Security framework) | 평문 파일 금지. `~/.claude/credentials.md`는 읽지 않음 |
| 스케줄 | 앱 내부 Timer + 런치/웨이크 시 catch-up | 메뉴바 상주 앱이므로 launchd 불필요 |
| 외부 패키지 | 없음 | 전부 Foundation/AppKit/SwiftUI/Security/ServiceManagement로 가능 |

## 4. 구조

```
task-manager/
  Package.swift
  Makefile                       # build / test / app / install / run
  Resources/Info.plist           # LSUIElement=true, CFBundleIdentifier
  Sources/
    TaskWidgetCore/              # 라이브러리. UI 없음. 전부 테스트 대상
      Models.swift               # Todo, JiraIssue, Summary, ActivityRecord, WorklogEntry
      DueBadge.swift             # 마감 배지 텍스트/상태 순수 함수, 정렬 비교자
      TodoStore.swift            # JSON 파일 로드/저장
      Settings.swift             # UserDefaults 래퍼
      Keychain.swift             # Jira 토큰 get/set/delete
      JiraClient.swift           # search/jql, myself 호출, 디코딩
      ActivityLog.swift          # activity.jsonl append(훅 모드) + 날짜별 read
      Worklog.swift              # worklog/YYYY-MM-DD.md 읽기, 섹션 파싱
      GitActivity.swift          # 프로젝트별 오늘 커밋
      SummaryPrompt.swift        # 프롬프트 조립
      ClaudeRunner.swift         # claude -p 프로세스 실행
      SummaryService.swift       # 수집 -> 프롬프트 -> 실행 -> 파일 저장
      Schedule.swift             # nextFireDate 순수 함수
      ClaudeIntegration.swift    # settings.json 훅 merge/제거, SKILL.md 설치/제거, 상태 확인
      Paths.swift                # 데이터 디렉터리 경로 상수
    TaskWidget/                  # 실행 파일. AppKit + SwiftUI
      main.swift                 # `--hook`이면 ActivityLog.append 후 종료, 아니면 앱 실행
      AppDelegate.swift          # 상태바 아이템, 패널 생성, 스케줄러 소유
      FloatingPanel.swift        # NSPanel 서브클래스 (투명도, 호버, 레벨)
      Scheduler.swift            # Timer + wake 알림 -> SummaryService
      Views/
        RootView.swift           # 탭 컨테이너 (할 일 | 요약), 기어
        TasksView.swift          # "내 할 일" 섹션 + "Jira" 섹션
        TodoRow.swift            # 체크박스, 제목, 마감 배지, 삭제
        DuePopover.swift         # 날짜 선택 팝오버
        JiraSection.swift
        SummaryView.swift
        SettingsView.swift
        MarkdownText.swift       # 줄 단위 간이 렌더러
  Tests/TaskWidgetCoreTests/
    Fixtures/
      activity-sample.jsonl
      worklog-sample.md
      settings-with-hooks.json
      jira-search.json
    TodoStoreTests.swift
    DueBadgeTests.swift
    ScheduleTests.swift
    JiraClientTests.swift
    ActivityLogTests.swift
    WorklogTests.swift
    SummaryPromptTests.swift
    ClaudeIntegrationTests.swift
  docs/superpowers/specs/
```

Core는 AppKit/SwiftUI를 import하지 않는다. 실행 파일은 Core를 조립만 한다.

### 데이터 디렉터리

`~/Library/Application Support/TaskWidget/` (이하 `DATA`)

```
todos.json
activity.jsonl                  # 훅이 append. 한 줄 = 한 이벤트
worklog/YYYY-MM-DD.md           # /worklog 스킬이 append
summaries/YYYY-MM-DD.md         # 최종 요약
logs/summary-YYYY-MM-DD.log     # claude stderr, 수집 통계
logs/hook.log                   # 훅 모드 오류만 (best effort)
```

## 5. Shell (창, 메뉴바)

- `Info.plist`에 `LSUIElement = true`. Dock 아이콘 없음.
- `NSStatusItem` 하나. 아이콘 클릭 → 패널 show/hide 토글. 우클릭 메뉴: 요약 지금 생성, 설정, 종료.
- `FloatingPanel: NSPanel`
  - `styleMask = [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView]`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`
  - `level` = 설정 `alwaysOnTop` ? `.floating` : `.normal`
  - `collectionBehavior` = 설정 `allSpaces` ? `[.canJoinAllSpaces, .fullScreenAuxiliary]` : `[.moveToActiveSpace]`
  - `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`
  - `alphaValue` = 설정 `opacity` (0.6~1.0). `hoverOpaque`가 켜져 있으면 `NSTrackingArea`로 mouseEntered 시 1.0, mouseExited 시 설정값 복귀.
  - `setFrameAutosaveName("TaskWidgetPanel")`, 기본 크기 320×520, 최소 280×360
  - 닫기 버튼은 hide로 동작 (앱 종료 아님)
- 테마: 설정 `theme`가 `light`/`dark`면 `panel.appearance = NSAppearance(named:)`, `system`이면 nil.
- 패널 내용: `NSHostingView(rootView: RootView(...))`
- `RootView`: 상단 세그먼트 **할 일 | 요약**, 우측 기어 → 설정 시트. 마지막 탭은 UserDefaults에 기억. 글자 크기는 `fontScale`(0.9/1.0/1.15)을 환경값으로 내려 모든 Text가 곱해 씀.

## 6. 할 일 탭 (TasksView)

세로 두 섹션. 각 섹션 헤더 클릭으로 접기/펴기(상태 기억).

### 6.1 내 할 일

```swift
struct Todo: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var done: Bool
    var createdAt: Date
    var completedAt: Date?
    var dueDate: String?        // "yyyy-MM-dd" 로컬 날짜. 시각 없음
}
```

- `TodoStore`: `load()`, `save([Todo])`. 파일 `todos.json`, 배열 JSON, ISO8601 날짜. 쓰기는 임시 파일 후 `replaceItemAt`로 원자적 교체. 파일 없으면 빈 배열. 파싱 실패 시 `todos.corrupt-<timestamp>.json`으로 이름 바꾸고 빈 배열로 시작.
- 추가: 상단 텍스트 필드, Enter(공백만이면 무시). 마감 없이 생성.
- 행: 체크박스 · 제목(한 줄 생략) · 마감 배지 · hover 시 ×.
- 마감 배지 (`DueBadge.text(due:today:)` 순수 함수):

| 조건 (`days = due - today`) | 표시 | 색 |
|---|---|---|
| nil | 📅 (흐리게) | 없음 |
| days < 0 | `D+{-days}` | 빨강 |
| days == 0 | `오늘` | 주황 |
| 1 ≤ days ≤ 7 | `D-{days}` | 기본 |
| days > 7 | `M/d` | 기본 |

- 배지 클릭 → `DuePopover`: `DatePicker(.graphical)` + "내일" "다음 주 월" 빠른 버튼 + "마감 없음". 선택 즉시 저장.
- 정렬 (미완료): `dueDate` 오름차순, nil은 맨 뒤, 동률은 `createdAt` 오름차순. `DueBadge.sort(_:)`로 구현, 테스트 대상.
- 완료: 접힌 "완료 (n)" 소섹션, "비우기" 버튼으로 전부 삭제. 완료 토글 시 `completedAt` 기록/해제.
- 변경 즉시 저장.

### 6.2 Jira

```swift
struct JiraIssue: Codable, Identifiable, Equatable {
    var id: String             // key, e.g. NMRS-12345
    var summary: String
    var status: String         // fields.status.name
    var statusCategory: String // fields.status.statusCategory.key: new|indeterminate|done
    var priority: String?      // fields.priority.name
    var updated: Date
}
```

- 요청: `GET {jiraBaseURL}/rest/api/3/search/jql`
  - query: `jql` = 설정 `jiraJQL`이 비어 있지 않으면 그 값, 아니면 `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`; `fields=summary,status,priority,updated`; `maxResults=100`
  - 헤더: `Authorization: Basic base64(email:token)`, `Accept: application/json`
  - 100건 초과는 무시. 초과 시 목록 하단에 "100건까지만 표시".
- `JiraClient.fetchMyOpenIssues() async throws -> [JiraIssue]`, `JiraClient.whoAmI() async throws -> String` (`/rest/api/3/myself`의 `displayName`).
- 에러: 401/403 → `JiraError.unauthorized`, 그 외 non-2xx → `JiraError.http(status)`, 네트워크 → `JiraError.network(Error)`, JQL 오류(400) → `JiraError.badQuery(message)`.
- `updated`는 Jira 포맷 `yyyy-MM-dd'T'HH:mm:ss.SSSZ` 파서 사용.
- 표시: `statusCategory` 순서 `indeterminate` → `new` → 나머지. 그룹 헤더 = 상태 이름 + 건수. 행: 우선순위 점(Highest/High 빨강, Medium 주황, 나머지 회색) · `KEY` 모노스페이스 · summary 한 줄 생략. 클릭 → `NSWorkspace.shared.open({jiraBaseURL}/browse/{key})`.
- 갱신: 패널 보일 때 설정 `jiraRefreshMinutes`마다, 탭 진입 시, 섹션 헤더 ↻ 버튼. 마지막 성공 시각 표시. 실패 시 기존 목록 유지 + 에러 한 줄. 토큰 미설정이면 "설정에서 Jira 토큰 입력" 버튼만.

## 7. 설정

시트 하나, 섹션별 그룹. 저장은 즉시.

### 7.1 키

| 섹션 | 키 | 타입 | 기본값 |
|---|---|---|---|
| 외관 | `opacity` | Double | 1.0 (범위 0.6~1.0, 슬라이더) |
| 외관 | `hoverOpaque` | Bool | true |
| 외관 | `theme` | String | `system` (`system`/`light`/`dark`) |
| 외관 | `fontScale` | Double | 1.0 (`0.9`/`1.0`/`1.15` = 작게/보통/크게) |
| 창 | `alwaysOnTop` | Bool | true |
| 창 | `allSpaces` | Bool | true |
| 일반 | 로그인 시 실행 | — | `SMAppService.mainApp.status`에서 읽고 register/unregister |
| Jira | `jiraBaseURL` | String | `https://midasitweb-jira.atlassian.net` |
| Jira | `jiraEmail` | String | `""` |
| Jira | 토큰 | Keychain | — |
| Jira | `jiraRefreshMinutes` | Int | 5 (1/5/15) |
| Jira | `jiraJQL` | String | `""` (빈 값 = 기본 JQL) |
| 요약 | `summaryHour` / `summaryMinute` | Int | 18 / 0 |
| 요약 | `summaryNotify` | Bool | true |
| 요약 | `claudeModel` | String | `""` (빈 값 = CLI 기본) |
| 요약 | `claudePath` | String | `""` (빈 값 = 자동 탐색) |
| UI | `lastTab` | String | `tasks` |
| UI | `todoSectionCollapsed` / `jiraSectionCollapsed` | Bool | false / false |

Jira 토큰: Keychain generic password, service `com.lsm0506.TaskWidget.jira`, account = `jiraEmail`. 설정의 토큰 필드는 `SecureField`, 저장 시 Keychain에만 쓴다. "연결 테스트" 버튼 → `whoAmI()` 결과 displayName 또는 에러 표시.

claude 바이너리 탐색 순서: `claudePath` → `~/.local/bin/claude` → `/opt/homebrew/bin/claude` → `/usr/local/bin/claude`. 모두 없으면 `SummaryError.claudeNotFound`.

### 7.2 Claude 연동 섹션

두 줄, 각각 상태 + 버튼:

- **활동 훅**: 상태 `설치됨` / `미설치` / `경로 불일치(앱 이동됨)`. 버튼 `설치` / `제거` / `재설치`. 오른쪽에 "오늘 기록 n건".
- **/worklog 스킬**: 상태 `설치됨` / `미설치`. 버튼 `설치` / `제거`.
- 하단: "데이터 폴더 열기", "요약 폴더 열기" (Finder).

## 8. Claude 연동

### 8.1 훅 모드 (`TaskWidget --hook`)

`main.swift`가 `CommandLine.arguments`에 `--hook`이 있으면 NSApplication을 띄우지 않고:

1. stdin 전체를 읽어 JSON 파싱. 실패 → exit 0.
2. `hook_event_name`이 `UserPromptSubmit`이면 `text = prompt`, `Stop`이면 `text = last_assistant_message`. 그 외 → exit 0.
3. `cwd`가 `DATA` 경로로 시작하면 exit 0 (요약 생성용 `claude -p` 세션 제외).
4. `text` 트림 후 비면 exit 0. `prompt`는 2,000자, `last_assistant_message`는 4,000자로 자름.
5. 한 줄 JSON을 `activity.jsonl`에 `O_APPEND`로 append:

```json
{"ts":"2026-10-02T18:12:33+09:00","event":"prompt","session":"<session_id>","cwd":"/Users/.../mrs-cms","text":"..."}
```

`event`는 `prompt` | `stop`. `ts`는 ISO8601 로컬 오프셋 포함.

6. 어떤 오류든 exit 0. Claude 세션을 막지 않는다. 오류는 `logs/hook.log`에 best effort.

settings.json에 추가되는 항목 (두 이벤트 동일):

```json
{ "hooks": [ { "type": "command", "command": "/Applications/TaskWidget.app/Contents/MacOS/TaskWidget --hook", "timeout": 5 } ] }
```

### 8.2 ClaudeIntegration (설치/제거/상태)

- 대상 파일 `~/.claude/settings.json`. 없으면 `{}`로 시작.
- 설치: 백업 `settings.json.bak-YYYYMMDD-HHmmss` 작성 → JSON 파싱 → `hooks.UserPromptSubmit`, `hooks.Stop` 배열에 위 항목 append (이미 `TaskWidget --hook`을 포함한 command가 있으면 그 항목의 command를 현재 실행 경로로 갱신) → pretty JSON으로 저장. 다른 훅/키는 손대지 않는다. 키 순서는 보존하지 않는다(JSONSerialization 한계, 허용).
- 제거: command에 `TaskWidget --hook`이 포함된 항목만 제거. 빈 배열이 되면 그 이벤트 키 삭제.
- 상태: 두 이벤트 모두에 항목이 있고 command 경로가 `Bundle.main.executableURL`과 같으면 `installed`, 항목은 있으나 경로 다르면 `pathMismatch`, 없으면 `notInstalled`.
- 스킬 설치: `~/.claude/skills/worklog/SKILL.md`를 아래 내용으로 작성(덮어씀). 제거: 디렉터리 삭제. 상태: 파일 존재 여부.
- 파싱 실패(settings.json이 유효 JSON이 아님) → 아무것도 쓰지 않고 에러 표시.

### 8.3 `/worklog` 스킬

```markdown
---
name: worklog
description: 현재 세션에서 한 일을 정리해 TaskWidget 업무 일지에 기록한다. "/worklog", "오늘 한 거 기록해", "업무 일지 남겨", "worklog" 요청 시 사용.
---

현재 세션에서 지금까지 한 일을 정리해 아래 파일 끝에 append 한다.

파일: `~/Library/Application Support/TaskWidget/worklog/YYYY-MM-DD.md` (오늘 로컬 날짜. 디렉터리 없으면 만든다)

형식:

## HH:mm · <프로젝트명>
- 한 일 (성과/결과 위주) 3~7개, 각 1~2문장
- 미완료: (있을 때만, 한 줄)

규칙:
- 프로젝트명 = 현재 작업 디렉터리의 마지막 경로 요소.
- 파일이 없으면 첫 줄 `# YYYY-MM-DD 업무 일지` 후 빈 줄, 그 다음 섹션.
- 기존 내용은 수정하지 않는다. 끝에 append만.
- `$ARGUMENTS`가 있으면 그 범위나 관점을 반영한다 (예: "오전 작업만", "버그 수정 위주").
- 추측하지 않는다. 이 세션에서 실제로 한 일만 쓴다.
- 기록 후 추가한 섹션을 그대로 보여준다.
```

### 8.4 ActivityLog / Worklog 읽기

- `ActivityLog.records(on day: Date) -> [ActivityRecord]`: `activity.jsonl` 줄 단위 스트리밍, JSON 실패 줄 스킵, `ts` 로컬 날짜 == day인 것만. 정렬 ts 오름차순.
- `Worklog.entries(on day: Date) -> [WorklogEntry]`: `worklog/YYYY-MM-DD.md`를 `^## (\d{2}:\d{2}) · (.+)$` 헤더로 분할. `{time, project, body}`. 파일 없으면 빈 배열. 원문 markdown 전체도 `Worklog.raw(on:)`로 제공.

## 9. 요약 파이프라인

`SummaryService.generate(for day: Date, force: Bool) async throws -> Summary`

순서: 수집 → 프롬프트 조립 → claude 실행 → 저장. 동시에 하나만 실행. `force == false`이고 해당 날짜 파일이 있으면 기존 것 반환.

### 9.1 수집

1. `worklog = Worklog.entries(on: day)`. `coveredProjects = Set(worklog.map(\.project))`.
2. `activity = ActivityLog.records(on: day)`. `project = cwd 마지막 경로 요소`. `coveredProjects`에 포함된 프로젝트의 레코드는 버린다(일지가 있으면 raw 불필요).
3. 남은 activity 텍스트 캡: `prompt` 400자, `stop` 1,200자. 전체 합 80,000자 초과 시 오래된 것부터 제거.
4. `GitActivity`: 2번에서 버리기 전의 activity 전체에서 고유 `cwd`를 모은다(worklog는 cwd가 없으므로 이 집합으로 커밋을 찾는다. 일지만 있고 activity가 없는 프로젝트는 커밋 생략). 각 `cwd`에 대해 `git -C <cwd> rev-parse --is-inside-work-tree` 성공 시 `git log --since=<day 00:00> --until=<day 23:59:59> --format=%h %s` 최대 30줄. 각 10초 타임아웃. 실패는 무시.
5. worklog 0건, activity 0건, 커밋 0건이면 claude 호출 없이 `# {date} 업무 요약\n\n오늘 기록 없음` 저장.

통계(worklog 섹션 수, activity 유지/제거 수, 프로젝트 목록, 커밋 수)는 로그 파일에.

### 9.2 프롬프트

```
당신은 개발자의 하루 업무 일지를 작성합니다. 날짜: {YYYY-MM-DD}

입력은 세 종류입니다.
1) 개발자가 세션 중 직접 기록한 업무 일지 — 가장 신뢰도 높음. 이 내용을 우선합니다.
2) 일지가 없는 프로젝트의 Claude Code 대화 기록(raw) — 보완용.
3) git 커밋 — 사실 확인용.

도구를 사용하지 말고, 아래 데이터만 근거로 한국어 Markdown을 출력하세요. 데이터에 없는 일은 쓰지 않습니다. 다른 설명 없이 Markdown만 출력합니다.

형식:
# {YYYY-MM-DD} 업무 요약
## {프로젝트명}
- 한 일 (성과/결과 위주, 3~7개, 각 1~2문장)
(프로젝트마다 반복)
## 미완료 / 내일
- 일지나 대화에서 드러난 미완료 작업, 다음 단계

=== 1) 업무 일지 ===
{worklog 원문 그대로}

=== 2) 대화 기록: {project} ({cwd}) ===
[HH:mm] user: ...
[HH:mm] assistant: ...

=== 3) 커밋: {project} ===
abc1234 feat: ...
```

빈 섹션은 `(없음)`으로 표기.

### 9.3 ClaudeRunner

```swift
func run(prompt: String, model: String?, timeout: TimeInterval = 180) async throws -> String
```

- `Process`: `<claudePath> -p --output-format text [--model <model>]`
- 프롬프트는 stdin으로 전달.
- `currentDirectoryURL` = `DATA` (훅이 이 cwd를 제외하므로 자기 기록 안 됨).
- 환경: 현재 환경 복사 후 `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` 제거. `PATH` 앞에 `~/.local/bin:/opt/homebrew/bin:/usr/local/bin` 추가.
- 타임아웃 시 `terminate()` 후 `SummaryError.timeout`. exit ≠ 0 → `SummaryError.claudeFailed(code, stderrTail)`. stdout 비면 `SummaryError.emptyOutput`.

### 9.4 저장과 표시

- `summaries/YYYY-MM-DD.md` 원자적 쓰기. `Summary { date, markdown, generatedAt }`.
- `SummaryView`:
  - 상단 `◀ 2026-10-02 (목) ▶`. 어느 날짜든 이동 가능.
  - 본문 우선순위: 요약 파일 있으면 요약. 없으면 그날 worklog 원문(헤더 "업무 일지 (요약 전)"). 둘 다 없으면 "기록 없음".
  - `MarkdownText`: 줄 단위. `# ` 제목, `## ` 소제목(bold), `- ` 불릿, 나머지 본문. 인라인 강조는 `AttributedString(markdown:)`.
  - 하단: 생성 시각 · "복사"(현재 본문 markdown → pasteboard) · "생성"/"다시 생성"(force) · "일지 열기"(worklog 파일을 기본 앱으로, 없으면 비활성).
  - 생성 중 스피너. 실패 시 에러 한 줄 + "로그 열기".
  - 오늘 탭을 볼 때 worklog 파일이 바뀌면(탭 진입/30초 폴링) 다시 읽는다.

## 10. 스케줄과 에러

### 10.1 Schedule (순수 함수)

```swift
func nextFireDate(after now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date
```

오늘 `hour:minute`가 `now`보다 뒤면 오늘, 아니면 내일.

### 10.2 Scheduler (앱)

- 시작 시 `Timer`를 `nextFireDate`에 등록. 설정 시각 변경 시 재등록.
- 발화: 오늘 파일 없으면 `generate(today, force: false)`. 끝나면 다음 날로 재등록.
- catch-up: 앱 시작, `NSWorkspace.didWakeNotification`, 설정 시각 변경 시 → `now ≥ 오늘 설정 시각`이고 오늘 파일 없으면 즉시 생성.
- `summaryNotify`가 켜져 있으면 완료 시 `UNUserNotificationCenter` "오늘 요약 완료", 실패 시 "요약 실패: {이유}". 권한은 첫 실행 때 요청.

### 10.3 에러 처리

| 상황 | 동작 |
|---|---|
| Jira 토큰 없음 | Jira 섹션에 설정 유도 버튼만 |
| Jira 401/403 | "토큰 확인" + 설정 열기 |
| Jira 400 (JQL 오류) | 에러 메시지 표시 + 설정 열기 |
| Jira 네트워크 실패 | 기존 목록 유지, 마지막 성공 시각 + 에러 한 줄 |
| 훅 경로 불일치 | 설정에 경고, "재설치" 버튼 |
| settings.json 파싱 실패 | 설치 중단, 에러 표시, 파일 손대지 않음 |
| claude 바이너리 없음 | 요약 탭 "claude CLI 없음. 설정에서 경로 지정" |
| claude 실패/타임아웃 | 파일 쓰지 않음. stderr 마지막 20줄 로그, 탭에 한 줄 |
| 기록 전무 | "오늘 기록 없음" 파일 생성 (catch-up 반복 방지) |
| todos.json 손상 | 백업 후 빈 목록 |
| activity.jsonl 깨진 줄 | 그 줄만 스킵 |

## 11. 빌드와 테스트

### 11.1 Package.swift

- `swift-tools-version: 5.9`, `platforms: [.macOS(.v14)]`, `swiftLanguageVersions: [.v5]`
- targets: `TaskWidgetCore` (library), `TaskWidget` (executableTarget, depends on Core), `TaskWidgetCoreTests` (testTarget)

### 11.2 Makefile

| 타깃 | 동작 |
|---|---|
| `make build` | `swift build` |
| `make test` | `swift test` |
| `make app` | `swift build -c release` → `build/TaskWidget.app/Contents/{MacOS/TaskWidget, Info.plist}` 조립, ad-hoc `codesign -s -` |
| `make install` | `build/TaskWidget.app` → `/Applications/` (기존 것 교체) |
| `make run` | `make app` 후 `open build/TaskWidget.app` |

설치 후 앱을 옮기면 훅 경로가 깨지므로 `/Applications`에 두는 것을 기본으로 한다.

### 11.3 테스트 (XCTest, Core만)

- `TodoStoreTests`: 임시 디렉터리 save → load 왕복, dueDate 유무, 손상 파일 백업.
- `DueBadgeTests`: nil / 지남 / 오늘 / 7일 이내 / 8일 이후 배지, 정렬(마감순, nil 뒤, 동률 createdAt).
- `ScheduleTests`: now가 설정 시각 전/후/정확히 같을 때.
- `JiraClientTests`: fixture 디코딩, statusCategory 정렬, 기본 JQL vs 커스텀 JQL 선택.
- `ActivityLogTests`: 훅 입력 JSON → 레코드(prompt/stop/무시 이벤트/DATA cwd 제외/빈 텍스트/자르기), 날짜 필터, 깨진 줄 스킵.
- `WorklogTests`: 헤더 파싱, 파일 없음, 헤더 없는 파일.
- `SummaryPromptTests`: 기록 전무 분기, worklog 있는 프로젝트의 activity 제외, 캡 적용, 섹션 생성.
- `ClaudeIntegrationTests`: fixture settings.json(다른 훅 있음)에 설치 → 다른 훅 보존, 두 번 설치해도 1개, 제거 후 원복, 경로 불일치 감지, 잘못된 JSON은 무변경.

UI, `ClaudeRunner`(실제 프로세스), 훅 실제 발화는 수동 확인. 수동 체크리스트는 구현 계획에 포함.

## 12. 결정 기록

- 레이아웃 C: 탭 2개(할 일 | 요약). 할 일 탭 안에 내 할 일 / Jira 두 섹션 (시안 검토 후 선택).
- Claude 연동은 트랜스크립트 파싱 대신 공식 훅 입력 + `/worklog` 스킬. 둘 다 사용. 일지가 1급, 훅 raw는 보완.
- 훅 명령은 앱 바이너리 자신(`--hook`). 외부 스크립트/jq 없음.
- 요약 출력 대상은 본인뿐이므로 공유/게시 기능 없음.
- Jira는 읽기 전용. 쓰기는 브라우저에서.
- 단일 앱 구조. launchd 대신 앱 내 타이머 + catch-up.
- Swift 6 strict concurrency는 끄고 Swift 5 모드.
- 외부 의존성 0. Markdown 렌더러도 줄 단위 간이 버전.
- 전역 단축키, 프롬프트 템플릿 편집은 제외 (설정 논의에서 미선택).
