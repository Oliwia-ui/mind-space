import Foundation

public struct ThoughtGroupPreview: Equatable, Sendable {
    public let draggedID: String
    public let targetID: String
    public let progress: Double
    public let isReady: Bool

    public init(draggedID: String, targetID: String, progress: Double, isReady: Bool) {
        self.draggedID = draggedID
        self.targetID = targetID
        self.progress = progress
        self.isReady = isReady
    }
}

public struct ThoughtGroupPair: Equatable, Sendable {
    public let firstID: String
    public let secondID: String

    public init(firstID: String, secondID: String) {
        self.firstID = firstID
        self.secondID = secondID
    }
}

public struct ThoughtGroupingEngine: Sendable {
    private struct Candidate: Sendable {
        let draggedID: String
        let targetID: String
        let beganAt: Date
    }

    private let holdDuration: TimeInterval
    private let contactDepthRatio: Double
    private var candidate: Candidate?

    public init(holdDuration: TimeInterval = 0.7, contactDepthRatio: Double = 0.92) {
        self.holdDuration = max(holdDuration, 0.1)
        self.contactDepthRatio = min(max(contactDepthRatio, 0.5), 1)
    }

    public mutating func update(
        draggedID: String,
        bodies: [ThoughtBody],
        at date: Date
    ) -> ThoughtGroupPreview? {
        guard let targetID = closestGroupingTarget(to: draggedID, bodies: bodies) else {
            candidate = nil
            return nil
        }

        if candidate?.draggedID != draggedID || candidate?.targetID != targetID {
            candidate = Candidate(draggedID: draggedID, targetID: targetID, beganAt: date)
        }

        guard let candidate else { return nil }
        let progress = min(max(date.timeIntervalSince(candidate.beganAt) / holdDuration, 0), 1)
        return ThoughtGroupPreview(
            draggedID: draggedID,
            targetID: targetID,
            progress: progress,
            isReady: progress >= 1
        )
    }

    public mutating func finish(
        draggedID: String,
        bodies: [ThoughtBody],
        at date: Date
    ) -> ThoughtGroupPair? {
        defer { candidate = nil }
        guard let preview = update(draggedID: draggedID, bodies: bodies, at: date), preview.isReady else {
            return nil
        }
        return ThoughtGroupPair(firstID: draggedID, secondID: preview.targetID)
    }

    public mutating func cancel() {
        candidate = nil
    }

    private func closestGroupingTarget(to draggedID: String, bodies: [ThoughtBody]) -> String? {
        guard let dragged = bodies.first(where: { $0.id == draggedID }) else { return nil }
        return bodies
            .filter { body in
                guard body.id != draggedID else { return false }
                let distance = hypot(body.center.x - dragged.center.x, body.center.y - dragged.center.y)
                return distance <= (dragged.radius + body.radius) * contactDepthRatio
            }
            .min { first, second in
                distance(from: dragged, to: first) < distance(from: dragged, to: second)
            }?
            .id
    }

    private func distance(from first: ThoughtBody, to second: ThoughtBody) -> Double {
        hypot(second.center.x - first.center.x, second.center.y - first.center.y)
    }
}
