#!/bin/bash
# 테스트용 가짜 aside. E2ERunner 가 실행용 폴더(workDir)를 작업 폴더로 띄우므로 $PWD 가 실행용 폴더다.
# FAKE_ASIDE_MODE: success | junk | fail-login | invalid | empty | hang | stubborn
# FAKE_DELAY: 시작 후 기다릴 초, FAKE_ORDER_FILE: 시작·끝을 적을 파일 (대기열 순서 확인용)
id=$(basename "$PWD")
[ -n "$FAKE_ORDER_FILE" ] && echo "start $id" >> "$FAKE_ORDER_FILE"
echo "created new session: fake-$id" >&2

# ATM 이 요청 파일을 실행용 폴더에 두었는지
[ -f request.json ] || { echo "Error: request.json 없음" >&2; exit 1; }
sleep "${FAKE_DELAY:-0}"

write_result() {
  printf 'png' > ABC-1-1.png
  cat > result.json <<'JSON'
{"status":"done","summary":"가짜 실행","issues":[{"key":"ABC-1","title":"t","url":"file:///Applications/Calculator.app","verdict":"PASS",
"scenarios":[{"name":"s","steps":["a"],"expected":"e","actual":"a","verdict":"PASS","screenshots":["ABC-1-1.png","ABC-1-2.png","run.sh"]}]}]}
JSON
}

case "${FAKE_ASIDE_MODE:-success}" in
  success) write_result; echo "ABC-1 PASS" ;;
  # 결과와 함께 이미지가 아닌 파일·링크·숨김 파일을 남긴다 (가져오면 안 되는 것들)
  junk) write_result; printf '#!/bin/sh\necho hi\n' > run.sh; chmod +x run.sh; ln -s /etc/hosts ABC-1-2.png; printf 'x' > .hidden.png ;;
  fail-login) echo "Error: Not signed in. Run aside login to continue." >&2; exit 1 ;;
  invalid) printf '{' > result.json ;;
  empty) printf '{"issues":[]}' > result.json ;;
  hang) sleep 6123 ;;
  stubborn) trap '' TERM; while true; do sleep 1; done ;;
esac
[ -n "$FAKE_ORDER_FILE" ] && echo "end $id" >> "$FAKE_ORDER_FILE"
exit 0
