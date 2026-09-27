import Foundation
import MindSpaceCore

@MainActor
final class MindSpacePhysicsController: ObservableObject {
    @Published private(set) var bodies: [ThoughtBody] = []
    @Published private(set) var contactIDs: Set<String> = []
    @Published private(set) var draggedObjectID: String?
    @Published private(set) var groupingPreview: ThoughtGroupPreview?
    @Published var errorMessage: String?

    private let repository: MindSpaceRepository
    private let engine = ThoughtPhysicsEngine()
    private var groupingEngine = ThoughtGroupingEngine()
    private var kinds: [String: MindSpaceObjectKind] = [:]
    private var storedPositions: [String: MindSpaceObjectPosition] = [:]
    private var bounds = ThoughtBounds(minX: 0, minY: 0, maxX: 1, maxY: 1)
    private var lastDragPoint: ThoughtPoint?
    private var timer: Timer?
    private var lastTickDate: Date?
    private var contactExpiry: [String: Date] = [:]
    private var groupingHoldTask: Task<Void, Never>?

    init(repository: MindSpaceRepository) throws {
        self.repository = repository
        storedPositions = Dictionary(
            uniqueKeysWithValues: try repository.objectPositions().map { (Self.key(id: $0.objectID, kind: $0.kind), $0) }
        )
    }

    func configure(defaultBodies: [ThoughtBody], kinds: [String: MindSpaceObjectKind], bounds: ThoughtBounds) {
        let priorBounds = self.bounds
        self.bounds = bounds
        self.kinds = kinds
        let existing = Dictionary(uniqueKeysWithValues: bodies.map { ($0.id, $0) })

        bodies = defaultBodies.map { defaultBody in
            if var body = existing[defaultBody.id] {
                body.radius = defaultBody.radius
                body.center = remapped(body.center, from: priorBounds, to: bounds, radius: body.radius)
                return body
            }
            guard let kind = kinds[defaultBody.id],
                  let stored = storedPositions[Self.key(id: defaultBody.id, kind: kind)] else {
                return defaultBody
            }
            var body = defaultBody
            body.center = point(normalizedX: stored.normalizedX, normalizedY: stored.normalizedY, bounds: bounds)
            return body
        }

        let frame = engine.step(bodies: bodies, deltaTime: 0, bounds: bounds)
        bodies = frame.bodies
    }

    func center(for objectID: String, fallback: ThoughtPoint) -> ThoughtPoint {
        bodies.first(where: { $0.id == objectID })?.center ?? fallback
    }

    func beginDragging(objectID: String, at point: ThoughtPoint) {
        timer?.invalidate()
        timer = nil
        draggedObjectID = objectID
        lastDragPoint = point
        groupingEngine.cancel()
        groupingPreview = nil
        groupingHoldTask?.cancel()
    }

    func drag(objectID: String, to point: ThoughtPoint) {
        if draggedObjectID != objectID {
            beginDragging(objectID: objectID, at: point)
        }
        let previous = lastDragPoint ?? point
        let movement = ThoughtVector(dx: point.x - previous.x, dy: point.y - previous.y)
        let frame = engine.drag(objectID: objectID, to: point, movement: movement, bodies: bodies, bounds: bounds)
        bodies = frame.bodies
        updateContacts(frame.contactIDs, at: Date())
        updateGroupingPreview(draggedID: objectID, at: Date())
        lastDragPoint = point
    }

    func endDragging(objectID: String) -> ThoughtGroupPair? {
        guard draggedObjectID == objectID else { return nil }
        let pair = groupingEngine.finish(draggedID: objectID, bodies: bodies, at: Date())
        groupingHoldTask?.cancel()
        groupingHoldTask = nil
        groupingPreview = nil
        draggedObjectID = nil
        lastDragPoint = nil
        startSettling()
        return pair
    }

    func reset(defaultBodies: [ThoughtBody], kinds: [String: MindSpaceObjectKind], bounds: ThoughtBounds) {
        timer?.invalidate()
        timer = nil
        do {
            try repository.resetObjectPositions()
            storedPositions = [:]
            contactExpiry = [:]
            contactIDs = []
            draggedObjectID = nil
            groupingEngine.cancel()
            groupingPreview = nil
            groupingHoldTask?.cancel()
            groupingHoldTask = nil
            self.bounds = bounds
            self.kinds = kinds
            bodies = engine.step(bodies: defaultBodies, deltaTime: 0, bounds: bounds).bodies
            errorMessage = nil
        } catch {
            errorMessage = "The automatic layout could not be restored. Your current arrangement is still available. \(error)"
        }
    }

    private func startSettling() {
        lastTickDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard draggedObjectID == nil else { return }
        let now = Date()
        let deltaTime = now.timeIntervalSince(lastTickDate ?? now)
        lastTickDate = now
        let frame = engine.step(bodies: bodies, deltaTime: deltaTime, bounds: bounds)
        bodies = frame.bodies
        updateContacts(frame.contactIDs, at: now)

        guard engine.isSettled(bodies) else { return }
        timer?.invalidate()
        timer = nil
        savePositions()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(260))
            guard let self, self.timer == nil, self.draggedObjectID == nil else { return }
            self.contactExpiry = [:]
            self.contactIDs = []
        }
    }

    private func updateContacts(_ newContacts: Set<String>, at date: Date) {
        for objectID in newContacts {
            contactExpiry[objectID] = date.addingTimeInterval(0.24)
        }
        contactExpiry = contactExpiry.filter { $0.value > date }
        contactIDs = Set(contactExpiry.keys)
    }

    private func updateGroupingPreview(draggedID: String, at date: Date) {
        let previousTarget = groupingPreview?.targetID
        let preview = groupingEngine.update(draggedID: draggedID, bodies: bodies, at: date)

        if let preview,
           kinds[preview.draggedID] == .project,
           kinds[preview.targetID] == .project {
            groupingEngine.cancel()
            groupingPreview = nil
            groupingHoldTask?.cancel()
            groupingHoldTask = nil
            return
        }

        groupingPreview = preview
        guard let preview else {
            groupingHoldTask?.cancel()
            groupingHoldTask = nil
            return
        }
        guard previousTarget != preview.targetID || groupingHoldTask == nil else { return }

        groupingHoldTask?.cancel()
        groupingHoldTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self,
                      !Task.isCancelled,
                      self.draggedObjectID == draggedID else { return }
                let refreshed = self.groupingEngine.update(
                    draggedID: draggedID,
                    bodies: self.bodies,
                    at: Date()
                )
                self.groupingPreview = refreshed
                if refreshed == nil { return }
            }
        }
    }

    private func savePositions() {
        let positions = bodies.compactMap { body -> MindSpaceObjectPosition? in
            guard let kind = kinds[body.id] else { return nil }
            let normalized = normalizedPoint(body.center, bounds: bounds)
            return MindSpaceObjectPosition(
                objectID: body.id,
                kind: kind,
                normalizedX: normalized.x,
                normalizedY: normalized.y
            )
        }
        do {
            try repository.saveObjectPositions(positions)
            storedPositions = Dictionary(
                uniqueKeysWithValues: positions.map { (Self.key(id: $0.objectID, kind: $0.kind), $0) }
            )
            errorMessage = nil
        } catch {
            errorMessage = "This arrangement could not be saved locally. Your tasks were not changed. \(error)"
        }
    }

    private func normalizedPoint(_ point: ThoughtPoint, bounds: ThoughtBounds) -> ThoughtPoint {
        let width = max(bounds.maxX - bounds.minX, 1)
        let height = max(bounds.maxY - bounds.minY, 1)
        return ThoughtPoint(
            x: min(max((point.x - bounds.minX) / width, 0), 1),
            y: min(max((point.y - bounds.minY) / height, 0), 1)
        )
    }

    private func point(normalizedX: Double, normalizedY: Double, bounds: ThoughtBounds) -> ThoughtPoint {
        ThoughtPoint(
            x: bounds.minX + (bounds.maxX - bounds.minX) * normalizedX,
            y: bounds.minY + (bounds.maxY - bounds.minY) * normalizedY
        )
    }

    private func remapped(_ point: ThoughtPoint, from oldBounds: ThoughtBounds, to newBounds: ThoughtBounds, radius: Double) -> ThoughtPoint {
        guard oldBounds.maxX - oldBounds.minX > 1, oldBounds.maxY - oldBounds.minY > 1 else { return point }
        let normalized = normalizedPoint(point, bounds: oldBounds)
        let mapped = self.point(normalizedX: normalized.x, normalizedY: normalized.y, bounds: newBounds)
        return ThoughtPoint(
            x: min(max(mapped.x, newBounds.minX + radius), newBounds.maxX - radius),
            y: min(max(mapped.y, newBounds.minY + radius), newBounds.maxY - radius)
        )
    }

    private static func key(id: String, kind: MindSpaceObjectKind) -> String {
        "\(kind.rawValue):\(id)"
    }
}
