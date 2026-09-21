import ServiceManagement
import XCTest
@testable import Kipple

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testPendingApprovalCanBeUnregistered() {
        var status: SMAppService.Status = .requiresApproval
        var unregisterCalls = 0
        let manager = LaunchAtLogin(readStatus: { status }, register: { XCTFail("Unexpected registration") }, unregister: {
            unregisterCalls += 1
            status = .notRegistered
        })
        XCTAssertTrue(manager.isEnabled)
        manager.setEnabled(false)
        XCTAssertEqual(unregisterCalls, 1)
        XCTAssertEqual(manager.status, .notRegistered)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRegistrationReportsPendingApprovalWithoutRegisteringAgain() {
        var status: SMAppService.Status = .notRegistered
        var registerCalls = 0
        let manager = LaunchAtLogin(readStatus: { status }, register: {
            registerCalls += 1
            status = .requiresApproval
        }, unregister: { XCTFail("Unexpected unregistration") })
        manager.setEnabled(true)
        manager.setEnabled(true)
        XCTAssertEqual(registerCalls, 1)
        XCTAssertEqual(manager.status, .requiresApproval)
    }

    func testExternalChangesRefreshDisplayedState() {
        var status: SMAppService.Status = .enabled
        let manager = LaunchAtLogin(readStatus: { status }, register: {}, unregister: {})
        status = .requiresApproval
        manager.checkStatus()
        XCTAssertEqual(manager.status, .requiresApproval)
        status = .notRegistered
        manager.checkStatus()
        XCTAssertFalse(manager.isEnabled)
        status = .notFound
        manager.checkStatus()
        XCTAssertEqual(manager.status, .notFound)
    }

    func testFailedRegistrationKeepsActualDisabledState() {
        let manager = LaunchAtLogin(readStatus: { .notRegistered }, register: {
            throw CocoaError(.fileReadNoPermission)
        }, unregister: {})
        manager.setEnabled(true)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.status, .notRegistered)
    }
}
