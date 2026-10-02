APP := build/TaskWidget.app
BIN_DIR := $(shell swift build -c release --show-bin-path)

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
	codesign --force --sign - $(APP)

install: app
	-pkill -x TaskWidget
	rm -rf /Applications/TaskWidget.app
	cp -R $(APP) /Applications/

run: app
	open $(APP)

clean:
	rm -rf .build build
