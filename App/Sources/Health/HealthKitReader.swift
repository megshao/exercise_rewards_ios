#if canImport(HealthKit)
import Foundation
import HealthKit
import SportsRewardsKit

/// HealthKit 錯誤（不含個資，可安全記錄訊息本身，但絕不夾帶健康數值）。
public enum HealthKitReaderError: Error, Sendable {
    case notAvailable
}

/// 唯讀 HealthKit 實作，符合 SportsRewardsKit 的 `HealthReading` 介面。
///
/// - 只讀取步數（`.stepCount`）、步行/跑步距離（`.distanceWalkingRunning`）、運動時間（`.appleExerciseTime`）。
/// - `requestAuthorization()` 一律以 `toShare: []` 呼叫，App 絕不寫入健康資料。
/// - `HKHealthStore` 非 Sendable 型別，本類別以 `@unchecked Sendable` 標記，內部僅持有
///   HealthKit 自身管理執行緒安全的 store，不額外持有可變共享狀態（授權旗標存於 UserDefaults）。
public final class HealthKitReader: HealthReading, @unchecked Sendable {
    private let store = HKHealthStore()
    private let log = SecureLog(.health)

    /// 需要授權的三種讀取型別。
    private static var quantityTypes: Set<HKQuantityType> {
        var types: Set<HKQuantityType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let exercise = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) { types.insert(exercise) }
        return types
    }

    /// HealthKit 基於隱私設計，不會揭露「讀取」授權是否被核准或拒絕
    /// （`HKHealthStore.authorizationStatus(for:)` 只反映「分享／寫入」授權，
    /// 本 App 從不申請寫入）。因此以「是否已完整跑過一次 `requestAuthorization()` 流程」
    /// 作為本機的授權旗標；實際能否讀到資料，仍以查詢結果為準（拒絕時 HealthKit 回傳空樣本、非錯誤）。
    private static let didRequestKey = "com.megshao.sportsrewards.health.didRequestAuthorization"

    public init() {}

    public func isAuthorized() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return UserDefaults.standard.bool(forKey: Self.didRequestKey)
    }

    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitReaderError.notAvailable
        }
        let types: Set<HKObjectType> = Set(Self.quantityTypes.map { $0 as HKObjectType })
        try await store.requestAuthorization(toShare: [], read: types)
        UserDefaults.standard.set(true, forKey: Self.didRequestKey)
        log.info("health authorization flow completed")
    }

    public func summary(for date: Date) async throws -> HealthSummary {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        // 依序查詢（而非平行 async let）：`NSPredicate` 非 Sendable，Swift 6 嚴格併發下
        // 不允許同一個 predicate 實例被送進多個並行 task；三次查詢皆很輕量，依序執行影響可忽略。
        let steps = try await sumQuantity(identifier: .stepCount, unit: .count(), start: start, end: end)
        let distance = try await sumQuantity(identifier: .distanceWalkingRunning, unit: .meter(), start: start, end: end)
        let exercise = try await sumQuantity(identifier: .appleExerciseTime, unit: .minute(), start: start, end: end)

        return HealthSummary(
            date: start,
            steps: Int(steps.rounded()),
            distanceMeters: distance,
            exerciseMinutes: Int(exercise.rounded())
        )
    }

    /// 對指定型別做累加查詢；查不到樣本（含尚未授權、當日無資料）回傳 0，不視為錯誤。
    private func sumQuantity(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return 0 }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                // 讀取查詢的良性狀況（當日無樣本、授權未定/被拒）HealthKit 會回 error 或 nil 統計；
                // 依隱私設計讀取無法區分「被拒」與「沒資料」，一律當作 0，不讓整頁報錯。
                if let error {
                    let benign: Set<Int> = [
                        HKError.Code.errorNoData.rawValue,
                        HKError.Code.errorAuthorizationNotDetermined.rawValue,
                        HKError.Code.errorAuthorizationDenied.rawValue
                    ]
                    if let hk = error as? HKError, benign.contains(hk.code.rawValue) {
                        continuation.resume(returning: 0)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}
#endif
