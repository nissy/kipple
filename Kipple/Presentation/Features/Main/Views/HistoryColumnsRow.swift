import SwiftUI

struct HistoryColumnsRow<Queue: View, Content: View, Category: View, Pin: View>: View {
    let showsQueue: Bool
    @ViewBuilder let queue: Queue
    @ViewBuilder let content: Content
    @ViewBuilder let category: Category
    @ViewBuilder let pin: Pin

    var body: some View {
        HStack(alignment: .center, spacing: MainViewMetrics.HistoryColumns.spacing) {
            if showsQueue { queue }
            content.frame(maxWidth: .infinity, alignment: .leading)
            category
            pin
        }
        .padding(.leading, MainViewMetrics.HistoryColumns.rowLeadingInset)
        .frame(maxWidth: .infinity)
    }
}
