#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
TEST_BUILD="$PROJECT_DIR/.build/tests"
mkdir -p "$TEST_BUILD" "$PROJECT_DIR/.build/swift-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/.build/swift-cache" \
  "$PROJECT_DIR/Sources/LedgerPricing.swift" "$PROJECT_DIR/Sources/LedgerCore.swift" "$PROJECT_DIR/Sources/LedgerAnalytics.swift" "$PROJECT_DIR/Sources/LedgerGoals.swift" "$PROJECT_DIR/Sources/LedgerShare.swift" "$PROJECT_DIR/Sources/LedgerDemo.swift" "$PROJECT_DIR/Sources/Localization.swift" "$PROJECT_DIR/Tests/CoreTests.swift" "$PROJECT_DIR/Tests/AnalyticsTests.swift" "$PROJECT_DIR/Tests/PricingTests.swift" "$PROJECT_DIR/Tests/SharedTests.swift" -lsqlite3 -o "$TEST_BUILD/CoreTests"
"$TEST_BUILD/CoreTests"
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/.build/swift-cache" \
  "$PROJECT_DIR/Sources/LedgerPricing.swift" "$PROJECT_DIR/Sources/LedgerCore.swift" "$PROJECT_DIR/Sources/LedgerAnalytics.swift" "$PROJECT_DIR/Sources/LedgerGoals.swift" "$PROJECT_DIR/Sources/LedgerShare.swift" "$PROJECT_DIR/Sources/LedgerDemo.swift" "$PROJECT_DIR/Sources/Localization.swift" "$PROJECT_DIR/Sources/LedgerStore.swift" "$PROJECT_DIR/Tests/StoreTests.swift" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement -lsqlite3 -o "$TEST_BUILD/StoreTests"
"$TEST_BUILD/StoreTests" --demo
xcrun swiftc -swift-version 5 -module-cache-path "$PROJECT_DIR/.build/swift-cache" \
  "$PROJECT_DIR/Sources/LedgerPricing.swift" "$PROJECT_DIR/Sources/LedgerCore.swift" "$PROJECT_DIR/Sources/LedgerAnalytics.swift" "$PROJECT_DIR/Sources/LedgerGoals.swift" "$PROJECT_DIR/Sources/LedgerShare.swift" "$PROJECT_DIR/Sources/LedgerDemo.swift" "$PROJECT_DIR/Sources/Localization.swift" "$PROJECT_DIR/Sources/LedgerStore.swift" "$PROJECT_DIR/Tests/GoalTests.swift" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement -lsqlite3 -o "$TEST_BUILD/GoalTests"
"$TEST_BUILD/GoalTests" --demo
