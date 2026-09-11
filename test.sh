#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
for test in Tests/*Tests.swift; do
  name="${test:t:r}"
  swiftc -D IMPORT_TEST -swift-version 5 Sources/*.swift "$test" -o "build/tests/$name" -framework AppKit -framework SwiftUI -framework UserNotifications -framework WebKit -framework ServiceManagement
  "build/tests/$name"
done
