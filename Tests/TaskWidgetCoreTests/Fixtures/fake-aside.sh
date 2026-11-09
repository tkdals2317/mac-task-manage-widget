#!/bin/bash
# 테스트용 가짜 aside. E2ERunner 가 job 폴더를 작업 폴더로 띄우므로 $PWD 가 job 폴더다.
# FAKE_ASIDE_MODE: success | leak | fail-login | invalid | empty | hang | stubborn
# FAKE_DELAY: 시작 후 기다릴 초, FAKE_ORDER_FILE: 시작·끝을 적을 파일 (대기열 순서 확인용)
id=$(basename "$PWD")
[ -n "$FAKE_ORDER_FILE" ] && echo "start $id" >> "$FAKE_ORDER_FILE"
echo "created new session: fake-$id" >&2

if grep -q '"password"' job.json; then echo present > saw-password.txt; else echo absent > saw-password.txt; fi
sleep "${FAKE_DELAY:-0}"

write_result() {
  printf 'png' > ABC-1-1.png
  cat > result.json <<'JSON'
{"status":"done","summary":"가짜 실행","issues":[{"key":"ABC-1","title":"t","url":"u","verdict":"PASS",
"scenarios":[{"name":"s","steps":["a"],"expected":"e","actual":"a","verdict":"PASS","screenshots":["ABC-1-1.png"]}]}]}
JSON
}

case "${FAKE_ASIDE_MODE:-success}" in
  success) write_result; echo "ABC-1 PASS" ;;
  leak) write_result; grep -o '"password"[^,}]*' job.json ;;
  fail-login) echo "Error: Not signed in. Run aside login to continue." >&2; exit 1 ;;
  invalid) printf '{' > result.json ;;
  empty) printf '{"issues":[]}' > result.json ;;
  hang) sleep 6123 ;;
  stubborn) trap '' TERM; while true; do sleep 1; done ;;
esac
[ -n "$FAKE_ORDER_FILE" ] && echo "end $id" >> "$FAKE_ORDER_FILE"
exit 0
