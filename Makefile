.DEFAULT_GOAL := help
VERSION ?= 0.1.0

.PHONY: help build release-build test app dmg dist run clean

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

build: ## Debug build (all targets)
	swift build

release-build: ## Release build
	swift build -c release

test: ## Run unit tests
	swift test

app: ## Assemble dist/Conure.app (release build, bundle CLI, codesign)
	scripts/make-app.sh $(VERSION)

dmg: app ## Package dist/Conure-$(VERSION).dmg (runs app first)
	scripts/make-dmg.sh $(VERSION)

dist: dmg ## Alias for dmg

run: build ## Print CLI version (smoke)
	swift run conure --version

clean: ## Remove build artifacts and dist/
	rm -rf .build dist
