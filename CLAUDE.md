# CLAUDE.md

ATM (SwiftPM macOS 앱). 설치·빌드 시 AI 에이전트가 지킬 규칙.

## 설치 순서

1. 저장소를 클론한다 (요청받은 위치에만).
2. `make doctor` 를 실행한다.
3. ❌ 가 있으면 사용자에게 정확히 `sudo ./scripts/fix-clt.sh` 한 줄만 실행해 달라고 요청한다 (한 번이면 충분). 그 뒤 `make doctor` 를 다시 돌린다.
4. `make install`
5. `open ~/Applications/ATM.app`

## 규칙

- 기능/버그 수정 PR 은 반드시 `VERSION` 을 올리고 `CHANGELOG.md` 에 항목을 추가한다.
- 관련 없는 디렉터리를 만들지 않는다.
- `/Library/Developer` 아래 파일을 직접 고치거나 지우지 않는다. 반드시 `scripts/fix-clt.sh` 를 쓴다.
- `~/.claude/settings.json` 을 직접 수정하지 않는다. 앱의 설정 > Claude 연동이 백업과 함께 처리한다.
- sudo 명령은 짧은 한 줄로 안내한다 (긴 명령은 붙여넣기에서 깨진다).
- 설치 후 사용자에게 알린다: Jira 첫 로드 시 키체인 창에서 **항상 허용**을 누를 것, 설정 > Jira 의 "토큰 발급 ↗" 링크로 API 토큰을 만들 것.
- Teleport 비밀번호·OTP 키는 채팅에 붙여넣어 달라고 절대 요청하지 않는다. 사용자가 앱(Teleport 탭 설정)에 직접 입력한다.
