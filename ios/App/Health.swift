import Foundation
import HealthKit
import Observation
import SpendingCore

/// What the Body screen shows, read from the Health app (filled by the watch).
struct BodyStats: Equatable {
    var steps: Double?
    var activeKcal: Double?
    var sleepMinutes: Double?
    var deepSleepMinutes: Double?
    var restingHR: Double?
    var hrv: Double?
    var vo2max: Double?
    var weights: [WeightPoint] = []
    var updated = Date()

    var weight: Double? { weights.last?.kg }
}

struct WeightPoint: Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let kg: Double
}

/// Reads activity, sleep, heart and weight from Health, and writes meals there.
/// Everything stays on the iPhone (HealthKit is on-device); only on when the user turns it on.
@MainActor @Observable
final class Health {
    static let shared = Health()

    private(set) var energy: HealthEnergy?
    private(set) var stats: BodyStats?
    private(set) var busy = false

    private let store = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private var enabled: Bool { available && Store.shared.loaded && Store.shared.data.nutrition.useHealth }

    private let reads: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned), HKQuantityType(.stepCount),
        HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.vo2Max),
        HKQuantityType(.bodyMass), HKCategoryType(.sleepAnalysis),
    ]
    private let writes: [(HKQuantityType, HKUnit, KeyPath<Meal, Double>?)] = [
        (HKQuantityType(.dietaryEnergyConsumed), .kilocalorie(), nil),
        (HKQuantityType(.dietaryProtein), .gram(), \.protein),
        (HKQuantityType(.dietaryCarbohydrates), .gram(), \.carbs),
        (HKQuantityType(.dietaryFatTotal), .gram(), \.fat),
    ]

    /// Asks for access (the system sheet shows once). Returns false if Health is unavailable.
    func requestAccess() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(toShare: Set(writes.map { $0.0 as HKSampleType }), read: reads)
            return true
        } catch {
            return false
        }
    }

    func refresh() async {
        guard enabled, !busy else { return }
        busy = true
        defer { busy = false }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)

        async let active = sum(.activeEnergyBurned, .kilocalorie(), from: today, to: now)
        async let steps = sum(.stepCount, .count(), from: today, to: now)
        async let resting = typicalDailyBasal(before: today)
        async let restingHR = latest(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()))
        async let hrv = latest(.heartRateVariabilitySDNN, .secondUnit(with: .milli))
        async let vo2 = latest(.vo2Max, HKUnit(from: "ml/kg*min"))
        async let weights = series(.bodyMass, .gramUnit(with: .kilo), days: 30)
        async let sleep = lastNightSleep(today: today)

        let a = await active
        let r = await resting
        energy = r.map { HealthEnergy(restingKcal: $0, activeKcal: a ?? 0) }
        let s = await sleep
        stats = BodyStats(steps: await steps, activeKcal: a, sleepMinutes: s?.asleep, deepSleepMinutes: s?.deep, restingHR: await restingHR,
                          hrv: await hrv, vo2max: await vo2, weights: await weights, updated: now)
    }

    // MARK: writing meals

    /// Replaces the meal's samples in Health (matched by the meal id).
    func saveMeal(_ m: Meal) {
        guard enabled else { return }
        let date = Self.time(of: m)
        let samples: [HKQuantitySample] = writes.compactMap { type, unit, path in
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { return nil }
            let value = path.map { m[keyPath: $0] } ?? Double(m.kcal)
            guard value > 0 else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value), start: date, end: date,
                                    metadata: [HKMetadataKeyExternalUUID: m.id, HKMetadataKeyFoodType: m.name])
        }
        let healthStore = store
        remove(m.id) { if !samples.isEmpty { healthStore.save(samples) { _, _ in } } }
    }

    func deleteMeal(_ id: String) {
        guard enabled else { return }
        remove(id) {}
    }

    private func remove(_ id: String, then: @escaping () -> Void) {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeyExternalUUID, allowedValues: [id])
        let types = writes.map(\.0).filter { store.authorizationStatus(for: $0) == .sharingAuthorized }
        guard !types.isEmpty else { return then() }
        let group = DispatchGroup()
        for t in types {
            group.enter()
            store.deleteObjects(of: t, predicate: predicate) { _, _, _ in group.leave() }
        }
        group.notify(queue: .main, execute: then)
    }

    /// A meal's time in Health: its time of day on its date.
    private static func time(of m: Meal) -> Date {
        let hour = switch m.meal {
        case .breakfast: 8
        case .lunch: 14
        case .dinner: 20
        case .snack: 17
        }
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Days.date(m.date)) ?? Days.date(m.date)
    }

    // MARK: queries

    private func sum(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from: Date, to: Date) async -> Double? {
        let q = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: from, end: to)),
            options: .cumulativeSum)
        return try? await q.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
    }

    /// Average resting energy of the last 7 full days that have data (today's is still counting up).
    private func typicalDailyBasal(before today: Date) async -> Double? {
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: today) else { return nil }
        let q = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.basalEnergyBurned), predicate: HKQuery.predicateForSamples(withStart: start, end: today)),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await q.result(for: store) else { return nil }
        var days: [Double] = []
        collection.enumerateStatistics(from: start, to: today) { s, _ in
            // Days the watch was worn only part of the time would pull the average down.
            if let v = s.sumQuantity()?.doubleValue(for: .kilocalorie()), v > 800 { days.append(v) }
        }
        return days.isEmpty ? nil : days.reduce(0, +) / Double(days.count)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> Double? {
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(id))],
                                        sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        return try? await q.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    private func series(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, days: Int) async -> [WeightPoint] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let q = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.endDate)])
        let samples = (try? await q.result(for: store)) ?? []
        return samples.map { WeightPoint(date: $0.endDate, kg: $0.quantity.doubleValue(for: unit)) }
    }

    /// Minutes asleep (and in deep sleep) from 6 pm yesterday to noon today.
    private func lastNightSleep(today: Date) async -> (asleep: Double, deep: Double)? {
        let cal = Calendar.current
        guard let from = cal.date(byAdding: .hour, value: -6, to: today), let to = cal.date(byAdding: .hour, value: 12, to: today) else { return nil }
        let q = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [])
        guard let samples = try? await q.result(for: store), !samples.isEmpty else { return nil }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        // Several sources (watch, phone) can record the same night: count the source with the most sleep.
        var bySource: [String: (asleep: Double, deep: Double)] = [:]
        for s in samples where asleep.contains(s.value) {
            let minutes = s.endDate.timeIntervalSince(s.startDate) / 60
            var t = bySource[s.sourceRevision.source.bundleIdentifier] ?? (0, 0)
            t.asleep += minutes
            if s.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue { t.deep += minutes }
            bySource[s.sourceRevision.source.bundleIdentifier] = t
        }
        return bySource.values.max { $0.asleep < $1.asleep }
    }
}
