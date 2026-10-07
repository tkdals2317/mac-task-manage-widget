#!/bin/sh
# Command Line Tools 안의 오래된 잔여 파일 경로를 한 줄씩 출력한다. (CLT_ROOT 로 경로 변경 가능)
CLT_ROOT="${CLT_ROOT:-/Library/Developer/CommandLineTools}"
DAY30=$((30 * 86400))

mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1"; }

# private.swiftinterface 가 같은 폴더의 일반 swiftinterface 보다 30일 넘게 오래됐으면 잔여 파일
for m in usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule usr/lib/swift/pm/PluginAPI/PackagePlugin.swiftmodule; do
  d="$CLT_ROOT/$m"
  [ -d "$d" ] || continue
  newest=0
  for f in "$d"/*.swiftinterface; do
    case "$f" in *.private.swiftinterface) continue ;; esac
    [ -f "$f" ] || continue
    t=$(mtime "$f"); [ "$t" -gt "$newest" ] && newest=$t
  done
  [ "$newest" -gt 0 ] || continue
  for f in "$d"/*.private.swiftinterface; do
    [ -f "$f" ] || continue
    [ $(( newest - $(mtime "$f") )) -gt "$DAY30" ] && echo "$f"
  done
done

# module.modulemap 과 bridging.modulemap 이 둘 다 SwiftBridging 을 선언하면 중복 정의
inc="$CLT_ROOT/usr/include/swift"
if [ -f "$inc/module.modulemap" ] && [ -f "$inc/bridging.modulemap" ] \
  && grep -q 'module SwiftBridging' "$inc/module.modulemap" \
  && grep -q 'module SwiftBridging' "$inc/bridging.modulemap"; then
  echo "$inc/module.modulemap"
fi
exit 0
