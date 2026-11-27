import SwiftDiff

struct TextComparison: Sendable {
    struct Line: Sendable {
        struct Change: Sendable {
            let range: Range<String.Index>
            let difference: Int
        }

        let number: Int
        let text: String
        var changes: [Change] = []
        var lineBreakDifference: Int?

        var lineBreakChanged: Bool { lineBreakDifference != nil }
        var hasChanges: Bool { !changes.isEmpty || lineBreakChanged }

        func containsDifference(_ difference: Int) -> Bool {
            lineBreakDifference == difference || changes.contains { $0.difference == difference }
        }
    }

    struct Row: Sendable {
        enum Kind: Sendable {
            case equal, replaced, removed, inserted
        }

        let left: Line?
        let right: Line?
        let kind: Kind
    }

    struct Difference: Sendable {
        let id: Int
        let row: Int
    }

    let rows: [Row]
    let differences: [Difference]
    let selection: String

    init(clipboard: String, selection: String) {
        self.selection = selection
        let left = SourceLine.split(clipboard)
        let right = SourceLine.split(selection)
        let changes = Changes(from: left, to: right)
        var rows: [Row] = []
        var differenceCount = 0
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < left.count || rightIndex < right.count {
            let leftEnd = changes.removals.endOfRun(startingAt: leftIndex)
            let rightEnd = changes.insertions.endOfRun(startingAt: rightIndex)
            if leftEnd > leftIndex || rightEnd > rightIndex {
                rows.append(contentsOf: Self.changedRows(
                    left: left[leftIndex..<leftEnd], right: right[rightIndex..<rightEnd],
                    differenceCount: &differenceCount
                ))
                leftIndex = leftEnd
                rightIndex = rightEnd
            } else {
                rows.append(Row(
                    left: Line(number: leftIndex + 1, text: left[leftIndex].text),
                    right: Line(number: rightIndex + 1, text: right[rightIndex].text),
                    kind: .equal
                ))
                leftIndex += 1
                rightIndex += 1
            }
        }
        self.rows = rows
        var firstRows = Array(repeating: 0, count: differenceCount)
        for index in rows.indices.reversed() where rows[index].kind != .equal {
            Self.assignChangeRows(for: rows[index].left, at: index, in: &firstRows)
            Self.assignChangeRows(for: rows[index].right, at: index, in: &firstRows)
        }
        // Line alignment can place related edits on different rows. Navigate in display order.
        differences = firstRows
            .enumerated()
            .map { Difference(id: $0.offset, row: $0.element) }
            .sorted { ($0.row, $0.id) < ($1.row, $1.id) }
    }

    private static func assignChangeRows(for line: Line?, at index: Int, in changeRows: inout [Int]) {
        guard let line else { return }
        for change in line.changes { changeRows[change.difference] = index }
        if let difference = line.lineBreakDifference { changeRows[difference] = index }
    }

    private struct SourceLine: Hashable {
        let text: String
        let hasLineBreak: Bool

        static func split(_ text: String) -> [Self] {
            let parts = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            return parts.indices.map { Self(text: String(parts[$0]), hasLineBreak: $0 < parts.count - 1) }
        }
    }

    private static func changedRows(
        left: ArraySlice<SourceLine>, right: ArraySlice<SourceLine>, differenceCount: inout Int
    ) -> [Row] {
        var before = Projection(left)
        var after = Projection(right)
        var matches: [LineMatch] = []
        var currentDifference: Int?
        let diff = blockDiff(before.text, after.text)
        for change in diff {
            switch change {
            case .equal(let text):
                guard !text.isEmpty else { continue }
                currentDifference = nil
                var remaining = text.count
                while remaining > 0 {
                    let count = min(remaining, before.remaining, after.remaining)
                    let match = LineMatch(left: before.lineIndex, right: after.lineIndex)
                    let leftHasText = before.advance(count, difference: nil)
                    let rightHasText = after.advance(count, difference: nil)
                    if leftHasText && rightHasText, matches.last != match {
                        matches.append(match)
                    }
                    remaining -= count
                }
            case .delete(let text), .insert(let text):
                guard !text.isEmpty else { continue }
                // Adjacent deletions and insertions are the two sides of one difference.
                let difference = currentDifference ?? differenceCount
                if currentDifference == nil {
                    currentDifference = difference
                    differenceCount += 1
                }
                if case .delete = change {
                    before.markChanges(text.count, difference: difference)
                } else {
                    after.markChanges(text.count, difference: difference)
                }
            }
        }
        return alignedRows(before, after, matches: matches)
    }

    private static func alignedRows(_ before: Projection, _ after: Projection, matches: [LineMatch]) -> [Row] {
        var rows: [Row] = []
        var left = 0
        var right = 0

        func append(until match: LineMatch) {
            while left < match.left || right < match.right {
                let old = left < match.left ? left : nil
                let new = right < match.right ? right : nil
                rows.append(row(before, at: old, after, at: new))
                if old != nil { left += 1 }
                if new != nil { right += 1 }
            }
        }

        for match in matches where match.left >= left && match.right >= right {
            append(until: match)
            rows.append(row(before, at: left, after, at: right))
            left += 1
            right += 1
        }
        append(until: LineMatch(left: before.lines.count, right: after.lines.count))
        return rows
    }

    private static func row(_ before: Projection, at left: Int?, _ after: Projection, at right: Int?) -> Row {
        let old = left.map { before.lines[$0] }
        let new = right.map { after.lines[$0] }
        let kind: Row.Kind
        if let left, right == nil, before.isUnmatchedLine(left) {
            kind = .removed
        } else if let right, left == nil, after.isUnmatchedLine(right) {
            kind = .inserted
        } else {
            kind = old?.hasChanges == true || new?.hasChanges == true ? .replaced : .equal
        }
        return Row(left: old, right: new, kind: kind)
    }

    private struct LineMatch: Equatable {
        let left: Int
        let right: Int
    }

    private struct Projection {
        private let source: [SourceLine]
        private var textOffset: String.Index?
        private var remainingText: Int
        private var matchedLines: Set<Int> = []
        private(set) var lineIndex = 0
        private(set) var lines: [Line]

        var text: String {
            source.map { $0.hasLineBreak ? $0.text + "\n" : $0.text }.joined()
        }

        var remaining: Int {
            remainingText + (source[lineIndex].hasLineBreak ? 1 : 0)
        }

        init(_ source: ArraySlice<SourceLine>) {
            self.source = Array(source)
            lines = source.indices.map { Line(number: $0 + 1, text: source[$0].text) }
            remainingText = source.first?.text.count ?? 0
        }

        func isUnmatchedLine(_ index: Int) -> Bool {
            !matchedLines.contains(index) && (source[index].hasLineBreak || !source[index].text.isEmpty)
        }

        mutating func markChanges(_ length: Int, difference: Int) {
            var remainingLength = length
            while remainingLength > 0 {
                let count = min(remainingLength, remaining)
                _ = advance(count, difference: difference)
                remainingLength -= count
            }
        }

        mutating func advance(_ count: Int, difference: Int?) -> Bool {
            let text = source[lineIndex].text
            let start = textOffset ?? text.startIndex
            let textCount = min(count, remainingText)
            let end = text.index(start, offsetBy: textCount)
            let matched = difference == nil && text[start..<end].contains { !$0.isWhitespace }
            if matched { matchedLines.insert(lineIndex) }
            if let difference {
                if start < end { lines[lineIndex].changes.append(.init(range: start..<end, difference: difference)) }
                if count > textCount { lines[lineIndex].lineBreakDifference = difference }
            }
            if count == remaining {
                lineIndex += 1
                textOffset = nil
                remainingText = source.indices.contains(lineIndex) ? source[lineIndex].text.count : 0
            } else {
                textOffset = end
                remainingText -= textCount
            }
            return matched
        }
    }

    private static func blockDiff(_ before: String, _ after: String) -> [Diff] {
        if before.isEmpty { return [.insert(text: after)] }
        if after.isEmpty { return [.delete(text: before)] }
        // SwiftDiff's half-match search can exceed its own timeout on long, repetitive input.
        if max(before.utf8.count, after.utf8.count) <= 512 {
            return SwiftDiff.diff(text1: before, text2: after, timeout: 0.05)
        }

        let left = Array(before)
        let right = Array(after)
        let changes = Changes(from: left, to: right, withinLine: true)
        var edits: [Diff] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < left.count || newIndex < right.count {
            let oldEnd = changes.removals.endOfRun(startingAt: oldIndex)
            let newEnd = changes.insertions.endOfRun(startingAt: newIndex)
            if oldEnd > oldIndex { edits.append(.delete(text: String(left[oldIndex..<oldEnd]))) }
            if newEnd > newIndex { edits.append(.insert(text: String(right[newIndex..<newEnd]))) }
            oldIndex = oldEnd
            newIndex = newEnd

            let equalStart = oldIndex
            while oldIndex < left.count, newIndex < right.count,
                  !changes.removals.contains(oldIndex), !changes.insertions.contains(newIndex) {
                oldIndex += 1
                newIndex += 1
            }
            if oldIndex > equalStart { edits.append(.equal(text: String(left[equalStart..<oldIndex]))) }
        }
        return edits
    }

    private static func commonPrefixCount<Items: Sequence>(_ first: Items, _ second: Items) -> Int
    where Items.Element: Equatable {
        zip(first, second).prefix { $0 == $1 }.count
    }

    private struct Changes {
        var removals: Set<Int> = []
        var insertions: Set<Int> = []

        init<Element: Hashable>(from: [Element], to: [Element], withinLine: Bool = false) {
            let prefix = commonPrefixCount(from, to)
            let suffix = commonPrefixCount(from.dropFirst(prefix).reversed(), to.dropFirst(prefix).reversed())
            let before = from[prefix..<(from.count - suffix)]
            let after = to[prefix..<(to.count - suffix)]
            let shared = Set(before).intersection(after)
            let candidatesBefore = before.indices.filter { shared.contains(before[$0]) }
            let candidatesAfter = after.indices.filter { shared.contains(after[$0]) }
            removals = Set(before.indices).subtracting(candidatesBefore)
            insertions = Set(after.indices).subtracting(candidatesAfter)
            let oldValues = candidatesBefore.map { before[$0] }
            let newValues = candidatesAfter.map { after[$0] }
            guard oldValues != newValues else { return }
            // The precise diff can take quadratic time when long collections share many reordered values.
            guard oldValues.count <= 4_000_000 / max(1, newValues.count)
                    || Self.canMatchWithFewEdits(oldValues, newValues) else {
                removals.formUnion(candidatesBefore)
                insertions.formUnion(candidatesAfter)
                if !withinLine {
                    let leftFirst = Self.matchInOrder(oldValues, newValues)
                    let rightFirst = Self.matchInOrder(newValues, oldValues)
                    let matches = leftFirst.count >= rightFirst.count ? leftFirst : rightFirst.map { ($0.1, $0.0) }
                    for (lhs, rhs) in matches {
                        removals.remove(candidatesBefore[lhs])
                        insertions.remove(candidatesAfter[rhs])
                    }
                }
                return
            }
            for change in newValues.difference(from: oldValues) {
                switch change {
                case .remove(let offset, _, _):
                    removals.insert(candidatesBefore[offset])
                case .insert(let offset, _, _):
                    insertions.insert(candidatesAfter[offset])
                }
            }
        }

        // A short edit script, even if suboptimal, bounds the cost of the precise diff.
        private static func canMatchWithFewEdits<Element: Equatable>(_ before: [Element], _ after: [Element]) -> Bool {
            var left = 0
            var right = 0
            var edits = 0
            while left < before.count, right < after.count, edits <= 64 {
                if before[left] == after[right] {
                    left += 1
                    right += 1
                } else if left + 1 < before.count, before[left + 1] == after[right] {
                    left += 1
                    edits += 1
                } else if right + 1 < after.count, before[left] == after[right + 1] {
                    right += 1
                    edits += 1
                } else {
                    left += 1
                    right += 1
                    edits += 2
                }
            }
            return edits + (before.count - left) + (after.count - right) <= 64
        }

        private static func matchInOrder<Element: Hashable>(_ before: [Element], _ after: [Element]) -> [(Int, Int)] {
            var positions: [Element: [Int]] = [:]
            for index in after.indices.reversed() {
                positions[after[index], default: []].append(index)
            }
            var matches: [(Int, Int)] = []
            var next = 0
            for (index, value) in before.enumerated() {
                while let candidate = positions[value]?.last, candidate < next {
                    positions[value]?.removeLast()
                }
                if let match = positions[value]?.popLast() {
                    matches.append((index, match))
                    next = match + 1
                }
            }
            return matches
        }
    }
}

private extension Set<Int> {
    func endOfRun(startingAt offset: Int) -> Int {
        var end = offset
        while contains(end) { end += 1 }
        return end
    }
}
