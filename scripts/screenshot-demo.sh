#!/usr/bin/env bash
# README 스크린샷용 데모 실행. 가짜 데이터·별도 UserDefaults 도메인으로 띄우고, 실제 데이터·키체인·네트워크는 건드리지 않는다.
# 사전: make app (build/ATM.app). 사용: scripts/screenshot-demo.sh [데이터 폴더]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="$ROOT/build/ATM.app"
APP="$ROOT/build/ATM-demo.app"
REAL=com.lsm0506.TaskWidget
DEMO=com.lsm0506.TaskWidget.demo
DATA="${1:-${TMPDIR:-/tmp}/atm-demo-data}"
DATA="${DATA%/}"

[ -d "$SRC_APP" ] || { echo "build/ATM.app 이 없어요. 먼저 make app" >&2; exit 1; }

# 이미 떠 있는 데모 앱은 종료 (실제 ATM 은 건드리지 않는다)
pkill -f "$APP/Contents/MacOS" 2>/dev/null || true

# 1) 번들 복사 + 식별자 변경 + ad-hoc 재서명 (UserDefaults 도메인이 분리된다)
rm -rf "$APP"
cp -R "$SRC_APP" "$APP"
PL="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEMO" "$PL"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ATM" "$PL" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleName string ATM" "$PL"
codesign --force -s - --deep "$APP"

# 2) 새 데이터 폴더 + 샘플 데이터
rm -rf "$DATA"
mkdir -p "$DATA"
cp -R "$ROOT/docs/demo/data/." "$DATA/"

# 3) 데모 도메인 설정 (실제 도메인은 읽기만 한다)
defaults delete "$DEMO" >/dev/null 2>&1 || true
for k in themePreset theme opacity fontScale customBackground customAccent hoverOpaque; do
  if v=$(defaults read "$REAL" "$k" 2>/dev/null); then
    t=$(defaults read-type "$REAL" "$k" | awk '{print $NF}')
    case "$t" in
      float) defaults write "$DEMO" "$k" -float "$v" ;;
      integer) defaults write "$DEMO" "$k" -int "$v" ;;
      boolean) defaults write "$DEMO" "$k" -bool "$([ "$v" = 1 ] && echo true || echo false)" ;;
      *) defaults write "$DEMO" "$k" -string "$v" ;;
    esac
  fi
done
d() { defaults write "$DEMO" "$@"; }
d enabledTabs -string "tasks,summary,notes,pr,teleport"
d lastTab -string tasks
d onboardingDone -bool true
d notesTabIntroduced -bool true
d prTabIntroduced -bool true
d jiraEmail -string "demo@example.com"
d jiraBaseURL -string "https://example.atlassian.net"
d confluenceBaseURL -string "https://example.atlassian.net"
d prGitHubEnabled -bool true
d prBitbucketEnabled -bool true
d teleportAutoConnect -bool false
d globalHotKeyEnabled -bool false
d summaryNotify -bool false
d prNotifyNewReview -bool false
d prNotifyApproved -bool false
d prNotifyChanges -bool false
d prNotifyComments -bool false
# NEW 표시는 412번 하나만 남기도록 나머지 리뷰 요청은 '본 것'으로 둔다
d prSeenIDs -array "bitbucket:shop-team/order-batch#88" "github:shop-team/shop-web#305" \
  "github:shop-team/admin-console#77" "github:shop-team/shop-web#318"

# 4) 실행 (open 은 환경변수를 --env 로 넘긴다)
# 스크린샷 크기를 맞추려고 패널을 주 화면(레티나) 왼쪽 위 479x765 에 둔다
d "NSWindow Frame TaskWidgetPanel" -string "80 120 479 765 0 0 1512 945 "
open -n --env ATM_DATA_DIR="$DATA" --env ATM_DEMO_FIXTURES="$ROOT/docs/demo/fixtures" "$APP"
echo "데모 실행: 데이터 $DATA (잠긴 메모 비밀번호: demo1234)"
