import Testing
@testable import MindSpaceCore

@Test("an existing thought pushes another thought softly when dragged into contact")
func draggedThoughtPushesAnotherThought() {
    let engine = ThoughtPhysicsEngine()
    let bounds = ThoughtBounds(minX: 0, minY: 0, maxX: 600, maxY: 400)
    let task = ThoughtBody(id: "task_one", center: ThoughtPoint(x: 160, y: 200), radius: 50)
    let idea = ThoughtBody(id: "task_idea", center: ThoughtPoint(x: 270, y: 200), radius: 50)

    let frame = engine.drag(
        objectID: task.id,
        to: ThoughtPoint(x: 210, y: 200),
        movement: ThoughtVector(dx: 50, dy: 0),
        bodies: [task, idea],
        bounds: bounds
    )

    let movedTask = frame.bodies.first { $0.id == task.id }
    let movedIdea = frame.bodies.first { $0.id == idea.id }
    #expect(movedTask?.center == ThoughtPoint(x: 210, y: 200))
    #expect((movedIdea?.center.x ?? 0) > idea.center.x)
    #expect((movedIdea?.velocity.dx ?? 0) > 0)
    #expect(frame.contactIDs == [task.id, idea.id])
}

@Test("free-moving thoughts slow down and remain inside safe canvas bounds")
func movingThoughtsSettleWithinBounds() {
    let engine = ThoughtPhysicsEngine()
    let bounds = ThoughtBounds(minX: 0, minY: 0, maxX: 500, maxY: 300)
    var frame = ThoughtPhysicsFrame(
        bodies: [
            ThoughtBody(
                id: "project_one",
                center: ThoughtPoint(x: 445, y: 150),
                radius: 50,
                velocity: ThoughtVector(dx: 70, dy: 0)
            ),
        ],
        contactIDs: []
    )

    for _ in 0..<180 {
        frame = engine.step(bodies: frame.bodies, deltaTime: 1.0 / 60.0, bounds: bounds)
    }

    let project = frame.bodies[0]
    #expect(project.center.x <= 450)
    #expect(project.center.x >= 50)
    #expect(project.velocity == .zero)
}
