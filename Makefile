APP := build/TaskWidget.app
BIN_DIR := $(shell swift build -c release --show-bin-path)
# /Applications 쓰기 불가(비관리자 계정)면 ~/Applications. make install INSTALL_DIR=... 로 지정 가능.
INSTALL_DIR ?= $(if $(shell test -w /Applications && echo y),/Applications,$(HOME)/Applications)

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
	codesign --force --timestamp=none --sign "$(SIGN_ID)" $(APP)
	@echo "signed with: $(SIGN_ID)"

install: app
	-pkill -x TaskWidget
	rm -rf "$(INSTALL_DIR)/TaskWidget.app"
	mkdir -p "$(INSTALL_DIR)"
	cp -R $(APP) "$(INSTALL_DIR)/"
	@echo "installed to $(INSTALL_DIR)/TaskWidget.app"

run: app
	open $(APP)

clean:
	rm -rf .build build
