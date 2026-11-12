# ATM — Windows 판

Mac 판 ATM 과 같은 떠 있는 패널을 Windows 에서 쓰는 버전이에요. Tauri 2 로 만들었어요.

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | 패널·트레이·단축키·설정, 할 일 탭, 노트 탭 | ✅ 0.1.1 |
| 2 | 요약 / 업무 일지, Claude 연동 (활동 훅·/worklog·atm-todo) | ✅ 0.2.0 |
| 3 | PR 탭 (GitHub·Bitbucket) | ✅ 0.2.0 |
| 4 | Teleport 탭 | ✅ 0.2.0 |
| - | 설정 도우미, 진단 정보 내보내기, 비밀 정보 저장 위치 | ✅ 0.2.0 |

## 설치

1. [Releases](https://github.com/tkdals2317/mac-task-manage-widget/releases) 에서 `Windows v…` 릴리스의 `ATM_<버전>_x64-setup.exe` 를 받아 실행해요.
   - 서명하지 않은 설치 파일이라 처음엔 SmartScreen 경고가 떠요. **추가 정보 → 실행** 을 누르세요.
   - 관리자 권한 없이 내 계정에만 설치돼요.
2. 설치가 끝나면 작업 표시줄 오른쪽 트레이에 ATM 아이콘이 생기고, 처음 실행하면 **설정 도우미**가 열려요. 쓸 기능(Jira·노트·요약·PR·Teleport)을 고르면 필요한 설정만 차례로 안내해요.
3. 도우미는 설정 > 정보 > **설정 도우미 열기** 로 언제든 다시 열 수 있어요.

## 쓰는 법

- **열고 닫기:** 트레이 아이콘 왼쪽 클릭, 또는 전역 단축키 `Ctrl + Alt + Q` (설정 > 창 · 일반 에서 바꿀 수 있어요).
- **빨간 버튼·Esc:** 끄지 않고 트레이로 숨겨요. 완전히 끄려면 트레이 아이콘 오른쪽 클릭 → **종료**.
- **노란 버튼:** 작업 표시줄로 최소화해요 (Mac 의 Dock 최소화). 작업 표시줄·트레이·단축키로 다시 열어요.
- **패널 옮기기:** 맨 위 빈 줄을 끌어요. 가장자리를 끌면 크기가 바뀌어요. `Ctrl + 1~5` 로 탭을 바꿔요.
- 화면과 기능은 Mac 판과 같아요. 자세한 설명은 [사용 설명서](../README.md#사용-설명서) 를 보세요. Windows 에서 다른 점:
  - Touch ID 대신 **Windows Hello**(지문·얼굴·PIN)로 잠긴 메모를 열어요. 설정 > 노트 에서 켜요.
  - 키체인 대신 **Windows 자격 증명 관리자**에 비밀값을 둬요 (설정 > 창 · 일반 > 비밀 정보 저장 에서 파일로 바꿀 수 있어요).
  - 요약은 `claude` CLI 를 PATH, `%USERPROFILE%\.local\bin`, npm 전역 폴더, Claude 데스크톱 앱이 받아 둔 Claude Code 순서로 찾아요. 로그인이 필요해요 (`claude` 실행 → `/login`).
  - PR 의 GitHub 는 `gh` CLI 로그인(`winget install GitHub.cli` → `gh auth login`)을 써요.
  - Teleport 는 `tsh` 가 PATH 에 있거나 설정 > Teleport 에 경로를 넣어야 해요. 로그인은 가상 콘솔(ConPTY)에서 비밀번호·OTP 를 대신 입력해요. OTP QR 이미지는 파일을 골라서 읽어요.
  - 요약 자동 생성·PR 알림·Teleport 자동 유지는 ATM 이 켜져 있는 동안(트레이에 숨겨도) 돌아가요.

## Claude Code 연동

설정 > Claude 연동에서 설치해요. `~/.claude/settings.json` 은 바꾸기 전에 `settings.json.bak-<시각>` 로 백업해요.

- **활동 훅:** Claude Code 의 프롬프트·응답을 `atm.exe --hook` 이 `activity.jsonl` 에 남겨 요약 재료로 써요.
- **/worklog 스킬:** 세션에서 한 일을 `worklog\YYYY-MM-DD.md` 에 남겨요.
- **atm-todo 스킬:** "이거 할 일에 추가해줘, 금요일까지" 처럼 말하면 `atm.exe --add-todo --title "…" [--due YYYY-MM-DD] [--tag 이름] [--memo "…"] [--sub "…"]` 로 할 일이 들어가요. 앱이 꺼져 있으면 다음 실행 때 반영돼요.
- 훅·스킬에는 설치 위치가 들어가요. ATM 을 다른 곳에 다시 설치하면 다시 설치해 주세요.

## 업데이트

새 버전이 나오면 패널 맨 위에 **새 버전 x.y.z** 버튼이 떠요. 누르면 릴리스 페이지가 열리고, 새 설치 파일을 받아 실행하면 덮어써서 업데이트돼요 (데이터는 그대로).

## 데이터

- 데이터 폴더: `%APPDATA%\TaskWidget` (`todos.json`, `notes.json`, `tags.json`, `settings.json`, `teleport.json`, `activity.jsonl`, `summaries\`, `worklog\`, `logs\`). 파일 형식은 Mac 판과 같아요.
- 문제가 생기면 설정 > 정보 > **진단 정보 내보내기** 로 바탕 화면에 만든 `ATM-진단-*.zip` 을 보내 주세요 (비밀번호·OTP·토큰은 들어가지 않아요). 로그: `logs\app.log`, `teleport-login.log`, `teleport-<DB>.log`, `summary-*.log`.

## 개발자용

필요한 것: Node 20, Rust(stable), Windows 에서는 [Tauri 준비물](https://v2.tauri.app/start/prerequisites/)(WebView2, MSVC 빌드 도구).

```bash
cd windows
npm ci
npm run check   # 타입 검사
npm test        # 로직 테스트
npx tauri dev   # 개발 실행
npx tauri build --bundles nsis   # 설치 파일
```

- 개발 실행(`tauri dev`)은 설치한 앱을 건드리지 않게 데이터 폴더로 `%APPDATA%\TaskWidget-dev` 를 쓰고(Mac 에서는 `~/Library/Application Support/TaskWidget-win-dev`), Windows 시작 프로그램에 등록하지 않아요.
- 폴더 경로가 길면(260자 근처) 링크가 실패할 수 있어요. `CARGO_TARGET_DIR` 을 짧은 경로로 두세요. 1420 포트를 다른 앱이 쓰면 `npx tauri dev --config '{"build":{"devUrl":"http://localhost:1430","beforeDevCommand":"npm run dev -- --port 1430"}}'`.
- PR 마다 GitHub Actions(`windows.yml`)가 Windows 에서 검사·테스트·설치 파일 빌드를 해요. 결과 설치 파일은 실행 결과의 Artifacts 에서 받을 수 있어요.
- 버전을 올릴 때는 `package.json` 의 `version` 과 `CHANGELOG.md` 를 같이 고쳐요. main 에 들어가면 `windows-v<버전>` 릴리스가 자동으로 만들어져요.
- 구조: `src-tauri/`(Rust: 창·트레이·파일·비밀값·Windows Hello·외부 프로그램·tsh 로그인·`--hook`/`--add-todo`), `src/lib/`(데이터·Jira·노트·요약·PR·Teleport 로직, `*Core.ts` 는 테스트하는 순수 함수), `src/tabs/`·`src/tasks/`·`src/notes/`·`src/pr/`·`src/teleport/`·`src/settings/`(화면).
