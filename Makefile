SHELL := /bin/bash

.PHONY: help shared-test android-debug ios-project ios-open ios-build ios-run verify-rc provision-devices

help:
	@echo "make shared-test  - Run shared Kotlin tests"
	@echo "make android-debug - Assemble the Android debug app"
	@echo "make ios-project  - Generate the iOS Xcode project"
	@echo "make ios-open     - Generate and open the iOS project in Xcode"
	@echo "make ios-build    - Build the iOS simulator app"
	@echo "make ios-run      - Build, install, and launch the iOS simulator app"
	@echo "make verify-rc    - Run release-candidate verification gate"
	@echo "make provision-devices - Provision simulators/AVDs from device pool"

shared-test:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :shared:allTests

android-debug:
	@if [[ -z "$$JAVA_HOME" || ! -x "$$JAVA_HOME/bin/java" ]]; then export JAVA_HOME="$$(/usr/libexec/java_home -v 21 2>/dev/null)"; fi; ./gradlew :androidApp:assembleDebug

ios-project:
	./scripts/generate-ios-project.sh

ios-open:
	./scripts/open-ios.sh

ios-build:
	./scripts/build-ios-sim.sh

ios-run:
	./scripts/run-ios-sim.sh

verify-rc:
	./scripts/verify-rc.sh

provision-devices:
	./scripts/provision-device-pool.sh
