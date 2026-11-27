import XCTest
@testable import Kipple

final class TextComparisonTests: XCTestCase {
    func testAlignsInsertionsAndRemovalsWithoutRenumberingEitherSide() {
        let comparison = TextComparison(
            clipboard: "見出し\n削除\n共通\n最後",
            selection: "見出し\n共通\n追加\n最後"
        )
        XCTAssertEqual(comparison.differences.map(\.row), [1, 3])
        XCTAssertEqual(comparison.rows.map(\.kind), [.equal, .removed, .equal, .inserted, .equal])
        XCTAssertEqual(comparison.rows.map { $0.left?.number }, [1, 2, 3, nil, 4])
        XCTAssertEqual(comparison.rows.map { $0.right?.number }, [1, nil, 2, 3, 4])
    }

    func testNavigatesToEachReplacementWithinTheSameLine() throws {
        let comparison = TextComparison(clipboard: "赤 と 👩🏽‍💻 を選ぶ", selection: "青 と 👩🏻‍🎨 を選ぶ")
        let row = try XCTUnwrap(comparison.rows.first)
        let left = try XCTUnwrap(row.left)
        let right = try XCTUnwrap(row.right)
        XCTAssertEqual(comparison.differences.map(\.row), [0, 0])
        XCTAssertEqual(left.changes.map(\.difference), [0, 1])
        XCTAssertEqual(right.changes.map(\.difference), [0, 1])
        XCTAssertEqual(left.changes.map { String(left.text[$0.range]) }, ["赤", "👩🏽‍💻"])
        XCTAssertEqual(right.changes.map { String(right.text[$0.range]) }, ["青", "👩🏻‍🎨"])
    }

    func testNavigatesOneSidedEditsAndReplacementsInOrderWithinTheSameLine() throws {
        let common = "［左右に共通する長めの見出し］"
        let comparison = TextComparison(
            clipboard: "削除\(common)赤\(common)", selection: "\(common)青\(common)追記"
        )
        let row = try XCTUnwrap(comparison.rows.first)
        let left = try XCTUnwrap(row.left)
        let right = try XCTUnwrap(row.right)
        XCTAssertEqual(comparison.differences.map(\.row), [0, 0, 0])
        XCTAssertEqual(left.changes.map(\.difference), [0, 1])
        XCTAssertEqual(right.changes.map(\.difference), [1, 2])
        XCTAssertEqual(left.changes.map { String(left.text[$0.range]) }, ["削除", "赤"])
        XCTAssertEqual(right.changes.map { String(right.text[$0.range]) }, ["青", "追記"])
    }

    func testNavigatesDifferencesInDisplayedRowOrderAfterAlignment() {
        let comparison = TextComparison(clipboard: "b\n\nr2👩🏽‍💻3\n3 👩🏽‍💻2deb", selection: "r ea\nr ")
        XCTAssertEqual(comparison.differences.map(\.row), [0, 2, 2, 3])
        XCTAssertEqual(comparison.differences.map(\.id), [0, 1, 3, 2])
        for difference in comparison.differences {
            let row = comparison.rows[difference.row]
            XCTAssertTrue(row.left?.containsDifference(difference.id) == true
                          || row.right?.containsDifference(difference.id) == true)
        }
    }

    func testPreservesBlankLinesAndRepeatedText() {
        let comparison = TextComparison(clipboard: "項目\n\n項目\n末尾", selection: "項目\n項目\n追記\n末尾\n")
        XCTAssertEqual(comparison.rows.compactMap { $0.left?.text }, ["項目", "", "項目", "末尾"])
        XCTAssertEqual(comparison.rows.compactMap { $0.right?.text }, ["項目", "項目", "追記", "末尾", ""])
        XCTAssertEqual(comparison.differences.map(\.row), [1, 3, 4])
        XCTAssertEqual(comparison.rows.first { $0.right?.text == "末尾" }?.right?.lineBreakDifference, 2)
    }

    func testTreatsLineEndingsConsistentlyAndKeepsWhitespaceEdits() {
        let same = TextComparison(clipboard: "行1\r\n行2\r\n", selection: "行1\n行2\n")
        XCTAssertTrue(same.differences.isEmpty)
        let different = TextComparison(clipboard: "行1\n行2", selection: "行1\n 行2")
        XCTAssertEqual(different.differences.map(\.row), [1])
    }

    func testSplittingAndJoiningALineMarksOnlyTheLineBreak() {
        let oneLine = "案内\n東京に行きます\n以上"
        let twoLines = "案内\n東京に\n行きます\n以上"
        let split = TextComparison(clipboard: oneLine, selection: twoLines)
        XCTAssertEqual(split.differences.map(\.row), [1])
        XCTAssertEqual(split.rows.map(\.kind), [.equal, .replaced, .equal, .equal])
        XCTAssertEqual(split.rows.map { $0.left?.number }, [1, 2, nil, 3])
        XCTAssertEqual(split.rows.map { $0.right?.number }, [1, 2, 3, 4])
        XCTAssertEqual(split.rows.compactMap(\.right).filter(\.lineBreakChanged).map(\.number), [2])
        XCTAssertTrue(split.rows.compactMap(\.left).allSatisfy { !$0.hasChanges })
        XCTAssertTrue(split.rows.compactMap(\.right).allSatisfy { $0.changes.isEmpty })

        let joined = TextComparison(clipboard: twoLines, selection: oneLine)
        XCTAssertEqual(joined.differences.map(\.row), [1])
        XCTAssertEqual(joined.rows.map { $0.right?.number }, [1, 2, nil, 3])
        XCTAssertEqual(joined.rows.compactMap(\.left).filter(\.lineBreakChanged).map(\.number), [2])
        XCTAssertTrue(joined.rows.compactMap(\.left).allSatisfy { $0.changes.isEmpty })
        XCTAssertTrue(joined.rows.compactMap(\.right).allSatisfy { !$0.hasChanges })
    }

    func testTracksAChangedLineBreakSeparatelyFromTextEdits() throws {
        let comparison = TextComparison(
            clipboard: "開始は10時です。受付は玄関です。",
            selection: "開始は11時です。\n受付は玄関です。"
        )
        let first = try XCTUnwrap(comparison.rows.first)
        let left = try XCTUnwrap(first.left)
        let right = try XCTUnwrap(first.right)
        XCTAssertEqual(comparison.differences.map(\.row), [0, 0])
        XCTAssertEqual(left.changes.map { String(left.text[$0.range]) }, ["0"])
        XCTAssertEqual(right.changes.map { String(right.text[$0.range]) }, ["1"])
        XCTAssertEqual(right.changes.map(\.difference), [0])
        XCTAssertEqual(right.lineBreakDifference, 1)
        XCTAssertTrue(right.lineBreakChanged)
        XCTAssertEqual(comparison.rows.last?.kind, .equal)
        XCTAssertEqual(comparison.rows.last?.right?.text, "受付は玄関です。")
    }

    func testMovingTheLineBreakDoesNotHighlightTheWordAcrossIt() {
        let comparison = TextComparison(
            clipboard: "案内\n集合は\n東京駅です\n最後",
            selection: "案内\n集合は東京\n駅です\n最後"
        )
        let left = comparison.rows.compactMap(\.left)
        let right = comparison.rows.compactMap(\.right)
        XCTAssertTrue(left.allSatisfy { $0.changes.isEmpty })
        XCTAssertTrue(right.allSatisfy { $0.changes.isEmpty })
        XCTAssertEqual(left.filter(\.lineBreakChanged).map(\.number), [2])
        XCTAssertEqual(right.filter(\.lineBreakChanged).map(\.number), [2])
        XCTAssertEqual(comparison.differences.map(\.row), [1, 1])
        XCTAssertEqual(left.compactMap(\.lineBreakDifference), [0])
        XCTAssertEqual(right.compactMap(\.lineBreakDifference), [1])
    }

    func testMarkingAnEndOfTextNewlineKeepsTheTextAndFinalEmptyLine() {
        let comparison = TextComparison(clipboard: "本文", selection: "本文\n")
        XCTAssertEqual(comparison.differences.map(\.row), [0])
        XCTAssertEqual(comparison.rows.map(\.kind), [.replaced, .equal])
        XCTAssertEqual(comparison.rows.compactMap(\.right).map(\.text), ["本文", ""])
        XCTAssertTrue(comparison.rows[0].right?.lineBreakChanged == true)
        XCTAssertTrue(comparison.rows[0].left?.hasChanges == false)
    }

    func testKeepsRelatedLinesTogetherAroundAnInsertionOrRemoval() {
        let before = "案内\n開始は10時です。\n受付は玄関です。\n以上"
        let after = "案内\nオンライン開催\n録画あり\n開始は11時です。\n受付は会議室です。\n以上"
        let insertion = TextComparison(clipboard: before, selection: after)
        XCTAssertEqual(insertion.rows.map(\.kind), [.equal, .inserted, .inserted, .replaced, .replaced, .equal])
        XCTAssertEqual(insertion.rows.map { $0.left?.number }, [1, nil, nil, 2, 3, 4])
        let removal = TextComparison(clipboard: after, selection: before)
        XCTAssertEqual(removal.rows.map(\.kind), [.equal, .removed, .removed, .replaced, .replaced, .equal])
        XCTAssertEqual(removal.rows.map { $0.right?.number }, [1, nil, nil, 2, 3, 4])
    }

    func testHighlightsOnlyTheEditsAtBothEndsOfALongLine() throws {
        let middle = String(repeating: "x", count: 10_000)
        let comparison = TextComparison(clipboard: "A\(middle)B", selection: "B\(middle)A")
        let left = try XCTUnwrap(comparison.rows.first?.left)
        let right = try XCTUnwrap(comparison.rows.first?.right)
        XCTAssertEqual(comparison.differences.map(\.row), [0, 0])
        XCTAssertEqual(left.changes.map(\.difference), [0, 1])
        XCTAssertEqual(right.changes.map(\.difference), [0, 1])
        XCTAssertEqual(left.changes.map { String(left.text[$0.range]) }, ["A", "B"])
        XCTAssertEqual(right.changes.map { String(right.text[$0.range]) }, ["B", "A"])
    }

    func testPreservesBothSequencesWhenReorderingManyRepeatedLines() {
        let count = 3_000
        let first = String(repeating: "Red team\n", count: count / 10)
        let second = String(repeating: "Blue team\n", count: count)
        let comparison = TextComparison(clipboard: first + second, selection: second + first)
        XCTAssertEqual(comparison.rows.compactMap { $0.left?.text }.joined(separator: "\n"), first + second)
        XCTAssertEqual(comparison.rows.compactMap { $0.right?.text }.joined(separator: "\n"), second + first)
        XCTAssertEqual(comparison.rows.filter { $0.kind == .equal }.count, count + 1)
    }

    func testPlacementUsesTheSourceDisplayEvenWhenThePointerIsElsewhere() {
        let left = CGRect(x: -1280, y: 0, width: 1280, height: 800)
        let right = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let placement = TextComparisonWindowPlacement(
            sourceFrame: CGRect(x: -650, y: 100, width: 850, height: 550),
            pointer: CGPoint(x: 200, y: 300)
        )

        XCTAssertEqual(placement.screenIndex(in: [right, left]), 1)
        let frame = placement.frame(size: CGSize(width: 800, height: 460), in: left)
        XCTAssertEqual(frame, CGRect(x: -800, y: 145, width: 800, height: 460))
    }

    func testPlacementUsesPointerDisplayWhenSourceWindowIsUnavailableAndFitsToVisibleFrame() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let above = CGRect(x: 0, y: 900, width: 1280, height: 800)
        let visible = above.insetBy(dx: 0, dy: 25)
        let placement = TextComparisonWindowPlacement(
            sourceFrame: CGRect(x: 1800, y: 0, width: 800, height: 460),
            pointer: CGPoint(x: 200, y: 1200)
        )

        XCTAssertEqual(placement.screenIndex(in: [main, above]), 1)
        XCTAssertEqual(placement.frame(size: CGSize(width: 1500, height: 820), in: visible), visible)
    }
}
