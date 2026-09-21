import SwiftUI

struct CategoryLabelsView: View {
    let categories: [UserCategory]
    var isPreview = false

    var body: some View {
        Group {
            if isPreview {
                preview
            } else {
                ViewThatFits(in: .vertical) {
                    labels(limit: categories.count)
                    ScrollView(.vertical) {
                        labels(limit: categories.count)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: 120)
                }
            }
        }
        .frame(maxHeight: 120, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var preview: some View {
        ViewThatFits(in: .vertical) {
            labels(limit: categories.count)
            ForEach(previewLimits, id: \.self) { limit in
                VStack(alignment: .leading, spacing: 6) {
                    labels(limit: limit)
                    Text("Open item details to view all categories.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var previewLimits: [Int] {
        guard categories.count > 1 else { return [] }
        return Array((1...min(categories.count - 1, 6)).reversed())
    }

    private func labels(limit: Int) -> some View {
        CategoryLabelsLayout(spacing: 6) {
            ForEach(Array(categories.prefix(limit))) { category in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: category.iconSystemName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(verbatim: category.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .help(category.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: category.name))
            }
            if categories.count > limit {
                Text("+\(categories.count - limit)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(Text(verbatim: categories.dropFirst(limit).map(\.name).joined(separator: ", ")))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CategoryLabelsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(CGFloat.zero) {
            $0 + $1.sizeThatFits(.unspecified).width + spacing
        }
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        let availableWidth = max(0, width)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let size = subview.sizeThatFits(ProposedViewSize(width: min(ideal.width, availableWidth), height: nil))
            if x > 0 && x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: availableWidth, height: y + rowHeight), frames)
    }
}
