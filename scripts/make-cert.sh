#!/bin/bash
# 자체 서명 코드 서명 인증서 "TaskWidget Dev" 를 로그인 키체인에 만든다 (이미 있으면 종료).
set -e
if security find-identity -p codesigning | grep -q '"TaskWidget Dev"'; then
  echo "이미 있음: TaskWidget Dev"
  exit 0
fi
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT
cd "$d"
cat > cs.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = TaskWidget Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cs.cnf
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out tw.p12 -passout pass:tw-dev -name "TaskWidget Dev"
security import tw.p12 -k ~/Library/Keychains/login.keychain-db -P tw-dev -T /usr/bin/codesign
echo "완료: TaskWidget Dev 인증서를 만들었습니다. make install 을 다시 실행하세요."
