README 스크린샷용 데모 모드. 가짜 데이터로 앱을 띄우며 실제 데이터·설정·키체인·네트워크는 쓰지 않는다.
`make app` 으로 `build/ATM.app` 을 만든 뒤 `scripts/screenshot-demo.sh [데이터 폴더]` 를 실행한다 (기본 `$TMPDIR/atm-demo-data`).
`data/` 는 데이터 폴더(`ATM_DATA_DIR`)로, `fixtures/` 는 Jira·PR·Confluence 응답(`ATM_DEMO_FIXTURES`)으로 쓰인다. 잠긴 메모 비밀번호는 `demo1234`.
