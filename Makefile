.PHONY: build test

build:
	./scripts/swift.sh build

test:
	./scripts/swift.sh test --disable-xctest
