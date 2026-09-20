//
//  TextRecognitionServiceProtocol.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import CoreGraphics

@MainActor
protocol TextRecognitionServiceProtocol: AnyObject {
    /// 指定された画像からテキストを抽出して返します。
    /// - Parameter image: 画面キャプチャなどのCGImage。
    /// - Returns: 認識したテキスト。段落を空行、表をTSVで表現します。
    ///   文字が検出できなかった場合は空文字列。
    func recognizeText(from image: CGImage) async throws -> String
}
