@testable import Kipple
import XCTest

@MainActor
final class ScreenRecordingPermissionOpenerTests: XCTestCase {
    func testOpenUsesFirstCandidateOnSuccess() {
        var attemptedURLs: [URL] = []
        var launchedProcess = false
        var executedScript: String?

        let dependencies = ScreenRecordingPermissionOpener.Dependencies(
            openURL: { url in
                attemptedURLs.append(url)
                return attemptedURLs.count == 1
            },
            launchProcess: { _, _ in
                launchedProcess = true
            },
            runAppleScript: { source in
                executedScript = source
            }
        )

        ScreenRecordingPermissionOpener.openSystemSettings(
            osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0),
            dependencies: dependencies
        )

        XCTAssertEqual(attemptedURLs.count, 1)
        XCTAssertTrue(attemptedURLs.first?.absoluteString.contains("Privacy_ScreenCapture") ?? false)
        XCTAssertFalse(launchedProcess)
        XCTAssertNil(executedScript)
    }

    func testOpenFallsBackToProcessAndAppleScript() {
        var attemptedURLs: [URL] = []
        var capturedProcess: (path: String, arguments: [String])?
        var executedScript: String?

        let dependencies = ScreenRecordingPermissionOpener.Dependencies(
            openURL: { url in
                attemptedURLs.append(url)
                return false
            },
            launchProcess: { path, arguments in
                capturedProcess = (path, arguments)
            },
            runAppleScript: { source in
                executedScript = source
            }
        )

        ScreenRecordingPermissionOpener.openSystemSettings(
            osVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 3, patchVersion: 0),
            dependencies: dependencies
        )

        XCTAssertEqual(attemptedURLs.count, 2)
        XCTAssertEqual(capturedProcess?.path, "/usr/bin/open")
        XCTAssertEqual(
            capturedProcess?.arguments,
            ["-b", "com.apple.systempreferences", "/System/Library/PreferencePanes/Security.prefPane"]
        )
        XCTAssertNotNil(executedScript)
        XCTAssertTrue(executedScript?.contains("Privacy_ScreenRecording") ?? false)
    }
}
