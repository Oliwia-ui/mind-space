import Foundation
import Testing
@testable import MindSpaceCore

@Test("a quick collision never confirms a visual group")
func quickCollisionDoesNotCreateGroup() {
    var engine = ThoughtGroupingEngine(holdDuration: 0.7)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let bodies = groupingBodies()

    let preview = engine.update(draggedID: "task_one", bodies: bodies, at: start)
    let result = engine.finish(
        draggedID: "task_one",
        bodies: bodies,
        at: start.addingTimeInterval(0.2)
    )

    #expect(preview?.targetID == "task_two")
    #expect(preview?.isReady == false)
    #expect(result == nil)
}

@Test("holding two thoughts together confirms the same stable objects")
func deliberateHoldConfirmsGroup() {
    var engine = ThoughtGroupingEngine(holdDuration: 0.7)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let bodies = groupingBodies()

    _ = engine.update(draggedID: "task_one", bodies: bodies, at: start)
    let preview = engine.update(
        draggedID: "task_one",
        bodies: bodies,
        at: start.addingTimeInterval(0.75)
    )
    let result = engine.finish(
        draggedID: "task_one",
        bodies: bodies,
        at: start.addingTimeInterval(0.75)
    )

    #expect(preview?.isReady == true)
    #expect(preview?.progress == 1)
    #expect(result == ThoughtGroupPair(firstID: "task_one", secondID: "task_two"))
}

@Test("leaving contact clears the grouping preview")
func leavingContactClearsPreview() {
    var engine = ThoughtGroupingEngine(holdDuration: 0.7)
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    _ = engine.update(draggedID: "task_one", bodies: groupingBodies(), at: start)

    let separated = [
        ThoughtBody(id: "task_one", center: ThoughtPoint(x: 80, y: 100), radius: 30),
        ThoughtBody(id: "task_two", center: ThoughtPoint(x: 240, y: 100), radius: 30),
    ]

    #expect(engine.update(draggedID: "task_one", bodies: separated, at: start.addingTimeInterval(0.4)) == nil)
    #expect(engine.finish(draggedID: "task_one", bodies: separated, at: start.addingTimeInterval(1)) == nil)
}

private func groupingBodies() -> [ThoughtBody] {
    [
        ThoughtBody(id: "task_one", center: ThoughtPoint(x: 100, y: 100), radius: 30),
        ThoughtBody(id: "task_two", center: ThoughtPoint(x: 145, y: 100), radius: 30),
        ThoughtBody(id: "task_far", center: ThoughtPoint(x: 300, y: 300), radius: 30),
    ]
}
