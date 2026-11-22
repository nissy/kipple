import SwiftUI

struct HistoryColumnsRow<Queue: View, Content: View, Delete: View, Pin: View, Category: View>: View {
    let showsQueue: Bool
    @ViewBuilder let queue: Queue
    @ViewBuilder let content: Content
    @ViewBuilder let delete: Delete
    @ViewBuilder let pin: Pin
    @ViewBuilder let category: Category

    var body: some View {
        HStack(alignment: .center, spacing: MainViewMetrics.HistoryColumns.spacing) {
            if showsQueue { queue }
            content.frame(maxWidth: .infinity, alignment: .leading)
            delete
            pin
            category
        }
        .padding(.horizontal, MainViewMetrics.HistoryColumns.rowHorizontalInset)
        .frame(maxWidth: .infinity)
    }
}
