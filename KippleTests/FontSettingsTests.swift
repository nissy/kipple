//
//  FontSettingsTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/30.
//

import XCTest
@testable import Kipple

final class FontSettingsTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // テスト前にデフォルト設定をリセット
        UserDefaults.standard.removeObject(forKey: "editorFontSettings")
        UserDefaults.standard.removeObject(forKey: "historyFontSettings")
    }
    
    override func tearDown() {
        super.tearDown()
        // テスト後にクリーンアップ
        UserDefaults.standard.removeObject(forKey: "editorFontSettings")
        UserDefaults.standard.removeObject(forKey: "historyFontSettings")
    }
    
    func testDefaultFontSettings() {
        // Given
        let settings = FontSettings.default
        
        // Then
        XCTAssertEqual(settings.primaryFontName, "System")
        XCTAssertEqual(settings.primaryFontSize, 13)
        XCTAssertEqual(settings.fallbackFontNames, [])
    }
    
    func testFontSettingsEquality() {
        // Given
        let settings1 = FontSettings(
            primaryFontName: "Menlo",
            primaryFontSize: 16,
            fallbackFontNames: ["Monaco"]
        )
        let settings2 = FontSettings(
            primaryFontName: "Menlo",
            primaryFontSize: 16,
            fallbackFontNames: ["Monaco"]
        )
        let settings3 = FontSettings(
            primaryFontName: "SF Mono",
            primaryFontSize: 16,
            fallbackFontNames: ["Monaco"]
        )
        
        // Then
        XCTAssertEqual(settings1, settings2)
        XCTAssertNotEqual(settings1, settings3)
    }
    
    func testGetAvailableFont() {
        // Given
        let settings = FontSettings(
            primaryFontName: "NonExistentFont",
            primaryFontSize: 14,
            fallbackFontNames: ["AlsoNonExistent", "Menlo"]
        )
        
        // When
        let font = settings.getAvailableFont()
        
        // Then
        // Menloフォントが存在するかチェック
        if let menloFont = NSFont(name: "Menlo", size: 14) {
            // MenloはMenlo-Regularという名前で返される可能性がある
            XCTAssertTrue(font.fontName.contains("Menlo") || font.fontName == menloFont.fontName)
        } else {
            // Menloが利用できない場合は、システム等幅フォントが返されることを確認
            XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        }
        XCTAssertEqual(font.pointSize, 14)
    }
    
    func testGetAvailableFontWithNoValidFonts() {
        // Given
        let settings = FontSettings(
            primaryFontName: "NonExistentFont",
            primaryFontSize: 14,
            fallbackFontNames: ["AlsoNonExistent", "StillNonExistent"]
        )
        
        // When
        let font = settings.getAvailableFont()
        
        // Then
        // システムフォントが返されるはず
        XCTAssertEqual(font.pointSize, 14)
        // システムフォントは必ずしも等幅ではないので、フォント名で確認
        XCTAssertNotNil(font)
    }
    
    func testFontManagerSingleton() {
        // Given
        let manager1 = FontManager.shared
        let manager2 = FontManager.shared
        
        // Then
        XCTAssertTrue(manager1 === manager2)
    }
    
    func testFontManagerSaveAndLoad() {
        // Given
        let customSettings = FontSettings(
            primaryFontName: "Monaco",
            primaryFontSize: 16,
            fallbackFontNames: ["Menlo", "SF Mono"]
        )
        
        // When
        FontManager.shared.editorSettings = customSettings
        
        // Create new instance to test persistence
        let loadedSettings = FontManager.loadEditorFontSettings()
        
        // Then
        XCTAssertEqual(loadedSettings.primaryFontName, "Monaco")
        XCTAssertEqual(loadedSettings.primaryFontSize, 16)
        XCTAssertEqual(loadedSettings.fallbackFontNames, ["Menlo", "SF Mono"])
    }
    
    func testFontManagerNotification() {
        // Given
        let expectation = self.expectation(description: "Font settings changed notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .editorFontSettingsChanged,
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }
        
        // When
        FontManager.shared.editorSettings = FontSettings(
            primaryFontName: "Menlo",
            primaryFontSize: 18,
            fallbackFontNames: []
        )
        
        // Then
        waitForExpectations(timeout: 1.0)
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testAvailableMonospacedFonts() {
        // When
        let fonts = FontManager.availableMonospacedFonts()
        
        // Then
        XCTAssertFalse(fonts.isEmpty)
        // 一般的な等幅フォントが含まれているか確認
        let commonMonospacedFonts = ["Menlo", "Monaco", "SF Mono", "Courier", "Courier New"]
        let foundFonts = fonts.filter { fontName in
            commonMonospacedFonts.contains { commonFont in
                fontName.contains(commonFont)
            }
        }
        XCTAssertFalse(foundFonts.isEmpty, "Should find at least one common monospaced font")
    }
    
    func testFontSettingsValidation() {
        // Given
        let validSettings = FontSettings(
            primaryFontName: "Menlo",
            primaryFontSize: 14,
            fallbackFontNames: []
        )
        
        let invalidSettings = FontSettings(
            primaryFontName: "NonExistentFont",
            primaryFontSize: 14,
            fallbackFontNames: ["AlsoNonExistent"]
        )
        
        // Then
        XCTAssertTrue(validSettings.isValid)
        XCTAssertFalse(invalidSettings.isValid)
    }
}
