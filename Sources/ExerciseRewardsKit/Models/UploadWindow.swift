import Foundation

// MARK: - 「這一期現在還能不能上傳」

extension TaskPeriod {
    /// 這一期現在還能不能上傳運動紀錄。
    ///
    /// **這裡踩過的坑**（2026-09-07 回報）：官網對「上傳窗早就關掉」的期別**照樣回
    /// `NOT_UPLOADED`**（`TaskParser` 對應到 `.open`），而且照樣附上「本期任務可上傳時間
    /// 剩 N 小時 N 分」那串倒數——同一批實測資料裡，一張 `2026/09/01 ~ 2026/09/06` 的卡片在
    /// 9/7 仍然長這樣。App 這邊「能不能上傳」只看 `state`，於是過期未上傳的期別照樣畫出
    /// 「上傳運動紀錄」按鈕：使用者要一路點進上傳頁、從相簿挑好照片、按下「確認上傳」，
    /// 才會被 `UploadService.upload`（上傳頁沒有 `name="screenshot"` 欄位 → `.windowClosed`）
    /// 擋下來。那是**事後攔截，不是預防**，而且白白讓使用者選了一次照片。
    ///
    /// 也就是說「能不能上傳」是**狀態與日曆的合取**，不是 `state` 單獨回答得了的問題。
    ///
    /// **為什麼這條規則放在 Kit、而不是留在 View 裡的一個 `if`**：跟
    /// `TaskState.showsUploadCountdown`、`TaskPeriod.current(in:now:)` 同一個理由——它是
    /// 領域規則而非排版。而且很現實：App target 沒有單元測試 target，寫在
    /// `TasksView`／`HomeView` 的 `private` 卡片裡的分支，**沒有任何測試搆得到**
    /// （UI 測試也搆不到——示範資料的 14 期裡沒有「已過期但仍 `.open`」的期別，
    /// 見 `MockTasksService.sample(now:)`）。搬到這裡它才有 `UploadWindowTests` 守著。
    ///
    /// **刻意不加「這一期已經開始了嗎」這個條件**：官網對還沒開始的期別回的是
    /// `NOT_STARTED`（→ `.notStarted`），正常路徑走不到這裡；真要出現「`.open` 卻還沒到起日」
    /// 那也是官網自己說可以上傳，寧可讓它送出去由伺服器判，也不要在 App 端自作主張多擋一層。
    /// 這個取捨與下面那條降級規則是同一個方向：**只擋官網明確說已經結束的，不擋看不懂的。**
    ///
    /// 日期解析不出來時 `hasEnded(now:)` 回 `false`（理由見它自己的註解），因此這裡會回
    /// `true`——官網哪天改了日期格式，行為退化成 v1.0.0 的舊樣子（按鈕留著、由伺服器擋），
    /// 而不是反過來把一個還開著的窗誤擋掉。官網的 markup 不是契約（見 commit `c2db9b4`）。
    ///
    /// - Parameter now: 判斷基準時間。日期一律以台北時間解讀（見 `activityCalendar`）。
    public func canUpload(now: Date) -> Bool {
        state == .open && !hasEnded(now: now)
    }
}
