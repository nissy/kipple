//
//  SettingsRow.swift
//  Kipple
//
//  Created by Kipple on 2025/07/06.
//

import SwiftUI

struct SettingsRow<Content: View>: View {
    private let labelColumnWidth: CGFloat = 110
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
                VStack(alignment: .leading, spacing: 4) {
                    content()
                    if let description = description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.leading, 4)
                    }
                }
            } else {
                Grid(horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow(alignment: .firstTextBaseline) {
                        labelView
                        content()
                    }
                    
                    if let description = description {
                        GridRow(alignment: .top) {
                            spacerCell
                            Text(description)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }
    
    private var labelView: some View {
        Text(label)
            .font(.system(size: 13))
            .foregroundColor(.primary)
            .frame(width: labelColumnWidth, alignment: .leading)
    }
    
    private var spacerCell: some View {
        Color.clear
            .frame(width: labelColumnWidth, height: 0)
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
