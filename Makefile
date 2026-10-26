.PHONY: build test app preview

build:
	./scripts/swift.sh build

test:
	./scripts/swift.sh test --disable-xctest

app:
	./scripts/build-app.sh

preview: app
	open -na "$(CURDIR)/.build/CopySaverDev.app" --args --ui-preview
