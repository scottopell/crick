/// Identifies a reproducible, headless creek-laboratory run.
public struct Scenario: Equatable, Sendable {
    public let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    /// A stable description suitable for the bootstrap CLI and tests.
    public var summary: String {
        "Crick scenario seed: \(seed)"
    }
}
