// Tests for the clipboard demonstration's clock and its choice of arrangement.

import CoreGraphics
import Foundation
import Testing

@testable import Uttrflow

/// The arrangement is settled from the width alone, so no frame of the animation has to measure anything.
@Suite("The clipboard demonstration's arrangement")
struct ClipboardDemonstrationArrangementTests {
    /// Padding both sides, the gap, the document, and the narrowest the words may be beside it.
    private let threshold: CGFloat = 17 * 2 + 22 + 400 + 360

    @Test("is built from the dimensions Docs/app-main-window.md states, and is 816 points wide")
    func theStatedDimensions() {
        #expect(ClipboardDemonstrationMetrics.padding == 17)
        #expect(ClipboardDemonstrationMetrics.columnSpacing == 22)
        #expect(ClipboardDemonstrationMetrics.documentWidth == 400)
        #expect(ClipboardDemonstrationMetrics.stageHeight == 172)
        #expect(ClipboardDemonstrationMetrics.explanationMinimumWidth == 360)
        #expect(ClipboardDemonstrationMetrics.explanationMaximumWidth == 460)
        #expect(threshold == 816)
    }

    @Test("stands side by side as soon as the words have their narrowest room")
    func sideBySideAtTheThreshold() {
        let arrangement = ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: threshold)

        #expect(arrangement == .sideBySide(explanationWidth: 360))
    }

    @Test("stacks one point below it")
    func stacksBelowTheThreshold() {
        let arrangement = ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: threshold - 1)

        #expect(arrangement == .stacked)
    }

    @Test("stacks at the minimum window, where reserving the document leaves too little for the words")
    func stacksAtTheMinimumWindow() {
        #expect(ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: 700) == .stacked)
    }

    @Test("stacks before it has been offered a width, rather than guessing one")
    func stacksBeforeItIsMeasured() {
        #expect(ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: 0) == .stacked)
    }

    @Test("never lets the words run wider than is comfortable to read")
    func wordsStopAtTheirMaximum() {
        for width in stride(from: threshold, through: 3000, by: 37.0) {
            guard
                case .sideBySide(let explanationWidth) =
                    ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: width)
            else {
                Issue.record("\(width) points should stand side by side")
                continue
            }
            #expect(explanationWidth <= 460)
            #expect(explanationWidth >= 360)
        }
    }

    @Test("always leaves the document its full width, so the pasted line never wraps")
    func theDocumentKeepsItsWidth() {
        for width in stride(from: threshold, through: 3000, by: 37.0) {
            guard
                case .sideBySide(let explanationWidth) =
                    ClipboardDemonstrationMetrics.arrangement(forOfferedWidth: width)
            else { continue }
            let used = 17 * 2 + explanationWidth + 22 + 400
            #expect(used <= width)
        }
    }
}

/// `ViewThatFits` and a clock are what #100 is about: inside one it is slow, outside one it freezes.
@Suite("The clipboard demonstration's structure")
struct ClipboardDemonstrationStructureTests {
    private var source: String {
        get throws {
            let card = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/Uttrflow/Main/ClipboardDemonstration.swift")
            return try String(contentsOf: card, encoding: .utf8)
        }
    }

    @Test("measures nothing per frame: no ViewThatFits anywhere near the clock")
    func noViewThatFits() throws {
        #expect(!(try source.contains("ViewThatFits")))
    }

    @Test("keeps exactly one clock, and not one per candidate arrangement")
    func oneTimeline() throws {
        #expect(try source.components(separatedBy: "TimelineView").count - 1 == 1)
    }
}

/// The card's whole job is to move, so these say the clock still drives it frame by frame.
@Suite("The clipboard demonstration's clock")
struct ClipboardDemonstrationPhaseTests {
    private func phase(at t: Double) -> ClipboardDemonstrationPhase {
        .at(Date(timeIntervalSinceReferenceDate: t))
    }

    @Test("changes from one display frame to the next while the panel is arriving")
    func movesBetweenAdjacentFrames() {
        #expect(phase(at: 1.5) != phase(at: 1.5 + 1.0 / 120.0))
    }

    @Test("changes from one display frame to the next while the words are landing")
    func movesWhileTyping() {
        #expect(phase(at: 5.2) != phase(at: 5.2 + 1.0 / 120.0))
    }

    @Test("draws hundreds of distinct frames over one loop, which is what a redraw is for")
    func aLoopIsNotAStill() {
        var seen = Set<Double>()
        for step in 0..<960 {
            let moment = phase(at: Double(step) / 120.0)
            seen.insert(moment.panel + moment.typed + moment.highlight + Double(moment.selected))
        }

        #expect(seen.count > 200)
    }

    @Test("tells the whole story: keys, panel, a walk down the rows, return, then the words arriving")
    func theStoryInOrder() {
        #expect(phase(at: 0.5).panel == 0)
        #expect(phase(at: 1.5).keysAreDown)
        #expect(phase(at: 2.2).panel == 1)
        #expect(phase(at: 2.2).selected == 0)
        #expect(phase(at: 2.8).selected == 1)
        #expect(phase(at: 3.5).selected == 2)
        #expect(phase(at: 4.1).returnIsDown)
        #expect(phase(at: 4.95).panel == 0)
        #expect(phase(at: 5.9).typed == 1)
    }

    @Test("repeats every eight seconds, so it is a loop rather than a run")
    func itLoops() {
        for t in stride(from: 0.0, to: 8.0, by: 0.13) {
            let first = phase(at: t)
            let next = phase(at: t + ClipboardDemonstrationPhase.loop)
            #expect(first.keysAreDown == next.keysAreDown)
            #expect(first.returnIsDown == next.returnIsDown)
            #expect(first.selected == next.selected)
            #expect(abs(first.panel - next.panel) < 1e-9)
            #expect(abs(first.highlight - next.highlight) < 1e-9)
            #expect(abs(first.typed - next.typed) < 1e-9)
        }
    }
}

/// The clock wakes when the drawing changes rather than on every display frame, and misses no change.
@Suite("The clipboard demonstration's moments")
struct ClipboardDemonstrationMomentsTests {
    /// A loop boundary, since 800 is a whole number of eight-second loops.
    private let loopStart = Date(timeIntervalSinceReferenceDate: 800)

    /// As long as the address the demonstration types, "Flat 402, Example Residences, Bengaluru".
    private let typedLength = 39

    private func offsets(loops: Double, from start: Date? = nil) -> [Double] {
        let end = loopStart.addingTimeInterval(ClipboardDemonstrationPhase.loop * loops)
        return ClipboardDemonstrationMoments(from: start ?? loopStart, typedLength: typedLength)
            .prefix { $0 < end }
            .map { $0.timeIntervalSince(loopStart) }
    }

    /// Everything the view reads from a phase, with the typed line reduced to what is visible of it.
    private struct Drawn: Equatable {
        let phase: ClipboardDemonstrationPhase
        let length: Int

        static func == (lhs: Drawn, rhs: Drawn) -> Bool {
            lhs.phase.keysAreDown == rhs.phase.keysAreDown
                && lhs.phase.returnIsDown == rhs.phase.returnIsDown
                && lhs.phase.selected == rhs.phase.selected
                && lhs.phase.highlight == rhs.phase.highlight
                && lhs.phase.panel == rhs.phase.panel
                && lhs.phase.typedCount(of: lhs.length) == rhs.phase.typedCount(of: rhs.length)
                && lhs.phase.showsCaret == rhs.phase.showsCaret
        }
    }

    private func drawn(at offset: Double) -> Drawn {
        Drawn(phase: .at(loopStart.addingTimeInterval(offset)), length: typedLength)
    }

    @Test("draws what the clock would show at every instant, give or take one frame of motion or the nudge")
    func missesNoChange() {
        let moments = offsets(loops: 1)
        let nudge = ClipboardDemonstrationMoments.nudge
        let boundaries =
            ClipboardDemonstrationMoments.steps
            + ClipboardDemonstrationPhase.characterArrivals(length: typedLength)
        var latest = 0
        var compared = 0
        for t in stride(from: 0.0, to: ClipboardDemonstrationPhase.loop, by: 0.0007) {
            while latest + 1 < moments.count && moments[latest + 1] <= t { latest += 1 }
            if boundaries.contains(where: { (0..<nudge).contains(t - $0) }) { continue }
            if ClipboardDemonstrationMoments.motion.contains(where: { $0.contains(t) }) {
                #expect(t - moments[latest] <= ClipboardDemonstrationMoments.frame + 1e-9)
            } else {
                #expect(drawn(at: moments[latest]) == drawn(at: t), "at \(t) seconds into the loop")
                compared += 1
            }
        }

        #expect(compared > 8000)
    }

    @Test("wakes under a quarter as often as a 120 Hz display redraws over one loop")
    func wakesLessThanEveryFrame() {
        let everyFrame = ClipboardDemonstrationPhase.loop * 120

        #expect(Double(offsets(loops: 1).count) < everyFrame * 0.25)
    }

    @Test("still wakes at the display's rate while the panel rises and goes")
    func movesSmoothly() {
        let moments = offsets(loops: 1)
        for range in [1.0...1.9, 4.3...4.9] {
            let moving = moments.filter { range.contains($0) }
            let gaps = zip(moving, moving.dropFirst()).map { $1 - $0 }
            #expect(moving.count > 60)
            #expect(gaps.allSatisfy { $0 <= ClipboardDemonstrationMoments.frame + 1e-9 })
        }
    }

    @Test("wakes once for each character of the typed line, not once a frame")
    func wakesPerCharacter() {
        let typing = offsets(loops: 1).filter { (4.9..<5.9).contains($0) }

        #expect(typing.count == typedLength + 1)
    }

    @Test("moves forward across loop boundaries, from a start part-way through a loop")
    func keepsGoingAcrossLoops() {
        let moments = offsets(loops: 3, from: loopStart.addingTimeInterval(5.95))

        #expect(abs((moments.first ?? 0) - 5.95) < 1e-9)
        #expect(zip(moments, moments.dropFirst()).allSatisfy { $0 < $1 })
        #expect(moments.contains { $0 > 16 + 5 })
    }

    @Test("gives a still card its one instant and nothing after it")
    func aStillCardWakesOnce() {
        let moments = ClipboardDemonstrationMoments(from: loopStart, typedLength: 39, isStill: true)

        #expect(Array(moments) == [loopStart])
    }

    @Test("rests on the panel open with the address row chosen, not on a blank document")
    func restsOnTheChosenRow() {
        let resting = ClipboardDemonstrationPhase.resting

        #expect(resting.panel == 1)
        #expect(resting.selected == 2)
        #expect(resting.highlight == 1)
        #expect(resting.typedCount(of: typedLength) == 0)
        #expect(!resting.showsCaret)
        #expect(!resting.keysAreDown && !resting.returnIsDown)
    }

    @Test("puts each character's arrival where the clock first shows it")
    func arrivalsMatchTheClock() {
        let arrivals = ClipboardDemonstrationPhase.characterArrivals(length: typedLength)

        #expect(arrivals.count == typedLength)
        for (index, arrival) in arrivals.enumerated() {
            let before = ClipboardDemonstrationPhase.at(loopStart.addingTimeInterval(arrival - 1e-6))
            let after = ClipboardDemonstrationPhase.at(loopStart.addingTimeInterval(arrival + 1e-6))
            #expect(before.typedCount(of: typedLength) == index)
            #expect(after.typedCount(of: typedLength) == index + 1)
        }
    }

    @Test("has no arrivals for an empty line, and shows the caret only while words arrive")
    func emptyLineAndCaret() {
        #expect(ClipboardDemonstrationPhase.characterArrivals(length: 0).isEmpty)
        #expect(!ClipboardDemonstrationPhase.at(loopStart.addingTimeInterval(4.5)).showsCaret)
        #expect(ClipboardDemonstrationPhase.at(loopStart.addingTimeInterval(5.2)).showsCaret)
        #expect(!ClipboardDemonstrationPhase.at(loopStart.addingTimeInterval(6.5)).showsCaret)
    }
}
