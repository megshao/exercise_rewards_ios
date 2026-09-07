import Foundation

/// 官網改版時，要把使用者交接到官網的哪一頁。
///
/// 三個 case 對應 App 內三個會自己解析官網 HTML 的畫面。首頁與任務頁共用 `.tasks`——
/// 官網沒有「首頁」這種東西，登入後的第一頁就是任務清單。
public enum SiteHandoffDestination: Equatable, Sendable {
    /// 任務清單（`/member/tasks`）。首頁與任務頁都交接到這裡。
    case tasks
    /// 某一期的可兌換清單（`/member/redeem/{uuid}`）。
    case redeem(taskID: String)
    /// 某一期的加碼券券碼頁（`/member/voucher/{uuid}`）。官網會先要求重新驗證一次簡訊。
    case voucher(taskID: String)
}

/// 官網改版降級接手：parser 對不上官網結構時，不修、不繞，只負責**說實話並交接**——
/// 給 UI 一個可以外開系統瀏覽器的官網 URL。
///
/// **為什麼放在 Kit 而不是 View 裡**：URL 是用官網 HTML 解析出來的 `taskID` 組的，那是
/// 不受信任輸入；組 URL 的規則（白名單、退路）需要單元測試守著，而 App target 沒有測試。
/// UI 層只准拿這裡回傳的 `URL` 去 `openURL`，**不得自己拼字串**。
///
/// **為什麼不自動登入**（已評估過，不要再提案）：官網登入是兩段式 POST，`_csrf` 綁在當下的
/// JSESSIONID 上，沒有任何 URL 可以「帶著三碼打開就登入」；App 的 cookie jar 也寫不進系統瀏覽器
/// （平台刻意封死）。唯一做得到的是 in-app WebView 注入 session，但那會踩 App Store 審查
/// 4.2／5.2.2，並把 Keychain 保護的 session 洩到 WebView 的明文儲存。所以交接方式是
/// 外開官網對應頁面，並在 UI 上提供「複製身分證號」讓使用者少打一欄。
public enum SiteHandoff {
    /// `taskID` 的長度上限。取自 `TaskParser.idPattern` 的 `{1,64}`——parser 本來就不會
    /// 吐出更長的 id，超過只可能是別的東西。
    public static let maxTaskIDLength = 64

    /// `taskID` 只允許這些字元，**與 `TaskParser.idPattern`（`[0-9a-fA-F-]{1,64}`）完全一致**：
    /// parser 只會吐出這個形狀的 id，長得不一樣就是別的東西。順帶排除了所有有 URL 語意的字元
    /// （`/` `?` `#` `%` `.` 空白…），路徑不可能被拼出去到別的端點。
    /// 示範資料的 `demo-period-01` 過不了這條——沒關係，示範模式下根本不顯示「前往官網」
    /// （見 App 端 `SiteHandoffOpener`）。
    private static let taskIDPattern = #"^[0-9a-fA-F-]{1,64}$"#

    private static let tasksPath = "/member/tasks"

    /// 任務清單頁。`SiteConfig.base` 是寫死的常數，這個 URL 不可能組不出來——
    /// `!` 只出現在這一行，其他所有路徑組不出來時都退到它。
    private static let tasksURL = URL(string: SiteConfig.base + tasksPath)!

    /// 對應目的地的官網 URL。一律以 `SiteConfig.base` 為根，**絕不接受解析內容的任意字串當 URL**。
    ///
    /// `taskID` 驗證失敗時**退回 `.tasks`**，而不是回傳 nil：使用者仍該有一條路去官網，
    /// 只是少了「直接落在那一期」的便利；任務清單頁上照樣找得到那一期的按鈕。
    public static func url(for destination: SiteHandoffDestination) -> URL {
        switch destination {
        case .tasks:
            return tasksURL
        case .redeem(let taskID):
            return url(path: "/member/redeem/", taskID: taskID)
        case .voucher(let taskID):
            return url(path: "/member/voucher/", taskID: taskID)
        }
    }

    /// 這個錯誤是不是「官網結構對不上」，該走接手畫面。
    ///
    /// 只認 `.parsing` 與 `.csrfNotFound`：前者是 parser 在頁面裡找不到它認得的標記，
    /// 後者是頁面裡連 `_csrf` 都沒有——兩者都代表拿到的 HTML 不是我們寫 parser 時看到的那份。
    ///
    /// 其他錯誤各有自己對的文案，不要蓋掉：`.network` 那句「請確認網路連線」在那個情境下是對的；
    /// `.notLoggedIn` 有既有的重新登入流程；`.unexpectedResponse`／`.responseTooLarge`／
    /// `.blockedEgress` 是官網出狀況或連線被擋，不是改版。
    ///
    /// **已知的模糊地帶**：session 過期時官網會 302 到登入頁、回 200 登入頁 HTML，parser 一樣
    /// 丟 `.parsing`——跟改版長得一模一樣。這裡不試圖分辨（那要看 HTML 內容，屬 parser 的事）；
    /// 文案因此寫「**可能**已改版」，而交接到官網這件事在兩種情境下都是對的。
    public static func shouldHandoff(_ error: Error) -> Bool {
        guard let appError = error as? AppError else { return false }
        switch appError {
        case .parsing, .csrfNotFound:
            return true
        case .network, .unexpectedResponse, .notLoggedIn, .blockedEgress, .responseTooLarge:
            return false
        }
    }

    /// `taskID` 是否長得像 parser 會吐出來的期別 id。空字串、含任何非 `[0-9a-fA-F-]` 的字元、
    /// 或超過 `maxTaskIDLength` 都不算。**刻意不 trim**：parser 不會給出帶空白的 id，
    /// 帶了就是別的東西。
    static func isValidTaskID(_ taskID: String) -> Bool {
        taskID.range(of: taskIDPattern, options: .regularExpression) != nil
    }

    private static func url(path: String, taskID: String) -> URL {
        guard isValidTaskID(taskID) else { return tasksURL }
        // 字元已限定在白名單內，`URL(string:)` 不會失敗也不會做任何百分比編碼；
        // `?? tasksURL` 只是不想在這裡放第二個 `!`。
        return URL(string: SiteConfig.base + path + taskID) ?? tasksURL
    }
}
