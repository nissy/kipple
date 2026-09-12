//
//  PasteCommandMonitorTests.swift
//  KippleTests
//
//  Created by Kipple on 2026/08/01.
//

import XCTest
import CoreGraphics
@testable import Kipple

final class PasteCommandMonitorTests: XCTestCase {
    private let selfPID: pid_t = 1234
    private let otherPID: pid_t = 5678
    private let keyCodeV: Int64 = 9

    func testCommandVTriggersPaste() {
        XCTAssertTrue(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: keyCodeV,
                flags: [.maskCommand],
                targetPID: otherPID,
                sourceUserData: 0,
                currentPID: selfPID
            )
        )
    }

    func testCommandVWithExtraModifierStillTriggers() {
        // キーリピートや Cmd+Shift 等の複合でも現行仕様どおり発火する
        XCTAssertTrue(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: keyCodeV,
                flags: [.maskCommand, .maskShift],
                targetPID: otherPID,
                sourceUserData: 0,
                currentPID: selfPID
            )
        )
    }

    func testUnknownTargetPIDTriggers() {
        // target PID が取れない (0) 場合は発火側に倒す
        XCTAssertTrue(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: keyCodeV,
                flags: [.maskCommand],
                targetPID: 0,
                sourceUserData: 0,
                currentPID: selfPID
            )
        )
    }

    func testNonCommandKeyDownDoesNotTrigger() {
        XCTAssertFalse(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: keyCodeV,
                flags: [],
                targetPID: otherPID,
                sourceUserData: 0,
                currentPID: selfPID
            )
        )
    }

    func testOtherKeyCodeDoesNotTrigger() {
        XCTAssertFalse(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: 8, // 'c'
                flags: [.maskCommand],
                targetPID: otherPID,
                sourceUserData: 0,
                currentPID: selfPID
            )
        )
    }

    func testSelfTargetedEventDoesNotTrigger() {
        // Kipple 自身 (検索フィールド等) へのペーストではキューを進めない
        XCTAssertFalse(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: keyCodeV,
                flags: [.maskCommand],
                targetPID: selfPID,
                sourceUserData: 0,
                currentPID: selfPID
            )
        )
    }

    func testSyntheticAutoPasteEventDoesNotTrigger() {
        // AutoPasteController が合成した Cmd+V ではキューを進めない
        XCTAssertFalse(
            PasteCommandMonitor.shouldTriggerPaste(
                keyCode: keyCodeV,
                flags: [.maskCommand],
                targetPID: otherPID,
                sourceUserData: SyntheticPasteEvent.sourceUserData,
                currentPID: selfPID
            )
        )
    }
}
