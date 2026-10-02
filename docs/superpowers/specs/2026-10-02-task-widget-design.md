# TaskWidget 설계 문서

작성일: 2026-10-02
상태: 승인됨 (구현 전)

## 1. 목적

macOS에서 다른 창 위에 항상 떠 있는 작은 할 일 위젯. 세 가지를 한 화면에서 본다.

1. 일반 할 일 (로컬 저장)
2. 내게 할당된 Jira 미완료 이슈 (읽기 전용)
3. 오늘 Claude Code 세션 기록을 기반으로 자동 생성한 "오늘 한 일" 요약

사용자는 한 명(본인). 서버, 동기화, 멀티 디바이스 없음. 요약은 개인 기록용이며 외부 게시 없음.

## 2. 범위

### 포함

- 메뉴바 상주 앱, 플로팅 패널 토글
- Todo CRUD (추가, 완료 토글, 삭제, 완료 항목 일괄 정리)
- Jira 미완료 이슈 목록 조회, 상태별 그룹, 클릭 시 브라우저로 열기
- 지정 시각에 하루 요약 자동 생성, 수동 생성/재생성, 날짜별 열람, 복사
- 설정: Jira URL/이메일/토큰(Keychain), 요약 시각, claude 모델(선택), 로그인 시 실행

### 제외 (필요해지면 추가)

- 전역 단축키
- Jira 상태 전이, 이슈 생성, 코멘트
- 여러 날 묶음 요약, 주간 요약
- Slack/Confluence 게시
- iCloud/서버 동기화

## 3. 기술 결정

| 항목 | 결정 | 이유 |
|---|---|---|
| 언어/UI | Swift 5 language mode, SwiftUI + AppKit(NSPanel) | 항상-위 창을 NSPanel 설정 몇 줄로 해결. 설치 의존성 없음 |
| 빌드 | SwiftPM (Xcode 프로젝트 없음) | 파일 적고 CLI로 빌드/테스트 가능 |
| 배포 타깃 | macOS 14 | 현재 머신 macOS 26, SDK 15.2 |
| 요약 생성 | `claude -p` CLI 호출 | API 키 불필요, 기존 구독 사용 |
| Jira 호출 | URLSession + Basic Auth | 의존성 없음 |
| 토큰 저장 | Keychain (Security framework) | 평문 파일 금지. `~/.claude/credentials.md`는 읽지 않음 |
| 스케줄 | 앱 내부 Timer + 런치/웨이크 시 catch-up | 메뉴바 상주 앱이므로 launchd 불필요 |
| 외부 패키지 | 없음 | 전부 Foundation/AppKit/SwiftUI로 가능 |

## 4. 구조

```
task-manager/
  Package.swift
  Makefile                       # build / app / install / test
  Resources/Info.plist           # LSUIElement=true, CFBundleIdentifier
  Sources/
    TaskWidgetCore/              # 라이브러리. UI 없음. 전부 테스트 대상
      Models.swift               # Todo, JiraIssue, Summary
      TodoStore.swift            # JSON 파일 로드/저장
      Settings.swift             # UserDefaults 래퍼
      Keychain.swift             # Jira 토큰 get/set/delete
      JiraClient.swift           # search/jql 호출, 디코딩
      TranscriptExtractor.swift  # ~/.claude/projects jsonl -> 오늘 메시지
      GitActivity.swift          # 프로젝트별 오늘 커밋
      SummaryPrompt.swift        # 프롬프트 조립
      ClaudeRunner.swift         # claude -p 프로세스 실행
      SummaryService.swift       # 추출 -> 프롬프트 -> 실행 -> 파일 저장
      Schedule.swift             # nextFireDate 순수 함수
    TaskWidget/                  # 실행 파일. AppKit + SwiftUI
      main.swift
      AppDelegate.swift          # 상태바 아이템, 패널 생성, 스케줄러 소유
      FloatingPanel.swift        # NSPanel 서브클래스
      Scheduler.swift            # Timer + wake 알림 -> SummaryService
      Views/
        RootView.swift           # 탭 컨테이너
        TodoView.swift
        JiraView.swift
        SummaryView.swift
        SettingsView.swift
        MarkdownText.swift       # 줄 단위 간이 렌더러
  Tests/TaskWidgetCoreTests/
    Fixtures/sample-session.jsonl
    TranscriptExtractorTests.swift
    ScheduleTests.swift
    JiraClientTests.swift
    TodoStoreTests.swift
    SummaryPromptTests.swift
  docs/superpowers/specs/
```

Core는 AppKit/SwiftUI를 import하지 않는다. 실행 파일은 Core를 조립만 한다.

### 데이터 디렉터리

`~/Library/Application Support/TaskWidget/`

```
todos.json
summaries/YYYY-MM-DD.md
logs/summary-YYYY-MM-DD.log     # claude stderr, 추출 통계
```

## 5. Shell (창, 메뉴바)

- `Info.plist`에 `LSUIElement = true`. Dock 아이콘 없음.
- `NSStatusItem` 하나. 아이콘 클릭 → 패널 show/hide 토글. 우클릭 메뉴: 요약 지금 생성, 설정, 종료.
- `FloatingPanel: NSPanel`
  - `styleMask = [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView]`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`
  - `level = .floating`
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`
  - `hidesOnDeactivate = false`, `isMovableByWindowBackground = true`
  - `setFrameAutosaveName("TaskWidgetPanel")`, 기본 크기 320×480, 최소 280×320
  - 닫기 버튼은 hide로 동작 (앱 종료 아님)
- 패널 내용: `NSHostingView(rootView: RootView(...))`
- `RootView`: 상단 세그먼트 **Todo | Jira | 요약**, 우측 상단 기어 → 설정 시트. 마지막 선택 탭은 UserDefaults에 기억.

## 6. Data

### 6.1 Todo

```swift
struct Todo: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var done: Bool
    var createdAt: Date
    var completedAt: Date?
}
```

- `TodoStore`: `load()`, `save([Todo])`. 파일 `todos.json`, 배열 JSON, ISO8601 날짜. 쓰기는 임시 파일 후 `replaceItemAt`로 원자적 교체. 파일 없으면 빈 배열. 파싱 실패 시 `.corrupt-<timestamp>`로 이름 바꾸고 빈 배열로 시작(데이터 유실 방지).
- UI: 상단 텍스트 필드, Enter로 추가(공백만이면 무시). 체크박스로 done 토글(`completedAt` 기록/해제). 행 hover 시 × 삭제. 미완료는 `createdAt` 오름차순. 완료는 접힌 "완료 (n)" 섹션, "비우기" 버튼으로 전부 삭제.
- 변경 즉시 저장.

### 6.2 Jira

```swift
struct JiraIssue: Codable, Identifiable, Equatable {
    var id: String          // key, e.g. NMRS-12345
    var summary: String
    var status: String      // fields.status.name
    var statusCategory: String // fields.status.statusCategory.key: new|indeterminate|done
    var priority: String?   // fields.priority.name
    var updated: Date
}
```

- 요청: `GET {baseURL}/rest/api/3/search/jql`
  - query: `jql=assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`, `fields=summary,status,priority,updated`, `maxResults=100`
  - 헤더: `Authorization: Basic base64(email:token)`, `Accept: application/json`
  - 100건 초과는 무시(한 페이지만). 초과 시 목록 하단에 "100건까지만 표시".
- `JiraClient.fetchMyOpenIssues() async throws -> [JiraIssue]`. 401/403 → `JiraError.unauthorized`, 그 외 non-2xx → `JiraError.http(status)`, 네트워크 → `JiraError.network(Error)`.
- 디코딩은 `Decodable` 응답 구조체로. `updated`는 Jira 포맷 `yyyy-MM-dd'T'HH:mm:ss.SSSZ` 파서 사용.
- UI: `statusCategory` 순서 `indeterminate`(진행 중) → `new`(할 일) → 나머지. 그룹 헤더 = 상태 이름. 행: `KEY` 모노스페이스 + summary 한 줄 생략. 클릭 → `NSWorkspace.shared.open({baseURL}/browse/{key})`.
- 갱신: 패널이 보일 때 5분마다, Jira 탭 진입 시, 수동 ↻ 버튼. 마지막 성공 시각 하단 표시. 실패 시 기존 목록 유지 + 에러 한 줄. 토큰 미설정이면 "설정에서 Jira 토큰 입력" 버튼만 표시.

### 6.3 Settings

`UserDefaults` 키:

| 키 | 타입 | 기본값 |
|---|---|---|
| `jiraBaseURL` | String | `https://midasitweb-jira.atlassian.net` |
| `jiraEmail` | String | `""` |
| `summaryHour` | Int | 18 |
| `summaryMinute` | Int | 0 |
| `claudeModel` | String | `""` (빈 값 = CLI 기본) |
| `claudePath` | String | `""` (빈 값 = 자동 탐색) |
| `lastTab` | String | `todo` |

Jira 토큰: Keychain generic password, service `com.lsm0506.TaskWidget.jira`, account = `jiraEmail`. 설정 화면의 토큰 필드는 `SecureField`, 저장 시 Keychain에 쓰고 UserDefaults에는 절대 쓰지 않음. "연결 테스트" 버튼 → `/rest/api/3/myself` 호출해 displayName 표시.

claude 바이너리 탐색 순서: `claudePath` 설정값 → `~/.local/bin/claude` → `/opt/homebrew/bin/claude` → `/usr/local/bin/claude`. 모두 없으면 `SummaryError.claudeNotFound`.

로그인 시 실행: `SMAppService.mainApp.register()/unregister()`. 토글 상태는 `SMAppService.mainApp.status`에서 읽음.

## 7. 요약 파이프라인

`SummaryService.generate(for date: Date, force: Bool) async throws -> Summary`

순서: 추출 → git 활동 → 프롬프트 조립 → claude 실행 → 저장. 동시에 하나만 실행(actor 또는 플래그). `force == false`이고 해당 날짜 파일이 있으면 기존 것을 반환.

### 7.1 TranscriptExtractor

입력: 날짜(로컬 캘린더), 루트 `~/.claude/projects`.

```swift
struct Message { let timestamp: Date; let project: String; let cwd: String; let role: Role; let text: String }
func extract(day: Date, root: URL, excludingCwdPrefix: String) throws -> [Message]
```

규칙:

1. `root/*/*.jsonl` 중 mtime ≥ 그날 00:00 로컬인 파일만 연다(이전 날 파일 스킵으로 I/O 절약).
2. 줄 단위 스트리밍 파싱. JSON 실패 줄은 건너뜀.
3. 유지하는 줄:
   - `type == "user"`:
     - `isSidechain == true` 스킵
     - `message.content`가 문자열이면 그대로. 배열이면 `type == "text"` 블록의 `text`를 `\n`으로 결합. 텍스트 블록이 없으면(tool_result만) 스킵
   - `type == "assistant"`: `message.content[]` 중 `type == "text"`만 결합. `thinking`, `tool_use` 스킵. 텍스트 없으면 스킵
   - 그 외 `type` 전부 스킵
4. `timestamp`(ISO8601, UTC) → 로컬 날짜가 `day`와 같아야 함.
5. `cwd`가 `excludingCwdPrefix`(앱 데이터 디렉터리)로 시작하면 스킵(요약 생성 세션 자체가 내일 입력이 되는 것 방지).
6. 텍스트 정리:
   - `<system-reminder>...</system-reminder>` 구간 제거 (여러 줄, 비탐욕)
   - `<command-name>`, `<command-message>`, `<local-command-stdout>`로 시작하는 메시지 스킵
   - 앞뒤 공백 제거 후 빈 문자열이면 스킵
   - 600자 초과 시 앞 600자 + `…`
7. `project` = `cwd`의 마지막 경로 요소.
8. 정렬: timestamp 오름차순.
9. 총량 제한: 전체 텍스트 합이 60,000자를 넘으면 가장 오래된 메시지부터 제거.

통계(파일 수, 유지 메시지 수, 제거 메시지 수, 프로젝트 목록)는 로그 파일에 기록.

### 7.2 GitActivity

추출된 메시지의 고유 `cwd` 각각에 대해:

- `git -C <cwd> rev-parse --is-inside-work-tree` 성공 시
- `git -C <cwd> log --since=<day 00:00 로컬> --until=<day 23:59:59 로컬> --format=%h %s` 최대 30줄
- 실패/비-git 디렉터리는 무시. 각 호출 10초 타임아웃.

### 7.3 SummaryPrompt

```
당신은 개발자의 하루 업무 일지를 작성합니다. 아래는 {YYYY-MM-DD}에 Claude Code에서 나눈 대화 기록과 git 커밋입니다.
도구를 사용하지 말고, 아래 데이터만 근거로 한국어 Markdown을 출력하세요. 다른 설명 없이 Markdown만 출력합니다.

형식:
# {YYYY-MM-DD} 업무 요약
## {프로젝트명}
- 한 일 (성과/결과 위주, 3~7개, 각 1~2문장)
(프로젝트마다 반복)
## 미완료 / 내일
- 대화에서 드러난 미완료 작업이나 다음 단계

데이터:
=== 프로젝트: {project} ({cwd}) ===
[커밋]
abc1234 feat: ...
[대화]
[HH:mm] user: ...
[HH:mm] assistant: ...
```

메시지가 0건이고 커밋도 0건이면 claude를 호출하지 않고 `# {date} 업무 요약\n\n오늘 기록 없음` 파일을 쓴다.

### 7.4 ClaudeRunner

```swift
func run(prompt: String, model: String?, timeout: TimeInterval = 180) async throws -> String
```

- `Process` 실행: `<claudePath> -p --output-format text [--model <model>]`
- 프롬프트는 stdin으로 전달(인자 길이 제한 회피).
- `currentDirectoryURL` = 앱 데이터 디렉터리.
- 환경: 현재 환경 복사 후 `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` 제거. `PATH`에 `~/.local/bin:/opt/homebrew/bin:/usr/local/bin` 앞에 추가.
- stdout 전체를 결과로. 타임아웃 시 `terminate()` 후 `SummaryError.timeout`. exit code ≠ 0 → `SummaryError.claudeFailed(code, stderrTail)`.
- stdout이 비어 있으면 `SummaryError.emptyOutput`.

### 7.5 저장과 표시

- `summaries/YYYY-MM-DD.md`에 원자적 쓰기. `Summary { date, markdown, generatedAt }`. `generatedAt`은 파일 mtime.
- `SummaryView`:
  - 상단 `◀ 2026-10-02 ▶`. 어느 날짜든 이동 가능. 파일 없으면 "요약 없음" + "생성" 버튼.
  - 본문 `MarkdownText`: 줄 단위. `# ` → 제목, `## ` → 소제목(bold), `- ` → 불릿, 나머지 본문. 인라인 강조는 `AttributedString(markdown:)`로 처리.
  - 하단: 생성 시각, "복사"(전체 markdown → pasteboard), "다시 생성"(force).
  - 생성 중 스피너 + 취소 불가(180초 상한). 실패 시 에러 메시지와 로그 파일 열기 버튼.

## 8. 스케줄과 에러

### 8.1 Schedule (순수 함수)

```swift
func nextFireDate(after now: Date, hour: Int, minute: Int, calendar: Calendar) -> Date
```

오늘 `hour:minute`가 `now`보다 뒤면 오늘, 아니면 내일. 테스트 대상.

### 8.2 Scheduler (앱)

- 시작 시 `Timer`를 `nextFireDate`에 맞춰 등록. 설정에서 시각이 바뀌면 재등록.
- 발화 시: 오늘 파일 없으면 `generate(today, force: false)`. 끝나면 다음 날로 재등록.
- catch-up: 앱 시작 시, `NSWorkspace.didWakeNotification` 수신 시, 설정 시각 변경 시 → `now ≥ 오늘 설정 시각`이고 오늘 파일이 없으면 즉시 생성.
- 완료 시 `UNUserNotificationCenter`로 "오늘 요약 완료" 알림. 실패 시 "요약 실패: {이유}". 권한은 첫 실행 때 요청.

### 8.3 에러 처리 요약

| 상황 | 동작 |
|---|---|
| Jira 토큰 없음 | Jira 탭에 설정 유도 버튼만 |
| Jira 401/403 | "토큰 확인" + 설정 열기 |
| Jira 네트워크 실패 | 기존 목록 유지, 마지막 성공 시각 + 에러 한 줄 |
| claude 바이너리 없음 | 요약 탭에 "claude CLI 없음. 설정에서 경로 지정" |
| claude 실패/타임아웃 | 파일 쓰지 않음. stderr 마지막 20줄을 로그에, 탭에 요약 메시지 |
| 오늘 기록 없음 | "오늘 기록 없음" 파일 생성(다음 catch-up이 반복 호출하지 않도록) |
| todos.json 손상 | 백업 후 빈 목록 |

## 9. 빌드와 테스트

### 9.1 Package.swift

- `swift-tools-version: 5.9`, `platforms: [.macOS(.v14)]`, `swiftLanguageVersions: [.v5]`
- targets: `TaskWidgetCore` (library), `TaskWidget` (executableTarget, depends on Core), `TaskWidgetCoreTests` (testTarget)

### 9.2 Makefile

| 타깃 | 동작 |
|---|---|
| `make build` | `swift build` |
| `make test` | `swift test` |
| `make app` | `swift build -c release` → `build/TaskWidget.app/Contents/{MacOS/TaskWidget, Info.plist, Resources}` 조립. ad-hoc `codesign -s -` |
| `make install` | `build/TaskWidget.app` → `/Applications/` 복사(기존 것 교체) |
| `make run` | `make app` 후 `open build/TaskWidget.app` |

### 9.3 테스트 (XCTest, Core만)

- `TranscriptExtractorTests`: fixture jsonl(오늘/어제 섞임, sidechain, tool_result만 있는 user, system-reminder 포함, 긴 메시지)로 유지/제거/절단/정렬/총량 제한 검증. 날짜는 고정값 주입.
- `ScheduleTests`: now가 설정 시각 전/후/정확히 같을 때.
- `JiraClientTests`: 고정 JSON 응답 디코딩, statusCategory 정렬.
- `TodoStoreTests`: 임시 디렉터리에서 save → load 왕복, 손상 파일 백업.
- `SummaryPromptTests`: 메시지 0건 분기, 프로젝트 섹션 생성.

UI와 `ClaudeRunner`(실제 프로세스)는 수동 확인. 수동 체크리스트는 구현 계획에 포함.

## 10. 결정 기록

- 요약 출력 대상은 본인뿐이므로 공유/게시 기능 없음.
- Jira는 읽기 전용. 쓰기는 브라우저에서.
- 단일 앱 구조. launchd 대신 앱 내 타이머 + catch-up.
- Swift 6 strict concurrency는 끄고 Swift 5 모드로 빌드(작은 앱에서 비용 대비 이득 없음).
- 외부 의존성 0. Markdown 렌더러도 직접 작성한 줄 단위 간이 버전.
