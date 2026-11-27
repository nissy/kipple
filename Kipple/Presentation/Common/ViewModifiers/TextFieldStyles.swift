import SwiftUI

extension View {
    @ViewBuilder
    func kippleRoundedTextFieldStyle() -> some View {
#if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            self
                .textFieldStyle(.bordered)
                .textInputBorderShape(.roundedRectangle)
        } else {
            self.textFieldStyle(.roundedBorder)
        }
#else
        self.textFieldStyle(.roundedBorder)
#endif
    }
}
