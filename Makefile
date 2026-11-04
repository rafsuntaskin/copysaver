.PHONY: build test app preview check verify archive community-dmg

build:
	./scripts/swift.sh build

test:
	./scripts/swift.sh test --disable-xctest

app:
	./scripts/build-app.sh

preview: app
	open -na "$(CURDIR)/.build/CopySaverDev.app" --args --ui-preview

check:
	python3 scripts/check-project.py
	bash -n scripts/swift.sh scripts/build-app.sh scripts/verify-source.sh scripts/release.sh scripts/community-release.sh scripts/check-automatic-vault.sh

verify:
	./scripts/verify-source.sh

archive:
	./scripts/release.sh archive

community-dmg:
	./scripts/community-release.sh
