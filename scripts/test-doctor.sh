#!/bin/bash
# doctor / clt-stale / fix-clt 검증 (가짜 CLT 트리 사용)
cd "$(dirname "$0")" || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; check() { n=$((n+1)); if [ "$2" = ok ]; then echo "ok $n $1"; else echo "FAIL $n $1"; exit 1; fi; }

mk() { # $1=root $2=private mtime(touch -t)
  for m in ManifestAPI/PackageDescription PluginAPI/PackagePlugin; do
    d="$1/usr/lib/swift/pm/$m.swiftmodule"; mkdir -p "$d"
    for a in arm64 x86_64; do
      touch "$d/$a-apple-macos.swiftinterface"
      touch -t "$2" "$d/$a-apple-macos.private.swiftinterface"
    done
  done
  mkdir -p "$1/usr/include/swift"
  for f in module bridging; do echo 'module SwiftBridging {}' > "$1/usr/include/swift/$f.modulemap"; done
}

export DOCTOR_SKIP_XCODE_SELECT=1 DOCTOR_ONLY_CLT=1
mk "$T/dirty" 202401010000
export CLT_ROOT="$T/dirty"
[ "$(./clt-stale.sh | wc -l | tr -d ' ')" = 5 ] ; check "stale 5개(PD×2, PP×2, modulemap)" "$([ $? = 0 ] && echo ok)"
out=$(./doctor.sh); rc=$?
[ $rc = 1 ] && echo "$out" | grep -q 'sudo ./scripts/fix-clt.sh'; check "doctor exit 1 + 수정 명령" "$([ $? = 0 ] && echo ok)"
out=$(./fix-clt.sh 2>&1); rc=$?
[ $rc = 1 ] && echo "$out" | grep -q 'sudo ./scripts/fix-clt.sh'; check "비root 거부" "$([ $? = 0 ] && echo ok)"
out=$(FIX_CLT_ALLOW_NONROOT=1 BACKUP_ROOT="$T/bk" ./fix-clt.sh); echo "$out" | grep -q '완료: 5개'; check "5개 이동" "$([ $? = 0 ] && echo ok)"
[ "$(find "$T/bk" -type f | wc -l | tr -d ' ')" = 5 ] && [ ! -e "$T/dirty/usr/include/swift/module.modulemap" ]; check "백업 보존/원본 제거" "$([ $? = 0 ] && echo ok)"
out=$(FIX_CLT_ALLOW_NONROOT=1 BACKUP_ROOT="$T/bk" ./fix-clt.sh); echo "$out" | grep -q '정리할 파일 없음'; check "idempotent" "$([ $? = 0 ] && echo ok)"
./doctor.sh >/dev/null; check "정리 후 doctor exit 0" "$([ $? = 0 ] && echo ok)"

mk "$T/clean" 202601010000; touch "$T/clean/usr/lib/swift/pm/"*/*/*.swiftinterface
rm "$T/clean/usr/include/swift/module.modulemap"
export CLT_ROOT="$T/clean"
[ -z "$(./clt-stale.sh)" ]; check "깨끗한 트리는 stale 없음" "$([ $? = 0 ] && echo ok)"
echo "ALL PASS"
