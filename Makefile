APP := build/ATM.app
BIN_DIR := $(shell swift build -c release --show-bin-path)
# 항상 ~/Applications (관리자 권한이 일시적이어도 설치 위치·훅 경로가 바뀌지 않게). make install INSTALL_DIR=... 로 변경 가능.
INSTALL_DIR ?= $(HOME)/Applications

# 고정 서명 ID. 키체인에 "TaskWidget Dev" 코드 서명 인증서가 있으면 사용, 없으면 ad-hoc.
SIGN_ID ?= $(shell security find-identity -p codesigning 2>/dev/null | grep -q '"TaskWidget Dev"' && echo "TaskWidget Dev" || echo -)

.PHONY: build test app install run clean

build:
	swift build

test:
	swift test

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN_DIR)/TaskWidget $(APP)/Contents/MacOS/TaskWidget
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	codesign --force --timestamp=none --sign "$(SIGN_ID)" $(APP)
	@echo "signed with: $(SIGN_ID)"

install: app
	-pkill -x TaskWidget
	rm -rf "$(INSTALL_DIR)/TaskWidget.app" "$(INSTALL_DIR)/ATM.app"
	mkdir -p "$(INSTALL_DIR)"
	cp -R $(APP) "$(INSTALL_DIR)/"
	@echo "installed to $(INSTALL_DIR)/ATM.app"

run: app
	open $(APP)


clean:
	rm -rf .build build
