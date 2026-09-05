import Foundation

/// 某一日的運動摘要（來自 Apple 健康的真實數據，唯讀）。
/// 這些值只用於「達標判定」與「產生上傳圖卡」，圖卡必須忠實呈現、不得竄改。
public struct HealthSummary: Equatable, Sendable {
    public var date: Date
    public var steps: Int
    public var distanceMeters: Double
    public var exerciseMinutes: Int

    public init(date: Date, steps: Int, distanceMeters: Double, exerciseMinutes: Int) {
        self.date = date; self.steps = steps
        self.distanceMeters = distanceMeters; self.exerciseMinutes = exerciseMinutes
    }
    public var distanceKm: Double { distanceMeters / 1000.0 }
}

/// 任務辦法認可的達標條件（單日任一項成立即符合當週任務）。
public enum TaskCriterion: String, CaseIterable, Sendable {
    case steps8000      // 單日步行 8,000 步
    case walk30min      // 單次/單日健走 30 分鐘
    case run5km         // 跑步 5 公里

    public var label: String {
        switch self {
        case .steps8000: return "單日 8,000 步"
        case .walk30min: return "運動 30 分鐘"
        case .run5km:    return "距離 5 公里"
        }
    }
}

/// 達標判定結果。
public struct GoalEvaluation: Equatable, Sendable {
    public let met: [TaskCriterion]
    public var isMet: Bool { !met.isEmpty }
    public init(met: [TaskCriterion]) { self.met = met }
}

/// 讀取健康數據的介面（實作在 App 端以 HealthKit 提供；核心層保持可測、不綁 HealthKit）。
public protocol HealthReading: Sendable {
    /// 是否已取得讀取授權。
    func isAuthorized() async -> Bool
    /// 請求唯讀授權（步數/距離/運動時間）。
    func requestAuthorization() async throws
    /// 取得指定日期的運動摘要。
    func summary(for date: Date) async throws -> HealthSummary
}

public enum GoalEvaluator {
    /// 依健康摘要判定符合哪些任務條件。門檻採官方任務辦法。
    public static func evaluate(_ s: HealthSummary,
                                stepGoal: Int = 8000,
                                exerciseMinutesGoal: Int = 30,
                                distanceKmGoal: Double = 5.0) -> GoalEvaluation {
        var met: [TaskCriterion] = []
        if s.steps >= stepGoal { met.append(.steps8000) }
        if s.exerciseMinutes >= exerciseMinutesGoal { met.append(.walk30min) }
        if s.distanceKm >= distanceKmGoal { met.append(.run5km) }
        return GoalEvaluation(met: met)
    }
}
