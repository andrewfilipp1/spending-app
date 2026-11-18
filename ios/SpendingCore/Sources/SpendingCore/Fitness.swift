import Foundation

// Workouts logged by the user. One entry = one exercise done on a day, with its sets.
// Same JSON shape and sync rules as js/logic.js (merged record by record, like meals).

public struct Workout: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var date: String          // yyyy-MM-dd
    public var exerciseId: String    // catalog id
    public var name: String          // snapshot of the exercise name (survives catalog changes)
    public var kind: ExerciseKind    // reps | time
    public var sets: [Int]           // per set: repetitions, or seconds held
    public var createdAt: Double
    public var updatedAt: Double

    public init(id: String = UUID().uuidString, date: String, exerciseId: String, name: String, kind: ExerciseKind,
                sets: [Int], createdAt: Double = Date().timeIntervalSince1970 * 1000, updatedAt: Double = 0) {
        self.id = id
        self.date = date
        self.exerciseId = exerciseId
        self.name = name
        self.kind = kind
        self.sets = sets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        date = try c.decode(String.self, forKey: .date)
        exerciseId = (try? c.decodeIfPresent(String.self, forKey: .exerciseId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        kind = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil).flatMap(ExerciseKind.init(rawValue:)) ?? .reps
        sets = (try? c.decodeIfPresent([Int].self, forKey: .sets)) ?? []
        createdAt = (try? c.decodeIfPresent(Double.self, forKey: .createdAt)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
    }

    /// Total repetitions, or total seconds, across the sets.
    public var total: Int { sets.reduce(0, +) }
    /// The best single set (max reps, or longest hold).
    public var best: Int { sets.max() ?? 0 }

    func sanitized() -> Workout? {
        guard Days.isValid(date) else { return nil }
        var w = self
        w.name = name.isEmpty ? (Exercises.byId(exerciseId)?.name ?? "Άσκηση") : String(name.prefix(80))
        w.exerciseId = String(exerciseId.prefix(64))
        let cap = kind == .time ? 36_000 : 1_000   // ≤10h hold, ≤1000 reps/set
        w.sets = sets.map { min(max($0, 0), cap) }.filter { $0 > 0 }
        w.sets = Array(w.sets.prefix(30))
        return w.sets.isEmpty ? nil : w
    }
}

public struct ExerciseBest: Sendable {
    public var exerciseId: String
    public var kind: ExerciseKind
    public var value: Int     // best single set
    public var date: String
}

public enum WorkoutLogic {
    /// Workouts logged on a day, in the order they were added.
    public static func day(_ workouts: [Workout], _ date: String) -> [Workout] {
        workouts.filter { $0.date == date }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Distinct days with at least one workout, within the last `days` days ending today.
    public static func sessionsThisWeek(_ workouts: [Workout], today: String, days: Int = 7) -> Int {
        let from = Days.add(today, -(days - 1))
        let set = Set(workouts.filter { $0.date >= from && $0.date <= today }.map(\.date))
        return set.count
    }

    /// Consecutive days with a workout, counting back from today (or yesterday if today is empty).
    public static func streak(_ workouts: [Workout], today: String) -> Int {
        let active = Set(workouts.map(\.date))
        guard !active.isEmpty else { return 0 }
        var day = active.contains(today) ? today : Days.add(today, -1)
        guard active.contains(day) else { return 0 }
        var n = 0
        while active.contains(day) {
            n += 1
            day = Days.add(day, -1)
        }
        return n
    }

    /// The best single set per exercise, most recent first by best date.
    public static func bests(_ workouts: [Workout]) -> [String: ExerciseBest] {
        var out: [String: ExerciseBest] = [:]
        for w in workouts {
            let b = w.best
            guard b > 0 else { continue }
            if let cur = out[w.exerciseId], cur.value >= b { continue }
            out[w.exerciseId] = ExerciseBest(exerciseId: w.exerciseId, kind: w.kind, value: b, date: w.date)
        }
        return out
    }
}
