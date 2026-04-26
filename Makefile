SHELL := /bin/bash

.PHONY: help localization-generate localization-check shared-static-analysis shared-test android-debug android-connected-test coverage ios-project ios-open ios-lint ios-build ios-test ios-run screenshot-refresh verify-rc provision-devices security-scan-secrets github-release-controls clean-local

help:
	@echo "make localization-generate - Generate Android, iOS, and shared localization outputs"
	@echo "make localization-check - Verify localization outputs and locale parity"
	@echo "make shared-test  - Run shared Kotlin tests"
	@echo "make shared-static-analysis - Run shared Kotlin static analysis"
	@echo "make android-debug - Assemble the Android debug app"
	@echo "make android-connected-test - Run Android emulator-backed smoke test"
	@echo "make coverage     - Generate and verify Kotlin coverage report"
	@echo "make ios-project  - Generate the iOS Xcode project"
	@echo "make ios-open     - Generate and open the iOS project in Xcode"
	@echo "make ios-lint     - Run SwiftLint against iOS sources"
	@echo "make ios-build    - Build the iOS simulator app"
	@echo "make ios-test     - Run the iOS XCTest suite on simulator"
	@echo "make ios-run      - Build, install, and launch the iOS simulator app"
	@echo "make screenshot-refresh - Capture app scenes and regenerate store screenshots"
	@echo "make verify-rc    - Run release-candidate verification gate"
	@echo "make provision-devices - Provision simulators/AVDs from device pool"
	@echo "make security-scan-secrets - Scan tracked files for leaked secrets"
	@echo "make github-release-controls - Dry-run GitHub release environment setup"
	@echo "make clean-local  - Remove local build artifacts and caches"

localization-generate:
	./scripts/generate-localizations.rb

localization-check:
	./scripts/generate-localizations.rb --check

shared-static-analysis:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :shared:detekt

shared-test:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :shared:allTests

android-debug:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :androidApp:assembleDebug

android-connected-test:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :androidApp:connectedDebugAndroidTest

coverage:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :androidApp:jacocoDebugUnitTestReport :androidApp:jacocoDebugUnitTestCoverageVerification

ios-project:
	./scripts/generate-ios-project.sh

ios-open:
	./scripts/open-ios.sh

ios-lint:
	./scripts/lint-ios.sh

ios-build:
	./scripts/build-ios-sim.sh

ios-test:
	./scripts/test-ios-sim.sh

ios-run:
	./scripts/run-ios-sim.sh

screenshot-refresh:
	./scripts/refresh-store-screenshots.sh

verify-rc:
	./scripts/verify-rc.sh

provision-devices:
	./scripts/provision-device-pool.sh

security-scan-secrets:
	./scripts/scan-secrets.sh

github-release-controls:
	./scripts/setup-github-release-controls.sh

clean-local:
	rm -rf build androidApp/build shared/build .gradle .kotlin
