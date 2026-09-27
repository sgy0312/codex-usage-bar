.PHONY: build check install print-once clean

build:
	./build.sh

check: build
	plutil -lint Resources/Info.plist
	./build/Codex\ Usage\ Bar.app/Contents/MacOS/CodexUsageBar --self-test

install: build
	./install.sh

print-once: build
	./build/Codex\ Usage\ Bar.app/Contents/MacOS/CodexUsageBar --print-once

clean:
	rm -rf build
