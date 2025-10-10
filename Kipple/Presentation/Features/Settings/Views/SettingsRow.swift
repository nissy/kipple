//
//  SettingsRow.swift
//  Kipple
//
//  Created by Kipple on 2025/07/06.
//

import SwiftUI

struct SettingsRow<Content: View>: View {
    let label: String
    let description: String?
    let content: () -> Content
    let layout: Layout
    
    enum Layout {
        case trailingContent
        case inlineControl
    }
    
    init(
        label: String,
        description: String? = nil,
        layout: Layout = .trailingContent,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.description = description
        self.content = content
        self.layout = layout
    }
    
    var body: some View {
        Group {
            if layout == .inlineControl {
                VStack(alignment: .leading, spacing: SettingsLayoutMetrics.rowVerticalSpacing) {
                    content()
                    if let description = description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, SettingsLayoutMetrics.inlineDescriptionLeadingPadding)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: SettingsLayoutMetrics.rowHorizontalSpacing) {
                    labelView
                    VStack(alignment: .leading, spacing: SettingsLayoutMetrics.rowVerticalSpacing) {
                        content()
                        if let description = description {
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, SettingsLayoutMetrics.rowVerticalPadding)
    }

    private var labelView: some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .frame(width: SettingsLayoutMetrics.rowLabelWidth, alignment: .leading)
            .lineLimit(1)
    }
}

// MARK: - Convenience initializers for common controls

extension SettingsRow where Content == AnyView {
    init(label: String, description: String? = nil, isOn: Binding<Bool>) {
        self.init(label: label, description: description, layout: .inlineControl) {
            AnyView(
                Toggle(label, isOn: isOn)
                    .toggleStyle(.checkbox)
            )
        }
    }
    
    init(label: String, description: String? = nil, value: String) {
        self.init(label: label, description: description) {
            AnyView(
                Text(value)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            )
        }
    }
}
