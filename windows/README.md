# ATM — Windows 판

Mac 판 ATM 과 같은 떠 있는 패널을 Windows 에서 쓰는 버전이에요. Tauri 2 로 만들었어요.

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | 패널·트레이·단축키·설정, 할 일 탭, 노트 탭 | ✅ 0.1.0 |
| 2 | 요약 / 업무 일지, Claude 연동 | 예정 |
| 3 | PR 탭 | 예정 |
| 4 | Teleport 탭 | 예정 |

## 설치

1. [Releases](https://github.com/tkdals2317/mac-task-manage-widget/releases) 에서 `Windows v…` 릴리스의 `ATM_<버전>_x64-setup.exe` 를 받아 실행해요.
   - 서명하지 않은 설치 파일이라 처음엔 SmartScreen 경고가 떠요. **추가 정보 → 실행** 을 누르세요.
   - 관리자 권한 없이 내 계정에만 설치돼요.
2. 설치가 끝나면 작업 표시줄 오른쪽 트레이에 ATM 아이콘이 생겨요. 처음 실행하면 설정 창의 Jira 화면이 열려요.
3. 설정 > Jira 에서 사이트 주소·이메일을 넣고 **토큰 발급 ↗** 으로 만든 API 토큰을 붙여 넣은 뒤 저장해요.

## 쓰는 법

- **열고 닫기:** 트레이 아이콘 왼쪽 클릭, 또는 전역 단축키 `Ctrl + Alt + Space` (설정 > 창 에서 바꿀 수 있어요).
- **✕ 버튼·Esc:** 끄지 않고 트레이로 숨겨요. 완전히 끄려면 트레이 아이콘 오른쪽 클릭 → **종료**.
- **패널 옮기기:** 맨 위 빈 줄을 끌어요. 가장자리를 끌면 크기가 바뀌어요.
- 할 일·노트·설정 화면은 Mac 판과 같아요. 자세한 설명은 [사용 설명서](../README.md#사용-설명서) 를 보세요.
  - Touch ID 대신 **Windows Hello**(지문·얼굴·PIN)로 잠긴 메모를 열어요. 설정 > 노트 에서 켜요.

## 업데이트

새 버전이 나오면 패널 맨 위에 **새 버전 x.y.z** 버튼이 떠요. 누르면 릴리스 페이지가 열리고, 새 설치 파일을 받아 실행하면 덮어써서 업데이트돼요 (데이터는 그대로).

## 데이터

- 데이터 폴더: `%APPDATA%\TaskWidget` (`todos.json`, `notes.json`, `tags.json`, `settings.json`, `logs\app.log`). 파일 형식은 Mac 판과 같아요.
- Jira 토큰·노트 열쇠는 **Windows 자격 증명 관리자** 에 저장돼요.
- 문제가 생기면 `%APPDATA%\TaskWidget\logs\app.log` 를 같이 보내 주세요.

## 개발자용

필요한 것: Node 20, Rust(stable), Windows 에서는 [Tauri 준비물](https://v2.tauri.app/start/prerequisites/)(WebView2, MSVC 빌드 도구).

```bash
cd windows
npm ci
npm run check   # 타입 검사
npm test        # 로직 테스트
npx tauri dev   # 개발 실행 (Mac 에서도 돌아가요. 데이터는 ~/Library/Application Support/TaskWidget-win-dev)
npx tauri build --bundles nsis   # 설치 파일
```

- PR 마다 GitHub Actions(`windows.yml`)가 Windows 에서 검사·테스트·설치 파일 빌드를 해요. 결과 설치 파일은 실행 결과의 Artifacts 에서 받을 수 있어요.
- 버전을 올릴 때는 `package.json` 의 `version` 과 `CHANGELOG.md` 를 같이 고쳐요. main 에 들어가면 `windows-v<버전>` 릴리스가 자동으로 만들어져요.
- 구조: `src-tauri/`(Rust: 창·트레이·파일·비밀값·Windows Hello), `src/lib/`(데이터·Jira·노트 로직), `src/tasks/`·`src/notes/`·`src/settings/`(화면).
