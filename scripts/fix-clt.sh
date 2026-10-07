#!/bin/sh
# CLT 잔여 파일을 삭제하지 않고 백업 폴더로 옮긴다. sudo 로 실행.
HERE=$(cd "$(dirname "$0")" && pwd)
CLT_ROOT="${CLT_ROOT:-/Library/Developer/CommandLineTools}"
export CLT_ROOT
if [ "$(id -u)" -ne 0 ] && [ -z "$FIX_CLT_ALLOW_NONROOT" ]; then
  echo "sudo ./scripts/fix-clt.sh 로 실행하세요"; exit 1
fi
dest="${BACKUP_ROOT:-/Library/Developer/CLT-stale-backup}/$(date +%Y%m%d-%H%M%S)"
n=0
for f in $("$HERE/clt-stale.sh"); do
  rel="${f#"$CLT_ROOT"/}"
  mkdir -p "$dest/$(dirname "$rel")" && mv "$f" "$dest/$rel" || exit 1
  echo "이동: $f -> $dest/$rel"
  n=$((n + 1))
done
if [ "$n" -eq 0 ]; then echo "정리할 파일 없음"
else echo "완료: ${n}개 이동. 되돌리려면 이 폴더의 파일을 원래 경로로 옮기면 됩니다."; fi
