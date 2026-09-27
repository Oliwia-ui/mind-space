import Foundation

public struct ThoughtPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct ThoughtVector: Equatable, Sendable {
    public var dx: Double
    public var dy: Double

    public static let zero = ThoughtVector(dx: 0, dy: 0)

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
}

public struct ThoughtBounds: Equatable, Sendable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }
}

public struct ThoughtBody: Equatable, Sendable {
    public let id: String
    public var center: ThoughtPoint
    public var radius: Double
    public var velocity: ThoughtVector

    public init(id: String, center: ThoughtPoint, radius: Double, velocity: ThoughtVector = .zero) {
        self.id = id
        self.center = center
        self.radius = radius
        self.velocity = velocity
    }
}

public struct ThoughtPhysicsFrame: Equatable, Sendable {
    public var bodies: [ThoughtBody]
    public var contactIDs: Set<String>

    public init(bodies: [ThoughtBody], contactIDs: Set<String>) {
        self.bodies = bodies
        self.contactIDs = contactIDs
    }
}

public struct ThoughtPhysicsEngine: Sendable {
    private let maximumSpeed: Double
    private let settleSpeed: Double
    private let collisionIterations: Int

    public init(maximumSpeed: Double = 54, settleSpeed: Double = 1.5, collisionIterations: Int = 2) {
        self.maximumSpeed = maximumSpeed
        self.settleSpeed = settleSpeed
        self.collisionIterations = collisionIterations
    }

    public func drag(
        objectID: String,
        to proposedCenter: ThoughtPoint,
        movement: ThoughtVector,
        bodies: [ThoughtBody],
        bounds: ThoughtBounds
    ) -> ThoughtPhysicsFrame {
        var bodies = bodies
        guard let pusherIndex = bodies.firstIndex(where: { $0.id == objectID }) else {
            return ThoughtPhysicsFrame(bodies: bodies, contactIDs: [])
        }

        bodies[pusherIndex].center = clamped(proposedCenter, radius: bodies[pusherIndex].radius, bounds: bounds)
        bodies[pusherIndex].velocity = .zero
        var contacts: Set<String> = []

        for _ in 0..<1 {
            for firstIndex in bodies.indices {
                for secondIndex in bodies.indices where secondIndex > firstIndex {
                    let collision = overlap(bodies[firstIndex], bodies[secondIndex])
                    guard collision.depth > 0 else { continue }
                    contacts.insert(bodies[firstIndex].id)
                    contacts.insert(bodies[secondIndex].id)

                    if firstIndex == pusherIndex || secondIndex == pusherIndex {
                        let pushedIndex = firstIndex == pusherIndex ? secondIndex : firstIndex
                        let direction = firstIndex == pusherIndex
                            ? collision.normal
                            : ThoughtVector(dx: -collision.normal.dx, dy: -collision.normal.dy)
                        bodies[pushedIndex].center.x += direction.dx * collision.depth * 0.18
                        bodies[pushedIndex].center.y += direction.dy * collision.depth * 0.18
                        bodies[pushedIndex].center = clamped(
                            bodies[pushedIndex].center,
                            radius: bodies[pushedIndex].radius,
                            bounds: bounds
                        )
                        let movementDirection = normalized(movement, fallback: direction)
                        let pushSpeed = min(maximumSpeed, max(8, magnitude(movement) * 0.18))
                        bodies[pushedIndex].velocity = limited(
                            ThoughtVector(
                                dx: movementDirection.dx * pushSpeed + direction.dx * 5,
                                dy: movementDirection.dy * pushSpeed + direction.dy * 5
                            )
                        )
                    } else {
                        var first = bodies[firstIndex]
                        var second = bodies[secondIndex]
                        separate(&first, &second, collision: collision, bounds: bounds)
                        bodies[firstIndex] = first
                        bodies[secondIndex] = second
                    }
                }
            }
        }

        bodies[pusherIndex].center = clamped(proposedCenter, radius: bodies[pusherIndex].radius, bounds: bounds)
        bodies[pusherIndex].velocity = .zero
        return ThoughtPhysicsFrame(bodies: bodies, contactIDs: contacts)
    }

    public func step(bodies: [ThoughtBody], deltaTime: Double, bounds: ThoughtBounds) -> ThoughtPhysicsFrame {
        let timeStep = min(max(deltaTime, 0), 1.0 / 20.0)
        var bodies = bodies
        var contacts: Set<String> = []

        for index in bodies.indices {
            bodies[index].center.x += bodies[index].velocity.dx * timeStep
            bodies[index].center.y += bodies[index].velocity.dy * timeStep
            let unclamped = bodies[index].center
            bodies[index].center = clamped(unclamped, radius: bodies[index].radius, bounds: bounds)
            if bodies[index].center.x != unclamped.x { bodies[index].velocity.dx = 0 }
            if bodies[index].center.y != unclamped.y { bodies[index].velocity.dy = 0 }
        }

        for _ in 0..<collisionIterations {
            for firstIndex in bodies.indices {
                for secondIndex in bodies.indices where secondIndex > firstIndex {
                    let collision = overlap(bodies[firstIndex], bodies[secondIndex])
                    guard collision.depth > 0 else { continue }
                    contacts.insert(bodies[firstIndex].id)
                    contacts.insert(bodies[secondIndex].id)
                    var first = bodies[firstIndex]
                    var second = bodies[secondIndex]
                    separate(&first, &second, collision: collision, bounds: bounds)
                    bodies[firstIndex] = first
                    bodies[secondIndex] = second
                }
            }
        }

        let damping = pow(0.18, timeStep)
        for index in bodies.indices {
            bodies[index].velocity.dx *= damping
            bodies[index].velocity.dy *= damping
            bodies[index].velocity = limited(bodies[index].velocity)
            if magnitude(bodies[index].velocity) < settleSpeed {
                bodies[index].velocity = .zero
            }
        }

        return ThoughtPhysicsFrame(bodies: bodies, contactIDs: contacts)
    }

    public func isSettled(_ bodies: [ThoughtBody]) -> Bool {
        bodies.allSatisfy { $0.velocity == .zero }
    }

    private func overlap(_ first: ThoughtBody, _ second: ThoughtBody) -> (normal: ThoughtVector, depth: Double) {
        let delta = ThoughtVector(dx: second.center.x - first.center.x, dy: second.center.y - first.center.y)
        let distance = magnitude(delta)
        let depth = first.radius + second.radius - distance
        let normal = distance > 0.001 ? ThoughtVector(dx: delta.dx / distance, dy: delta.dy / distance) : ThoughtVector(dx: 1, dy: 0)
        return (normal, max(0, depth))
    }

    private func separate(
        _ first: inout ThoughtBody,
        _ second: inout ThoughtBody,
        collision: (normal: ThoughtVector, depth: Double),
        bounds: ThoughtBounds
    ) {
        let correction = collision.depth * 0.10
        first.center.x -= collision.normal.dx * correction
        first.center.y -= collision.normal.dy * correction
        second.center.x += collision.normal.dx * correction
        second.center.y += collision.normal.dy * correction
        first.center = clamped(first.center, radius: first.radius, bounds: bounds)
        second.center = clamped(second.center, radius: second.radius, bounds: bounds)

        let relativeSpeed = (first.velocity.dx - second.velocity.dx) * collision.normal.dx
            + (first.velocity.dy - second.velocity.dy) * collision.normal.dy
        let impulse = max(0, relativeSpeed) * 0.22
        first.velocity.dx -= collision.normal.dx * impulse
        first.velocity.dy -= collision.normal.dy * impulse
        second.velocity.dx += collision.normal.dx * impulse
        second.velocity.dy += collision.normal.dy * impulse
    }

    private func clamped(_ point: ThoughtPoint, radius: Double, bounds: ThoughtBounds) -> ThoughtPoint {
        ThoughtPoint(
            x: min(max(point.x, bounds.minX + radius), bounds.maxX - radius),
            y: min(max(point.y, bounds.minY + radius), bounds.maxY - radius)
        )
    }

    private func normalized(_ vector: ThoughtVector, fallback: ThoughtVector) -> ThoughtVector {
        let length = magnitude(vector)
        guard length > 0.001 else { return fallback }
        return ThoughtVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    private func limited(_ vector: ThoughtVector) -> ThoughtVector {
        let speed = magnitude(vector)
        guard speed > maximumSpeed else { return vector }
        let scale = maximumSpeed / speed
        return ThoughtVector(dx: vector.dx * scale, dy: vector.dy * scale)
    }

    private func magnitude(_ vector: ThoughtVector) -> Double {
        sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    }
}
