import XCTest
@testable import Kipple

@MainActor
final class PasteCommandMonitorTests: XCTestCase {
    func testQueueShortcutRequiresAccessibility() {
        let monitor = PasteCommandMonitor { false }
        XCTAssertFalse(monitor.start { XCTFail("Untrusted shortcut must not run") })
    }

    func testOnlyRegisteredQueueShortcutInvokesHandler() {
        let monitor = PasteCommandMonitor { true }
        defer { monitor.stop() }
        var requests = 0
        XCTAssertTrue(monitor.start { requests += 1 })
        XCTAssertFalse(monitor.handleHotKey(signature: 0x4B505054, id: 1))
        XCTAssertFalse(monitor.handleHotKey(signature: 0x4B505151, id: 2))
        XCTAssertTrue(monitor.handleHotKey(signature: 0x4B505151, id: 1))
        XCTAssertEqual(requests, 1)
        monitor.stop()
        XCTAssertFalse(monitor.handleHotKey(signature: 0x4B505151, id: 1))
        XCTAssertEqual(requests, 1)
    }

    func testStoppingQueueReleasesCommandVAndAllowsRestart() {
        let first = PasteCommandMonitor { true }
        let second = PasteCommandMonitor { true }
        defer { first.stop(); second.stop() }
        XCTAssertTrue(first.start {})
        XCTAssertFalse(second.start {}, "A reserved shortcut must report the conflict")
        first.stop()
        XCTAssertTrue(second.start {})
        second.stop()
        XCTAssertTrue(first.start {})
    }
}
