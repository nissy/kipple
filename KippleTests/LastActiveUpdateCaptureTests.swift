import XCTest
@testable import Kipple

@MainActor
final class LastActiveUpdateCaptureTests: XCTestCase {
    func testRememberAppForRestoreUpdatesTracker() {
        let tracker = SpyLastActiveAppTracker()
        let manager = WindowManager(lastActiveAppTracker: tracker, appReactivationDelay: 0)

        let info = LastActiveAppTracker.AppInfo(name: "TestApp", bundleId: "com.example.test", pid: 999)
        manager.rememberAppForRestoreForTesting(info)

        XCTAssertEqual(tracker.updateCallCount, 1)
        XCTAssertEqual(tracker.lastInfo?.bundleId, info.bundleId)
    }
}

@MainActor
private final class SpyLastActiveAppTracker: LastActiveAppTracking {
    var updateCallCount = 0
    var lastInfo: LastActiveAppTracker.AppInfo?
    var storedInfo = LastActiveAppTracker.AppInfo(name: "Spy", bundleId: "com.example.spy", pid: 1)

    func getSourceAppInfo() -> LastActiveAppTracker.AppInfo { storedInfo }
    func activateLastTrackedAppIfAvailable() { }
    func updateLastActiveApp(_ info: LastActiveAppTracker.AppInfo) {
        updateCallCount += 1
        lastInfo = info
    }
}
