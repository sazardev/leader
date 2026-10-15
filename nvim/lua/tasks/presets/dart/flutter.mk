# Flutter app: run, test, analyze, code generation, Android builds
.PHONY: get run test analyze fmt gen apk bundle clean help

get: ## Fetch the packages
	flutter pub get

run: ## Run on the connected device
	flutter run

test: ## Run the tests
	flutter test

analyze: ## Static analysis
	flutter analyze

fmt: ## Format the code
	dart format .

gen: ## Run build_runner (generated code)
	dart run build_runner build --delete-conflicting-outputs

apk: ## Build a release APK
	flutter build apk --release

bundle: ## Build a release app bundle
	flutter build appbundle --release

clean: ## Clean and fetch the packages again
	flutter clean
	flutter pub get

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'
