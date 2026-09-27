import Foundation
import Testing

@testable import MindSpaceCore

@Test("drifting keeps every thought within a calm, reachable offset")
func driftStaysWithinCalmBounds() {
    let field = ThoughtDriftField(amplitude: 6)

    for time in stride(from: 0.0, through: 40.0, by: 0.25) {
        let offset = field.hoverOffset(forID: "task_a", at: time)
        #expect(abs(offset.x) <= 6.001)
        #expect(abs(offset.y) <= 6.001)
    }
}

@Test("drifting is deterministic per thought so saved positions stay stable")
func driftIsDeterministicPerThought() {
    let field = ThoughtDriftField(amplitude: 6)

    let first = field.hoverOffset(forID: "task_a", at: 12.5)
    let repeated = field.hoverOffset(forID: "task_a", at: 12.5)
    let other = field.hoverOffset(forID: "task_b", at: 12.5)

    #expect(first == repeated)
    #expect(first != other)
}

@Test("drifting actually moves a thought over time")
func driftMovesOverTime() {
    let field = ThoughtDriftField(amplitude: 6)

    let start = field.hoverOffset(forID: "task_a", at: 0)
    let later = field.hoverOffset(forID: "task_a", at: 3.5)

    #expect(start != later)
}

@Test("orbiting tasks stay evenly spread around their project")
func orbitSpreadsTasksAroundProject() {
    let field = ThoughtDriftField(amplitude: 6)
    let center = ThoughtPoint(x: 200, y: 150)

    let first = field.orbitPoint(around: center, radius: 90, index: 0, count: 3, at: 0)
    let second = field.orbitPoint(around: center, radius: 90, index: 1, count: 3, at: 0)

    let firstDistance = hypot(first.x - center.x, first.y - center.y)
    let secondDistance = hypot(second.x - center.x, second.y - center.y)

    #expect(abs(firstDistance - 90) < 0.001)
    #expect(abs(secondDistance - 90) < 0.001)
    #expect(first != second)
}
