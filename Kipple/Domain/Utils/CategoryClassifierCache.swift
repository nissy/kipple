//
//  CategoryClassifierCache.swift
//  Kipple
//
//  Lightweight in‑process cache for ClipItem category classification.
//  Caches by content only. Editor-origin items bypass cache (always .kipple).
//

import Foundation

final class CategoryClassifierCache {
    static let shared = CategoryClassifierCache()
    private let cache = NSCache<NSString, NSString>()

    private init() {
        // Reasonable limit to avoid unbounded growth
        cache.countLimit = 1000
    }

    func get(for content: String) -> ClipItemCategory? {
        if let raw = cache.object(forKey: content as NSString) {
            return ClipItemCategory(rawValue: raw as String)
        }
        return nil
    }

    func set(_ category: ClipItemCategory, for content: String) {
        cache.setObject(category.rawValue as NSString, forKey: content as NSString)
    }
}

extension CategoryClassifierCache: @unchecked Sendable {}
