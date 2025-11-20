import XCTest
@testable import Kipple

@MainActor
final class WindowFocusReturnTests: XCTestCase {
    func testFallbackWhenStoredAppUnavailable() async throws {
        let tracker = SpyLastActiveAppTracker()
        let manager = WindowManager(
            lastActiveAppTracker: tracker,
            appReactivationDelay: 0
        )

        manager.setAppToRestoreForTesting(
            LastActiveAppTracker.AppInfo(name: "Ghost", bundleId: nil, pid: Int32.max)
        )

        manager.triggerReactivationForTesting()

        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(tracker.activateLastTrackedCallCount, 1)
    }

    func testFallbackWhenNoStoredApp() async throws {
        let tracker = SpyLastActiveAppTracker()
        let manager = WindowManager(
            lastActiveAppTracker: tracker,
            appReactivationDelay: 0
        )

        manager.setAppToRestoreForTesting(nil)
        manager.triggerReactivationForTesting()

        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(tracker.activateLastTrackedCallCount, 1)
    }
}

@MainActor
private final class SpyLastActiveAppTracker: LastActiveAppTracking {
    var activateLastTrackedCallCount = 0
    var appInfo = LastActiveAppTracker.AppInfo(
        name: "Dummy",
        bundleId: "com.example.app",
        pid: 123
    )

    func getSourceAppInfo() -> LastActiveAppTracker.AppInfo {
        appInfo
    }

    func activateLastTrackedAppIfAvailable() {
        activateLastTrackedCallCount += 1
    }

    func updateLastActiveApp(_ info: LastActiveAppTracker.AppInfo) {
        appInfo = info
    }
}
