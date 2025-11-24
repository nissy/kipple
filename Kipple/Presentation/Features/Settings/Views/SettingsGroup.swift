//
//  SettingsGroup.swift
//  Kipple
//
//  Created by Kipple on 2025/07/06.
//

import SwiftUI

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    let includeTopDivider: Bool
    let content: () -> Content
    let headerAccessory: AnyView?
    let headerAccessoryAlignment: HeaderAccessoryAlignment
    
    init(
        _ title: LocalizedStringKey,
        includeTopDivider: Bool = true,
        headerAccessory: AnyView? = nil,
        headerAccessoryAlignment: HeaderAccessoryAlignment = .trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.includeTopDivider = includeTopDivider
        self.content = content
        self.headerAccessory = headerAccessory
        self.headerAccessoryAlignment = headerAccessoryAlignment
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayoutMetrics.groupContainerSpacing) {
            if includeTopDivider {
                Divider()
                    .padding(.bottom, SettingsLayoutMetrics.groupDividerBottomPadding)
            }

            HStack(alignment: .center, spacing: SettingsLayoutMetrics.groupHeaderSpacing) {
                if headerAccessoryAlignment == .leading, let headerAccessory {
                    headerAccessory
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.leading, 1)
                Spacer(minLength: 0)

                if headerAccessoryAlignment == .trailing, let headerAccessory {
                    headerAccessory
                }
            }

            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.groupContentSpacing) {
                content()
            }
            .padding(.leading, SettingsLayoutMetrics.groupContentIndent)
        }
        .padding(
            .top,
            includeTopDivider
                ? SettingsLayoutMetrics.groupTopPaddingWithDivider
                : SettingsLayoutMetrics.groupTopPaddingWithoutDivider
        )
        .padding(.bottom, SettingsLayoutMetrics.groupBottomPadding)
    }
}

enum HeaderAccessoryAlignment {
    case leading
    case trailing
}
