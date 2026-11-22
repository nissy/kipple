import SwiftUI

extension View {
    @ViewBuilder
    func kippleRoundedTextFieldStyle() -> some View {
        if #available(macOS 27.0, *) {
            self
                .textFieldStyle(.bordered)
                .textInputBorderShape(.roundedRectangle)
        } else {
            self.textFieldStyle(.roundedBorder)
        }
    }
}
