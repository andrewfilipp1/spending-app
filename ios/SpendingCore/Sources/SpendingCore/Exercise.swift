import Foundation

// The exercise catalog (library + animation data), shipped as a resource so the same
// definitions drive the figure on iOS and, later, the web. Not user data — never synced.
// Each exercise carries a tiny skeleton: named joints in a 0..100 box (y points down),
// bones that connect them, and 2 key poses the figure eases and ping-pongs between.

public enum ExerciseKind: String, Codable, Sendable {
    case reps   // counted in repetitions
    case time   // held/measured in seconds
}

public enum ExerciseLevel: String, Codable, Sendable, CaseIterable {
    case beginner, intermediate, advanced

    public var title: String {
        switch self {
        case .beginner: "Αρχάριος"
        case .intermediate: "Μέτριος"
        case .advanced: "Προχωρημένος"
        }
    }
}

/// A point in the 0..100 drawing box.
public struct Joint: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

public struct Exercise: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var muscle: String
    public var level: ExerciseLevel
    public var kind: ExerciseKind
    public var tips: [String]
    public var view: String        // "side" | "front" (informational)
    public var period: Double      // seconds for one full ping-pong of the animation
    public var head: String        // joint drawn as the head circle
    public var hr: Double          // head radius (in the 0..100 box)
    public var ground: Double      // y of the floor line
    public var wall: Bool?         // draw a wall (e.g. wall sit)
    public var bones: [[String]]   // pairs of joint names
    public var poses: [[String: Joint]]

    /// The default measurement for a new set (reps for strength, seconds for holds).
    public var defaultAmount: Int { kind == .time ? 30 : 10 }

    /// The joints at phase `t` (0…1), eased and interpolated between the two key poses.
    public func interpolated(_ t: Double) -> [String: Joint] {
        guard let a = poses.first else { return [:] }
        let b = poses.count > 1 ? poses[1] : a
        let e = 0.5 - 0.5 * cos(.pi * min(max(t, 0), 1)) // easeInOut
        var out: [String: Joint] = [:]
        for (k, pa) in a {
            let pb = b[k] ?? pa
            out[k] = Joint(x: pa.x + (pb.x - pa.x) * e, y: pa.y + (pb.y - pa.y) * e)
        }
        return out
    }
}

extension Joint {
    init(x: Double, y: Double) { self.x = x; self.y = y }
}

public enum Exercises {
    private struct Catalog: Decodable { let version: Int; let exercises: [Exercise] }

    /// The catalog, loaded once from the bundled JSON.
    public static let all: [Exercise] = {
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { return [] }
        return catalog.exercises
    }()

    public static func byId(_ id: String) -> Exercise? { all.first { $0.id == id } }
}
