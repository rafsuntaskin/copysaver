.PHONY: build test app preview check verify archive community-dmg distribution

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
	python3 scripts/community-distribution.py config
	bash -n scripts/swift.sh scripts/build-app.sh scripts/verify-source.sh scripts/release.sh scripts/community-release.sh scripts/check-automatic-vault.sh scripts/draft-community-release.sh

verify:
	./scripts/verify-source.sh

archive:
	./scripts/release.sh archive

community-dmg:
	./scripts/community-release.sh

distribution:
	python3 scripts/community-distribution.py prepare
