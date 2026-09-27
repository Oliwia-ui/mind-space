import Foundation

/// Calm ambient motion for a free-floating Mind Space.
///
/// The field never changes a thought's saved position. It only reports a small,
/// deterministic offset that the canvas adds while drawing, so thoughts hover and
/// orbit gently while the layout the user arranged stays exactly where they left it.
public struct ThoughtDriftField: Sendable {
    private let amplitude: Double
    private let hoverPeriod: Double
    private let orbitPeriod: Double

    public init(amplitude: Double = 6, hoverPeriod: Double = 11, orbitPeriod: Double = 96) {
        self.amplitude = max(0, amplitude)
        self.hoverPeriod = max(1, hoverPeriod)
        self.orbitPeriod = max(1, orbitPeriod)
    }

    /// A gentle hovering offset for an ungrouped thought.
    public func hoverOffset(forID id: String, at time: Double) -> ThoughtPoint {
        let phase = phase(forID: id)
        let angularSpeed = 2 * Double.pi / hoverPeriod
        return ThoughtPoint(
            x: amplitude * sin(angularSpeed * time + phase),
            y: amplitude * sin(angularSpeed * 0.63 * time + phase * 1.7)
        )
    }

    /// The resting point of a task orbiting the project it belongs to.
    public func orbitPoint(
        around center: ThoughtPoint,
        radius: Double,
        index: Int,
        count: Int,
        at time: Double
    ) -> ThoughtPoint {
        let slots = max(1, count)
        let spacing = 2 * Double.pi / Double(slots)
        let angle = spacing * Double(index) + 2 * Double.pi * time / orbitPeriod
        return ThoughtPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    /// Stable per-thought phase so each object drifts on its own rhythm.
    private func phase(forID id: String) -> Double {
        let hash = id.unicodeScalars.reduce(into: UInt64(7)) { result, scalar in
            result = result &* 31 &+ UInt64(scalar.value)
        }
        return Double(hash % 6_283) / 1_000
    }
}
