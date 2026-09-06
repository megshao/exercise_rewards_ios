import Foundation

/// 免責聲明的同意紀錄。
///
/// **這份紀錄能證明什麼、不能證明什麼**（在依賴它之前請先讀完）：
///
/// 能證明的：這支裝置上的 App 知道使用者同意過哪一個版本、什麼時候同意的。
/// 用途是流程控制——聲明改版時讓使用者重新同意，以及在「立即清除本機資料」時
/// 一併重置。
///
/// **不能**當作法律意義上的舉證：紀錄只存在使用者自己的裝置，開發者拿不到；
/// 越獄裝置上使用者也能自行竄改。要做到「開發者手上有一份可舉證的同意紀錄」，
/// 必須有伺服器接收、而且要能對應到特定使用者——那等於推翻本 App
/// 「沒有任何自建後端、開發者收不到你的任何資料」的核心設計。
/// 這裡刻意選擇保住後者。
///
/// 真正對外站得住的是另一組證據，而且那些是公開可驗證的：App Store 上的截圖、
/// 公開的隱私權政策頁、以及「任何人下載這支 App 都會在使用前看到這個畫面」
/// 這個行為本身——這些都不需要開發者持有使用者的個人紀錄。
enum DisclaimerConsent {
    /// 已同意的版本號。0（或不存在）代表從未同意。
    static let versionKey = "disclaimerAgreedVersion"
    /// 同意當下的時間戳（`timeIntervalSince1970`）。純粹本機除錯與顯示用。
    static let timestampKey = "disclaimerAgreedAt"

    static var agreedVersion: Int {
        UserDefaults.standard.integer(forKey: versionKey)
    }

    static var agreedAt: Date? {
        let raw = UserDefaults.standard.double(forKey: timestampKey)
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    static var hasAgreedToCurrentVersion: Bool {
        agreedVersion >= DisclaimerView.currentVersion
    }

    /// 記下同意。**刻意不送遙測**：這個畫面出現在使用者看到遙測開關之前，
    /// 遙測此時必然是關的；而且用匿名、可關閉的統計來承載「同意紀錄」本來就不對。
    static func record() {
        let defaults = UserDefaults.standard
        defaults.set(DisclaimerView.currentVersion, forKey: versionKey)
        defaults.set(Date().timeIntervalSince1970, forKey: timestampKey)
    }

    /// 「立即清除本機資料」時呼叫：回到從未同意的狀態。
    /// 清除的語意是「回到初次設定」，同意紀錄也屬於那個狀態的一部分。
    static func reset() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: versionKey)
        defaults.removeObject(forKey: timestampKey)
    }
}
