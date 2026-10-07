#!/bin/sh
# 설치 전 점검. ❌ 가 하나라도 있으면 exit 1.
# 테스트용 환경변수: CLT_ROOT, DOCTOR_SKIP_XCODE_SELECT=1, DOCTOR_ONLY_CLT=1
HERE=$(cd "$(dirname "$0")" && pwd)
CLT_ROOT="${CLT_ROOT:-/Library/Developer/CommandLineTools}"
export CLT_ROOT
fail=0
ok()   { echo "✅ $1"; }
warn() { echo "⚠️  $1"; }
bad()  { echo "❌ $1"; fail=1; }

if [ -z "$DOCTOR_ONLY_CLT" ]; then
  v=$(sw_vers -productVersion 2>/dev/null)
  if [ "${v%%.*}" -ge 14 ] 2>/dev/null; then ok "macOS $v"; else bad "macOS 14 이상 필요 (현재 ${v:-알 수 없음})"; fi

  if command -v swift >/dev/null 2>&1; then ok "$(swift --version 2>&1 | head -1)"
  else bad "swift 없음 → xcode-select --install"; fi

  if command -v git >/dev/null 2>&1; then ok "git"; else bad "git 없음 → xcode-select --install"; fi

  c=$("${SHELL:-/bin/zsh}" -lc 'command -v claude' 2>/dev/null | tail -1)
  if [ -n "$c" ]; then ok "claude: $c"; else warn "claude CLI 없음: 요약 기능에 필요 (설치는 계속 가능)"; fi
fi

if [ -n "$DOCTOR_SKIP_XCODE_SELECT" ]; then active="$CLT_ROOT"; else active=$(xcode-select -p 2>/dev/null); fi
if [ "$active" = "$CLT_ROOT" ]; then
  stale=$("$HERE/clt-stale.sh")
  if [ -z "$stale" ]; then
    ok "Command Line Tools 잔여 파일 없음"
  else
    echo "$stale" | while IFS= read -r f; do
      case "$f" in
        *PackagePlugin*) echo "⚠️  오래된 파일: $f" ;;
        *) echo "❌ 오래된 파일: $f" ;;
      esac
    done
    # 경고만 있는 경우(PackagePlugin)는 실패로 치지 않는다
    echo "$stale" | grep -qv PackagePlugin && fail=1
    echo "   수정: sudo ./scripts/fix-clt.sh"
    echo "   또는 CLT 재설치: sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install"
  fi
else
  ok "개발자 디렉터리: ${active:-없음} (CLT 점검 생략)"
fi
exit $fail
