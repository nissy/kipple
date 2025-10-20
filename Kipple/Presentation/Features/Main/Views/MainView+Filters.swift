//
//  MainView+Filters.swift
//  Kipple
//
//  Created by Kipple on 2025/10/20.
//

import Foundation

internal extension MainView {
    func isCategoryFilterEnabled(_ category: ClipItemCategory) -> Bool {
        switch category {
        case .all:
            return true
        case .url:
            return AppSettings.shared.filterCategoryURL
        }
    }
}
