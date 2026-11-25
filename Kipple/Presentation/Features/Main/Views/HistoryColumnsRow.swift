import SwiftUI

struct HistoryColumnsRow<Queue: View, Content: View, Pin: View, Category: View>: View {
    let showsQueue: Bool
    @ViewBuilder let queue: Queue
    @ViewBuilder let content: Content
    @ViewBuilder let pin: Pin
    @ViewBuilder let category: Category

    var body: some View {
        HStack(alignment: .center, spacing: MainViewMetrics.HistoryColumns.spacing) {
            if showsQueue { queue }
            content.frame(maxWidth: .infinity, alignment: .leading)
            pin
            category
        }
        .padding(.leading, MainViewMetrics.HistoryColumns.rowLeadingInset)
        .frame(maxWidth: .infinity)
    }
}
