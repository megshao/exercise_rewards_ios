import Foundation
import ExerciseRewardsKit

/// 任務清單的本地快取 + 節流。
/// - 本地優先：畫面先顯示上次抓到的任務，避免每次都等網路。
/// - 節流：距離上次成功更新未滿 `minInterval`（60 秒）不再發 request。
/// 快取只存任務狀態（期數/日期/狀態/倒數），**不含個資**；存在 UserDefaults（app 容器）。
enum TasksCache {
    private static let periodsKey = "tasks.cache.periods.v1"
    private static let updatedKey = "tasks.cache.updatedAt.v1"
    static let minInterval: TimeInterval = 60

    static func load() -> [TaskPeriod]? {
        guard let data = UserDefaults.standard.data(forKey: periodsKey) else { return nil }
        do {
            let periods = try JSONDecoder().decode([TaskPeriod].self, from: data)
            return periods.isEmpty ? nil : periods
        } catch {
            // 解碼失敗代表 App 更新後 `TaskPeriod` 結構變了，快取全體失效——
            // 這是回歸訊號，值得知道。**不附任何快取內容**（雖然不含個資，但沒必要），
            // 也不附 `error` 原物件（`DecodingError.debugDescription` 含欄位名與 coding path）。
            Telemetry.recordNonFatal(.cacheDecode)
            return nil
        }
    }

    static func save(_ periods: [TaskPeriod]) {
        guard let data = try? JSONEncoder().encode(periods) else { return }
        UserDefaults.standard.set(data, forKey: periodsKey)
        UserDefaults.standard.set(Date(), forKey: updatedKey)
    }

    static func lastUpdated() -> Date? {
        UserDefaults.standard.object(forKey: updatedKey) as? Date
    }

    /// 距離上次更新是否已超過節流間隔（沒有紀錄時視為可更新）。
    static func canRefresh(now: Date = Date()) -> Bool {
        guard let last = lastUpdated() else { return true }
        return now.timeIntervalSince(last) >= minInterval
    }

    /// 清除快取（登出／清資料時用）。
    static func clear() {
        UserDefaults.standard.removeObject(forKey: periodsKey)
        UserDefaults.standard.removeObject(forKey: updatedKey)
    }
}
