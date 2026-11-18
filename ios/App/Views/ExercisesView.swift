import SpendingCore
import SwiftUI

/// The "Γυμναστική" section: week summary, the day's logged workouts, and the exercise library
/// with animated demos.
struct ExercisesView: View {
    @Environment(Router.self) private var router
    let day: String
    let today: String
    let pick: (String) -> Void
    @State private var detail: Exercise?

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 14) {
            DayNav(date: day, today: today, pick: pick)
            SummaryCard(today: today)
            TodayWorkoutsCard(day: day)
            LibraryCard { detail = $0 }
        }
        .sheet(item: $detail) { ex in
            ExerciseDetailView(exercise: ex, day: day)
        }
        .sheet(isPresented: $router.exercisePicker) {
            ExercisePickerView(day: day)
        }
    }
}

struct DayNav: View {
    let date: String
    let today: String
    let pick: (String) -> Void

    var body: some View {
        HStack {
            Button { pick(Days.add(date, -1)) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Προηγούμενη ημέρα")
            Spacer()
            Text(Days.label(date, today: today)).font(.headline)
            Spacer()
            Button { pick(Days.add(date, 1)) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Επόμενη ημέρα")
                .disabled(date >= today)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - summary

private struct SummaryCard: View {
    @Environment(Store.self) private var store
    let today: String

    var body: some View {
        let workouts = store.data.workouts
        let sessions = WorkoutLogic.sessionsThisWeek(workouts, today: today)
        let streak = WorkoutLogic.streak(workouts, today: today)
        let goal = store.data.settings.workoutGoal

        if let goal, goal > 0 {
            HStack(spacing: 18) {
                SessionsRing(sessions: sessions, goal: goal)
                VStack(alignment: .leading, spacing: 6) {
                    Text(sessions >= goal ? "Έπιασες τον στόχο! 💪" : "Αυτή την εβδομάδα").font(.headline)
                    Text("\(sessions) από \(goal) ημέρες προπόνησης").font(.subheadline)
                    if streak > 0 {
                        Label("Σερί \(streak) \(streak == 1 ? "ημέρα" : "ημέρες")", systemImage: "flame.fill").font(.footnote)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brand.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            Card {
                HStack(spacing: 14) {
                    StatBox(value: "\(sessions)", label: "ημέρες / εβδομάδα")
                    StatBox(value: "\(streak)", label: streak == 1 ? "ημέρα σερί" : "ημέρες σερί")
                }
                Text("Βάλε στόχο ημερών την εβδομάδα στις Ρυθμίσεις → Γυμναστική.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatBox: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 28, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SessionsRing: View {
    let sessions: Int
    let goal: Int
    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 12)
            Circle().trim(from: 0, to: min(Double(sessions) / Double(max(goal, 1)), 1))
                .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(sessions)").font(.system(size: 26, weight: .heavy, design: .rounded)).monospacedDigit()
                Text("/ \(goal)").font(.caption2)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - today's workouts

private struct TodayWorkoutsCard: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    let day: String

    var body: some View {
        let workouts = WorkoutLogic.day(store.data.workouts, day)
        Card {
            HStack {
                Text("Προπόνηση").font(.headline)
                Spacer()
                if !workouts.isEmpty {
                    Text("\(workouts.count) \(workouts.count == 1 ? "άσκηση" : "ασκήσεις")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if workouts.isEmpty {
                Text("Καμία άσκηση ακόμα. Πάτα + ή διάλεξε από τη βιβλιοθήκη πιο κάτω.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(workouts) { w in
                    Button { router.edit(w) } label: { WorkoutRow(workout: w) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { store.deleteWorkout(w.id) } label: { Label("Διαγραφή", systemImage: "trash") }
                        }
                    if w.id != workouts.last?.id { Divider() }
                }
            }
        }
    }
}

private struct WorkoutRow: View {
    let workout: Workout

    var body: some View {
        HStack(spacing: 12) {
            if let ex = Exercises.byId(workout.exerciseId) {
                ExerciseFigure(exercise: ex, playing: false)
                    .frame(width: 44, height: 44)
                    .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.body.weight(.semibold))
                Text(ExFmt.sets(workout)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ExFmt.amount(workout.total, kind: workout.kind)).font(.body.weight(.semibold)).monospacedDigit()
                Text("σύνολο").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - library

private struct LibraryCard: View {
    let open: (Exercise) -> Void
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Βιβλιοθήκη ασκήσεων").font(.headline).padding(.horizontal, 4)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Exercises.all) { ex in
                    Button { open(ex) } label: { ExerciseTile(exercise: ex) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ExerciseTile: View {
    @Environment(Store.self) private var store
    let exercise: Exercise

    var body: some View {
        let best = WorkoutLogic.bests(store.data.workouts)[exercise.id]
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ExerciseFigure(exercise: exercise)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .background(
                        LinearGradient(colors: [Color.brand.opacity(0.14), Color.brand.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                if let best {
                    Text("PB \(ExFmt.amount(best.value, kind: best.kind))")
                        .font(.caption2.weight(.bold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(exercise.muscle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            LevelDot(level: exercise.level).padding(10)
        }
    }
}

struct LevelDot: View {
    let level: ExerciseLevel
    var body: some View {
        Text(level.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
    private var color: Color {
        switch level {
        case .beginner: .green
        case .intermediate: .orange
        case .advanced: .red
        }
    }
}

// MARK: - formatting

enum ExFmt {
    /// A single amount: reps as a number, seconds as "45δ" or "1:30".
    static func amount(_ v: Int, kind: ExerciseKind) -> String {
        guard kind == .time else { return "\(v)" }
        return v >= 60 ? "\(v / 60):\(String(format: "%02d", v % 60))" : "\(v)δ"
    }

    /// A workout's sets, e.g. "3 σετ · 12, 10, 8" or "3 × 30δ".
    static func sets(_ w: Workout) -> String {
        guard !w.sets.isEmpty else { return "" }
        let n = w.sets.count
        let setsWord = n == 1 ? "σετ" : "σετ"
        if n > 1, Set(w.sets).count == 1 {
            return "\(n) × \(amount(w.sets[0], kind: w.kind))"
        }
        return "\(n) \(setsWord) · " + w.sets.map { amount($0, kind: w.kind) }.joined(separator: ", ")
    }
}
