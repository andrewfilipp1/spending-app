import SpendingCore
import SwiftUI

/// Logs (or edits) one exercise for a day: its sets, in reps or seconds.
struct WorkoutEditorView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    private struct SetRow: Identifiable { let id = UUID(); var value: Int }

    private let original: Workout?
    private let exercise: Exercise?
    private let exerciseId: String
    private let name: String
    private let kind: ExerciseKind
    @State private var date: Date
    @State private var rows: [SetRow]
    @State private var prefilled: Bool
    @State private var confirmDelete = false

    init(target: WorkoutTarget) {
        let w = target.workout
        original = w
        exercise = target.exercise
        exerciseId = w?.exerciseId ?? target.exercise?.id ?? ""
        name = w?.name ?? target.exercise?.name ?? "Άσκηση"
        kind = w?.kind ?? target.exercise?.kind ?? .reps
        _date = State(initialValue: Days.date(w?.date ?? target.date))
        if let w {
            _rows = State(initialValue: w.sets.map { SetRow(value: $0) })
            _prefilled = State(initialValue: true)
        } else {
            _rows = State(initialValue: [SetRow(value: target.exercise?.defaultAmount ?? 10)])
            _prefilled = State(initialValue: false)
        }
    }

    private var step: Int { kind == .time ? 5 : 1 }
    private var unitLabel: String { kind == .time ? "δευτερόλεπτα" : "επαναλήψεις" }

    var body: some View {
        NavigationStack {
            Form {
                if let exercise {
                    Section {
                        HStack(spacing: 14) {
                            ExerciseFigure(exercise: exercise)
                                .frame(width: 84, height: 84)
                                .background(Color.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(exercise.name).font(.headline)
                                Text(exercise.muscle).font(.caption).foregroundStyle(.secondary)
                                Text(kind == .time ? "Μετριέται σε χρόνο" : "Μετριέται σε επαναλήψεις")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }

                Section {
                    ForEach($rows) { $row in
                        Stepper(value: $row.value, in: 0...(kind == .time ? 36000 : 1000), step: step) {
                            HStack {
                                Text("Σετ \((rows.firstIndex { $0.id == row.id } ?? 0) + 1)")
                                Spacer()
                                Text(ExFmt.amount(row.value, kind: kind))
                                    .font(.body.weight(.semibold)).monospacedDigit()
                                if kind == .reps { Text("επαν.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    .onDelete { rows.remove(atOffsets: $0) }

                    Button {
                        rows.append(SetRow(value: rows.last?.value ?? (exercise?.defaultAmount ?? (kind == .time ? 30 : 10))))
                    } label: {
                        Label("Προσθήκη σετ", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Σετ (σε \(unitLabel))")
                } footer: {
                    Text(summary)
                }

                Section {
                    DatePicker("Ημερομηνία", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                if original != nil {
                    Section {
                        Button("Διαγραφή", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(original == nil ? "Νέα προπόνηση" : "Προπόνηση")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Άκυρο") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Αποθήκευση") { save() }
                        .fontWeight(.semibold)
                        .disabled(rows.filter { $0.value > 0 }.isEmpty)
                }
            }
            .onAppear(perform: prefillFromLast)
            .confirmationDialog("Διαγραφή;", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Διαγραφή", role: .destructive) {
                    if let original { store.deleteWorkout(original.id) }
                    dismiss()
                }
            }
        }
    }

    /// For a new workout, start from the last time this exercise was done.
    private func prefillFromLast() {
        guard !prefilled else { return }
        prefilled = true
        if let last = store.data.workouts.filter({ $0.exerciseId == exerciseId }).max(by: { $0.createdAt < $1.createdAt }) {
            rows = last.sets.map { SetRow(value: $0) }
        }
    }

    private var summary: String {
        let clean = rows.map(\.value).filter { $0 > 0 }
        guard !clean.isEmpty else { return "Πρόσθεσε τουλάχιστον ένα σετ." }
        let total = clean.reduce(0, +)
        return kind == .time
            ? "Σύνολο \(ExFmt.amount(total, kind: .time)) σε \(clean.count) σετ."
            : "Σύνολο \(total) επαναλήψεις σε \(clean.count) σετ."
    }

    private func save() {
        let clean = rows.map(\.value).filter { $0 > 0 }
        guard !clean.isEmpty else { return }
        var w = original ?? Workout(date: Days.key(date), exerciseId: exerciseId, name: name, kind: kind, sets: clean)
        w.date = Days.key(date)
        w.exerciseId = exerciseId
        w.name = name
        w.kind = kind
        w.sets = clean
        store.upsertWorkout(w)
        dismiss()
    }
}
