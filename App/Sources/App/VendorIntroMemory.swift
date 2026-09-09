import Foundation
import SwiftUI
import ExerciseRewardsKit

/// 「這一期兌換的是哪家廠商、它的可兌換品項頁在哪」的本機紀錄。
///
/// ## 為什麼需要這個
///
/// 券夾要在已兌換的券卡上提供「查看可兌換品項」，就需要那家廠商的 `introPath`。
/// 但**已兌換的期別在官網上沒有兌換頁了**——`TaskParser` 檔內註解與
/// `docs/redeem-flow-capture.md` 都記著：兌換後那張卡片只剩 voucher／screenshot 連結，
/// 而 `intro/vendor-*.html` 的連結只長在**兌換頁**上。已兌換期別手上只剩
/// `TaskPeriod.voucherSummary`（官網原文「通路／品項」）。
///
/// 而 `introPath` **不准自己用 vendorId 拼**（見 `RedeemOption.introPath` 的說明）：
/// 官網的規則是靜態頁存在才長出連結，拼出來的網址在沒有那一頁時就是 404。
///
/// 所以路徑只能「在還看得到的時候記下來」——使用者在 App 內按下「確認兌換」的那一刻，
/// 我們手上正好有完整的 `RedeemOption`。
///
/// ## 界線
///
/// - **純本機狀態**：只寫 UserDefaults（App 容器），不送官網、不進遙測。
/// - **`introPath` 已經被 `RedeemParser` 驗證過**（限定 `/intro/*.html`），這裡只是原封搬運；
///   讀回來仍會再驗一次，因為 UserDefaults 是使用者改得到的地方（見 `introPath(forID:)`）。
/// - **`vendorName` 是官網原文**，屬不受信任輸入：只能顯示，絕不可進遙測。
/// - **算「本機資料」**：`clear()` 必須被「立即登出並清除本機資料」與示範模式切換呼叫，
///   否則會出現「示範資料的期別記著真實廠商」或「清完資料還記得你換過哪一家」。
///
/// ## 覆蓋不到的情況（刻意接受）
///
/// 在官網或別台手機上兌換的期別沒有本機紀錄。那時券夾改用
/// `WalletViewModel` 的備援：intro 頁是**每家廠商的靜態頁、與期別無關**，
/// 所以可以拿任一個還可兌換的期別去載入兌換清單，用廠商名對出路徑。
/// 兩條都拿不到就不顯示那顆按鈕——與 `RedeemView` 的現行規則一致
/// （`introPath == nil` 就沒有「兌換品項」鈕）。
enum VendorIntroMemory {
    private static let key = "vendorIntro.byTaskID.v1"

    /// 一期的紀錄。存成 `["path": ..., "vendor": ...]` 的字典陣列
    /// （UserDefaults 能直接吃，不必為兩個字串引入 Codable）。
    struct Entry: Equatable, Sendable {
        let introPath: String
        let vendorName: String
    }

    static func entries(defaults: UserDefaults = .standard) -> [String: Entry] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: [String: String]] else { return [:] }
        return raw.compactMapValues { value in
            guard let path = value["path"], let vendor = value["vendor"],
                  VendorIntroPath.isValid(path) else { return nil }
            return Entry(introPath: path, vendorName: vendor)
        }
    }

    /// 記下某一期兌換到的廠商頁。`id` 或 `introPath` 空的一律忽略。
    static func remember(id: String, introPath: String, vendorName: String,
                         defaults: UserDefaults = .standard) {
        guard !id.isEmpty, VendorIntroPath.isValid(introPath) else { return }
        var raw = (defaults.dictionary(forKey: key) as? [String: [String: String]]) ?? [:]
        raw[id] = ["path": introPath, "vendor": vendorName]
        defaults.set(raw, forKey: key)
    }

    /// 清除所有紀錄（「立即登出並清除本機資料」與示範模式切換時呼叫）。
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// `introPath` 的形狀檢查。
///
/// **為什麼讀回來還要再驗一次**：`RedeemParser` 在解析時已經驗過，但這個值中間去
/// UserDefaults 繞了一圈，而那是使用者（或越獄環境下的其他程式）改得到的地方。
/// `VendorIntroView` 會拿它去組網址，所以把關放在最靠近使用點的地方，
/// 而不是相信「存進去的時候是乾淨的」。
enum VendorIntroPath {
    /// 與 `RedeemParser` 接受的形狀一致：base-relative、限定 `/intro/*.html`。
    static func isValid(_ path: String) -> Bool {
        guard path.count <= 200, path.hasPrefix("/intro/"), path.hasSuffix(".html") else { return false }
        // 不允許路徑跳脫或夾帶 query／fragment。
        guard !path.contains(".."), !path.contains("?"), !path.contains("#"),
              !path.contains("//") else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./")
        return path.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

/// 廠商頁紀錄的**單一真相來源**，由 `HuihanApp` 建立一份、`.environmentObject` 往下傳。
///
/// 與 `VoucherUsageStore` 同一個理由要共用：兌換是在 sheet 裡發生的（`RedeemView`），
/// 而券夾是同時活著的另一個分頁。寫入後要讓券夾立刻長出那顆按鈕，就不能各自抄快照。
@MainActor
final class VendorIntroStore: ObservableObject {
    @Published private(set) var entries: [String: VendorIntroMemory.Entry]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = VendorIntroMemory.entries(defaults: defaults)
    }

    func entry(for period: TaskPeriod) -> VendorIntroMemory.Entry? {
        entry(forID: period.id)
    }

    func entry(forID id: String) -> VendorIntroMemory.Entry? {
        guard !id.isEmpty else { return nil }
        return entries[id]
    }

    /// 兌換成功時呼叫（`RedeemViewModel.confirmRedeem`）。
    func remember(id: String, introPath: String, vendorName: String) {
        VendorIntroMemory.remember(id: id, introPath: introPath, vendorName: vendorName,
                                   defaults: defaults)
        entries = VendorIntroMemory.entries(defaults: defaults)
    }

    /// 示範模式切換與「立即登出並清除本機資料」用。
    func clear() {
        VendorIntroMemory.clear(defaults: defaults)
        entries = [:]
    }
}
