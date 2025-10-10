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
    let headerAccessory: AnyView?
    
    init(
        _ title: String,
        includeTopDivider: Bool = true,
        headerAccessory: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.includeTopDivider = includeTopDivider
        self.content = content
        self.headerAccessory = headerAccessory
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.groupContainerSpacing) {
            if includeTopDivider {
                Divider()
                    .padding(.bottom, SettingsLayoutMetrics.groupDividerBottomPadding)
            }

            HStack(alignment: .center, spacing: SettingsLayoutMetrics.groupHeaderSpacing) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.leading, 1)
                if let headerAccessory {
                    headerAccessory
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.groupContentSpacing) {
                content()
            }
            .padding(.leading, SettingsLayoutMetrics.groupContentIndent)
        }
        .padding(.top, SettingsLayoutMetrics.groupTopPadding)
        .padding(.bottom, SettingsLayoutMetrics.groupBottomPadding)
    }
}
