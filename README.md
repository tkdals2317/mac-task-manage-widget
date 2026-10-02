# TaskWidget

macOS 메뉴바 상주 플로팅 위젯. 할 일(마감일) + 내 Jira 미완료 이슈 + Claude Code 세션 기반 하루 업무 요약.

## 설치

```bash
make install            # /Applications/TaskWidget.app (쓰기 불가면 ~/Applications)
open ~/Applications/TaskWidget.app   # 또는 /Applications
```

처음 한 번:

1. 메뉴바 체크리스트 아이콘 → 패널 → 기어(설정)
2. **Jira**: 이메일 + API 토큰 입력 → 저장 → 연결 테스트
3. **Claude 연동**: "활동 훅 설치", "/worklog 스킬 설치"
4. **일반**: 로그인 시 실행

## 사용

- 할 일: 입력 후 Enter. 📅/배지 클릭으로 마감 설정. 지난 마감 빨강, 오늘 주황. 제목 더블클릭 → 바로 수정 (Enter 저장, Esc 취소).
- Jira: 내게 할당된 미완료 이슈. 클릭하면 브라우저. 설정에서 JQL 교체 가능.
- 요약: 매일 설정 시각(기본 18:00)에 자동 생성. Claude Code 세션에서 `/worklog` 로 일지를 남기면 그게 1급 입력, 훅이 모은 대화 기록은 보완.
- 요약은 `claude -p` 로 생성 (Claude Code CLI 구독 사용).

## 데이터

`~/Library/Application Support/TaskWidget/`
- `todos.json`, `activity.jsonl`, `worklog/`, `summaries/`, `logs/`
- Jira 토큰은 Keychain (`com.lsm0506.TaskWidget.jira`)

## 개발

```bash
make build   # swift build
make test    # swift test (Core 단위 테스트)
make run     # build/TaskWidget.app 실행
```

앱을 옮기면 `~/.claude/settings.json` 의 훅 경로가 깨진다. 설정 > Claude 연동에서 "재설치".

설계: `docs/superpowers/specs/2026-10-02-task-widget-design.md`

## 수동 확인 체크리스트

하나씩 확인 후 체크.

- [ ] 메뉴바 아이콘만 있고 Dock 없음. 좌클릭 토글, 우클릭 메뉴 4개
- [ ] 패널이 Finder/브라우저/터미널 위에 떠 있음. 전체화면 앱 위에서도 보임 (allSpaces on)
- [ ] 할 일 추가/완료/삭제/마감/비우기, 재실행 후 유지
- [ ] 할 일 제목 더블클릭 → 인라인 편집, Enter 저장 / Esc 취소 / 다른 곳 클릭 시 저장, 공백만 입력하면 원래 제목 유지
- [ ] Jira 목록, 클릭 시 브라우저, ↻, 토큰 오류 메시지, JQL 커스텀
- [ ] 설정 각 항목 즉시 반영 (투명도, 호버, 테마, 글자 크기, 항상 위, Spaces)
- [ ] 훅 설치 후 Claude Code 세션 → activity.jsonl 증가. 요약 생성용 claude -p 세션은 기록 안 됨 (cwd = 데이터 폴더)
- [ ] `/worklog` 스킬 → worklog 파일 append → 요약 탭 즉시 표시
- [ ] 예정 시각 자동 생성 + 알림. 재실행/깨우기 catch-up. 수동 "다시 생성"
- [ ] 첫 실행 시 알림 권한 요청 (이미 요청됐을 수 있음 → 시스템 설정 > 알림 > TaskWidget 확인)
- [ ] 생성 시각을 과거로 바꾸고 오늘 파일이 없으면 ~3초 후 즉시 생성
- [ ] 오늘 파일이 있으면 시각을 바꿔도 재생성 안 함
- [ ] 최근 날짜의 summaries 파일 하나 지우고(그날 activity 있음) 재실행 → 그날 요약 자동 생성
- [ ] 메뉴바 우클릭 "요약 지금 생성" → 패널 표시 + 요약 탭 + 강제 재생성
- [ ] 요약 실패 시 "요약 실패: {이유}" 알림
- [ ] 잠자기 → 깨우기 (예정 시각 지남, 오늘 파일 없음) → 생성
- [ ] 기록 없는 날 → "오늘 기록 없음" 파일
- [ ] 로그인 시 실행 토글 → 시스템 설정 로그인 항목에 표시
- [ ] 설정 시트 텍스트 필드에서 ⌘V 붙여넣기 / ⌘A 모두 선택 동작. API 토큰 필드는 SecureField 라 한글 입력소스에서는 글자가 안 들어감 → ABC 로 전환해서 붙여넣기
- [ ] 앱 종료 후 재실행 시 패널 위치/크기/탭/섹션 접힘 유지

화면 확인이 필요해 자동 검증하지 못한 UI 항목:

- [ ] 메뉴바 아이콘 표시, 좌클릭 시 패널 토글
- [ ] 우클릭 메뉴 4개: 패널 토글, 요약 지금 생성, 설정…, 종료
- [ ] 할 일 입력, 마감 팝오버의 버튼(오늘/내일/다음 주 월/마감 없음), 달력 클릭 시 팝오버 유지
- [ ] Jira 목록 표시, 이슈 클릭 시 브라우저 열림
- [ ] 요약 탭: 날짜 이동, 복사, 생성
- [ ] 설정 시트에서 텍스트 필드 입력 가능
- [ ] 투명도/호버/테마/글자 크기 변경이 즉시 반영
- [ ] 닫기 버튼으로 숨긴 뒤 다시 표시해도 투명도 유지
- [ ] Claude Code 세션 하나 끝낸 뒤 `activity.jsonl`에 `"event":"prompt"` 와 `"event":"stop"` 줄이 둘 다 있음
- [ ] `make install` 후 첫 Jira 갱신 때 키체인 프롬프트가 뜨면 **항상 허용** 선택 (허용만 누르면 매 갱신마다 다시 뜸)
