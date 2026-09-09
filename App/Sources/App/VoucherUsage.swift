import Foundation
import SwiftUI
import ExerciseRewardsKit

/// 「這張加碼券我已經用掉了」的本機標記。
///
/// ## 為什麼需要這個
///
/// 官網**沒有**「已使用／已核銷」這個狀態。實測（2026-09-06，券已在超商用掉的帳號）：
/// `/member/tasks` 那一期仍然是 `period-state--REDEEMED`「已兌換」，仍然掛著
/// 「檢視加碼券」連結，卡片上也仍然寫著「兌換內容：…」；券碼頁（OTP 關卡）
/// 與沒用過的券**一模一樣**，沒有任何 used／expired 標記。
///
/// 也就是說**這個狀態只能由使用者自己告訴 App**。OTP 通過後的
/// `/member/voucher/{uuid}/view` 是唯一還沒排除的地方，但即使那頁有標記也救不了列表——
/// 「要不要顯示條碼按鈕」是在列表上就要決定的，不可能為了畫一顆按鈕先發一次簡訊。
///
/// ## 界線
///
/// - **純本機狀態**：只寫 UserDefaults（App 容器），不送官網、不進遙測。
///   券到底還能不能用，一律以現場條碼掃得過為準；這裡只是使用者自己的紀錄。
/// - **可還原**：標錯了要能改回來，因此 `setUsed(_:for:)` 兩個方向都支援。
/// - **算「本機資料」**：`clear()` 必須被「立即登出並清除本機資料」與示範模式切換呼叫，
///   否則會出現「示範資料的券被標成已使用」或「清完資料還記得你用過哪張」。
///
/// ## key 用期別 UUID 而不是期數
///
/// 期數（`index`）只有 1–14，換帳號就會撞在一起——A 帳號標記的第 3 期會直接套到
/// B 帳號的第 3 期上。期別 UUID 是官網給的、綁帳號，不會有這個問題。
/// UUID 本來就已經隨 `TasksCache` 存在本機（`TaskPeriod.id`），這裡不算新增暴露面；
/// 但它仍然是**官方站識別碼**，所以一樣不准進遙測。
enum VoucherUsage {
    private static let key = "voucher.usage.usedIDs.v1"

    /// 目前被標記為已使用的期別 UUID。
    static func usedIDs(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    /// 標記／取消標記。id 為空字串（官網沒給 UUID 的期別）一律忽略——
    /// 那種期別根本點不進券碼頁，不會走到這裡。
    static func setUsed(_ used: Bool, forID id: String, defaults: UserDefaults = .standard) {
        guard !id.isEmpty else { return }
        var ids = usedIDs(defaults: defaults)
        if used {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
        // 排序過再存：UserDefaults 的內容順序穩定，日後 diff／除錯時看得懂。
        defaults.set(ids.sorted(), forKey: key)
    }

    /// 清除所有標記（「立即登出並清除本機資料」與示範模式切換時呼叫）。
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// 「已使用」標記的**單一真相來源**，由 `HuihanApp` 建立一份、`.environmentObject` 往下傳。
///
/// **為什麼一定要是共用的 observable，而不是各畫面自己讀一次**（這裡踩過坑，理由留著）：
/// 標記可以在三個地方被改（券碼頁、券夾、首頁），而首頁／任務／券夾是 `TabView` 的三個分頁，
/// **同時活著**。先前的寫法是每個 ViewModel 在 init 時把 `VoucherUsage.usedIDs()` 抄一份，
/// 結果在券夾標記完切回任務分頁，任務那份快照還是舊的——連下拉重新整理都救不了，
/// 因為下拉只重抓官網資料，而「已使用」根本不在官網資料裡。
///
/// 改成共用的 `@Published` 之後，任何一處寫入都會讓三個分頁一起重畫，不需要任何
/// 「回來時記得重讀」的呼叫（那種呼叫漏掉一個就是同一個 bug 再來一次）。
@MainActor
final class VoucherUsageStore: ObservableObject {
    @Published private(set) var usedIDs: Set<String>

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.usedIDs = VoucherUsage.usedIDs(defaults: defaults)
    }

    func isUsed(_ period: TaskPeriod) -> Bool {
        isUsed(id: period.id)
    }

    func isUsed(id: String) -> Bool {
        guard !id.isEmpty else { return false }
        return usedIDs.contains(id)
    }

    /// 切換某一期的標記，回傳切換後的值（呼叫端用它送遙測）。
    @discardableResult
    func toggle(id: String) -> Bool {
        let used = !isUsed(id: id)
        setUsed(used, id: id)
        return used
    }

    func setUsed(_ used: Bool, id: String) {
        VoucherUsage.setUsed(used, forID: id, defaults: defaults)
        usedIDs = VoucherUsage.usedIDs(defaults: defaults)
    }

    /// 示範模式切換與「立即登出並清除本機資料」用。
    func clear() {
        VoucherUsage.clear(defaults: defaults)
        usedIDs = []
    }
}
