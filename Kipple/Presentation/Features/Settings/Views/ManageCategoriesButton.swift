import SwiftUI
import AppKit

struct ManageCategoriesButton: View {
    var body: some View {
        Button(
            action: {
                CategoryManagerWindowCoordinator.shared.open(relativeTo: NSApp.keyWindow)
            },
            label: {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                    Text("Manage…")
                }
            }
        )
        .buttonStyle(.borderedProminent)
    }
}
