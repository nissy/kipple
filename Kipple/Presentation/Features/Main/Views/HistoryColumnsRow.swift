import SwiftUI

// The toolbar and history entries share the same column widths and spacing.
struct HistoryColumnsRow<Queue: View, Pin: View, Category: View, Content: View, Trailing: View>: View {
    let showsQueue: Bool
    @ViewBuilder let queue: Queue
    @ViewBuilder let pin: Pin
    @ViewBuilder let category: Category
    @ViewBuilder let content: Content
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: MainViewMetrics.HistoryColumns.spacing) {
            if showsQueue { column(queue) }
            column(pin)
            column(category)
            content.frame(maxWidth: .infinity, alignment: .leading)
            column(trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func column<V: View>(_ view: V) -> some View {
        view.frame(
            width: MainViewMetrics.HistoryColumns.controlColumnWidth,
            height: MainViewMetrics.HistoryColumns.controlColumnWidth,
            alignment: .center
        )
    }
}
