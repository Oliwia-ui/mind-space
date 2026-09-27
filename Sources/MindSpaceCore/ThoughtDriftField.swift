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

    /// The far end of a thought's hovering travel.
    ///
    /// Paired with `hoverDuration`, this drives an autoreversing animation, which lets the
    /// render server do the work instead of re-evaluating the canvas on every frame.
    public func hoverTarget(forID id: String) -> ThoughtPoint {
        let angle = phase(forID: id)
        let travel = amplitude * 0.5 + amplitude * 0.5 * Double((hash(forID: id) % 100)) / 100
        return ThoughtPoint(x: travel * cos(angle), y: travel * sin(angle))
    }

    /// How long one hover sweep takes, so no two thoughts breathe in lockstep.
    public func hoverDuration(forID id: String) -> Double {
        let spread = Double((hash(forID: id) >> 13) % 100) / 100
        return hoverPeriod * 0.6 + hoverPeriod * 0.8 * spread
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
        Double(hash(forID: id) % 6_283) / 1_000
    }

    private func hash(forID id: String) -> UInt64 {
        var value = id.unicodeScalars.reduce(into: UInt64(7)) { result, scalar in
            result = result &* 31 &+ UInt64(scalar.value)
        }
        // Avalanche the digest so ids that differ by one character land far apart.
        value ^= value >> 33
        value = value &* 0xff51_afd7_ed55_8ccd
        value ^= value >> 33
        value = value &* 0xc4ce_b9fe_1a85_ec53
        value ^= value >> 33
        return value
    }
}
