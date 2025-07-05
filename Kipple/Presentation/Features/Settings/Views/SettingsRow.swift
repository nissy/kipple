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
    
    init(label: String, description: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.description = description
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                
                Spacer()
                
                content()
            }
            
            if let description = description {
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Convenience initializers for common controls

extension SettingsRow where Content == AnyView {
    init(label: String, description: String? = nil, isOn: Binding<Bool>) {
        self.init(label: label, description: description) {
            AnyView(
                Toggle("", isOn: isOn)
                    .toggleStyle(SwitchToggleStyle())
                    .labelsHidden()
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
