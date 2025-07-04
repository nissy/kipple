//
//  FontNameMappingsTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/01.
//

import XCTest
@testable import Kipple

final class FontNameMappingsTests: XCTestCase {
    
    func testJapaneseFontMapping() {
        // Given
        let hiraginoSansW3 = "HiraginoSans-W3"
        let hiraginoSansW6 = "HiraginoSans-W6"
        let hiraginoSansRegular = "HiraginoSans-Regular"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: hiraginoSansW3), "ヒラギノ角ゴシック W3")
        XCTAssertEqual(FontNameMappings.displayName(for: hiraginoSansW6), "ヒラギノ角ゴシック W6")
        XCTAssertEqual(FontNameMappings.displayName(for: hiraginoSansRegular), "ヒラギノ角ゴシック")
    }
    
    func testYuGothicFontMapping() {
        // Given
        let yuGothicBold = "YuGothic-Bold"
        let yuGothicMedium = "YuGothic-Medium"
        let yuGothicRegular = "YuGothic-Regular"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: yuGothicBold), "游ゴシック Bold")
        XCTAssertEqual(FontNameMappings.displayName(for: yuGothicMedium), "游ゴシック Medium")
        XCTAssertEqual(FontNameMappings.displayName(for: yuGothicRegular), "游ゴシック")
    }
    
    func testMonospaceFontMapping() {
        // Given
        let sfMono = "SFMono-Regular"
        let menlo = "Menlo-Regular"
        let monaco = "Monaco"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: sfMono), "SF Mono")
        XCTAssertEqual(FontNameMappings.displayName(for: menlo), "Menlo")
        XCTAssertEqual(FontNameMappings.displayName(for: monaco), "Monaco")
    }
    
    func testCJKFontMapping() {
        // Given
        let notoSansCJKJP = "NotoSansCJK-jp"
        let notoSansCJKSC = "NotoSansCJK-sc"
        let notoSansCJKRegular = "NotoSansCJK-Regular"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: notoSansCJKJP), "Noto Sans CJK JP")
        XCTAssertEqual(FontNameMappings.displayName(for: notoSansCJKSC), "Noto Sans CJK SC")
        XCTAssertEqual(FontNameMappings.displayName(for: notoSansCJKRegular), "Noto Sans CJK")
    }
    
    func testRegularSuffixRemoval() {
        // Given
        let fontWithDashRegular = "CustomFont-Regular"
        let fontWithRegularSuffix = "AnotherFontRegular"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: fontWithDashRegular), "CustomFont")
        XCTAssertEqual(FontNameMappings.displayName(for: fontWithRegularSuffix), "AnotherFont")
    }
    
    func testUnknownFontMapping() {
        // Given
        let unknownFont = "UnknownCustomFont"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: unknownFont), "UnknownCustomFont")
    }
    
    func testOsakaMonoFontMapping() {
        // Given
        let osakaMonoFont = "Osaka-Mono"
        let osakaRegularFont = "Osaka-Regular"
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: osakaMonoFont), "Osaka 等幅")
        XCTAssertEqual(FontNameMappings.displayName(for: osakaRegularFont), "Osaka")
    }
    
    func testEmptyAndSpecialCases() {
        // Given
        let emptyString = ""
        let spaceString = " "
        
        // When & Then
        XCTAssertEqual(FontNameMappings.displayName(for: emptyString), "")
        XCTAssertEqual(FontNameMappings.displayName(for: spaceString), " ")
    }
}
