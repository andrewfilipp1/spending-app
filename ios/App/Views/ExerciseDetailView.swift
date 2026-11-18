import SpendingCore
import SwiftUI

/// A single exercise: a large animated demo, how-to tips, your best so far, and a button to log it.
struct ExerciseDetailView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let exercise: Exercise
    let day: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ExerciseFigure(exercise: exercise, lineWidth: 0.045)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .background(
                            LinearGradient(colors: [Color.brand.opacity(0.16), Color.brand.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )

                    HStack(spacing: 8) {
                        Chip(text: exercise.muscle)
                        LevelDot(level: exercise.level)
                        Chip(text: exercise.kind == .time ? "Χρόνος" : "Επαναλήψεις")
                    }

                    if let best = WorkoutLogic.bests(store.data.workouts)[exercise.id] {
                        Label("Ρεκόρ: \(ExFmt.amount(best.value, kind: best.kind)) · \(Days.label(best.date))",
                              systemImage: "trophy.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.brand)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Πώς γίνεται").font(.headline)
                        ForEach(Array(exercise.tips.enumerated()), id: \.offset) { i, tip in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.brand, in: Circle())
                                Text(tip).font(.subheadline)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding()
                .padding(.bottom, 80)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    router.newWorkout(exercise, date: day)
                } label: {
                    Label("Καταγραφή", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Κλείσιμο") { dismiss() }
                }
            }
        }
    }
}

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Picks an exercise from the library to log (from the "+" button).
struct ExercisePickerView: View {
    @Environment(Store.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    let day: String

    var body: some View {
        NavigationStack {
            List(Exercises.all) { ex in
                Button {
                    dismiss()
                    router.newWorkout(ex, date: day)
                } label: {
                    HStack(spacing: 12) {
                        ExerciseFigure(exercise: ex, playing: false)
                            .frame(width: 44, height: 44)
                            .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.body.weight(.semibold))
                            Text(ex.muscle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Διάλεξε άσκηση")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Άκυρο") { dismiss() } }
            }
        }
    }
}
