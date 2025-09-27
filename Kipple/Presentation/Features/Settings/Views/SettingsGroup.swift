//
//  SettingsGroup.swift
//  Kipple
//
//  Created by Kipple on 2025/07/06.
//

import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: String
    let includeTopDivider: Bool
    let content: () -> Content
    
    init(
        _ title: String,
        includeTopDivider: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.includeTopDivider = includeTopDivider
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if includeTopDivider {
                Divider()
                    .padding(.bottom, 6)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.leading, 1)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 14)
        }
        .padding(.top, includeTopDivider ? 10 : 2)
        .padding(.bottom, 10)
    }
}
