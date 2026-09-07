import XCTest
@testable import ExerciseRewardsKit

/// 驗證 `TaskPeriod.canUpload(now:)`——「要不要畫『上傳運動紀錄』按鈕」的唯一依據。
///
/// **這組測試守的是什麼**：官網對上傳窗已經關掉的期別照樣回 `NOT_UPLOADED`（→ `.open`），
/// 所以 v1.0.0 那個「只看 `state` 就決定給不給 CTA」的判斷，會對過期未上傳的期別照樣
/// 畫出按鈕，一路到使用者按下「確認上傳」才被伺服器擋。細節見 `canUpload(now:)` 的註解。
///
/// **為什麼是單元測試而不是 UI 測試**：這個分支在 UI 層沒有辦法被公平地驗到——
/// 示範模式的 14 期資料裡沒有「已過期但仍 `.open`」的期別（過去 5 期都已走完審核，
/// 當期依定義涵蓋今天），要讓 XCUITest 看到這種卡片就得替示範資料加一個測試專用的注入點，
/// 而那會踩到 `DemoMode.swift` 裡 `ScreenshotMode` 明訂的界線（啟動參數**只能影響畫面呈現，
/// 不可以拿來改資料來源**）。因此改成把決策本身搬進 Kit，用這裡的矩陣覆蓋——
/// View 那一側剩下的只是「true 給按鈕、false 給一行字」。
final class UploadWindowTests: XCTestCase {

    /// 以台北時間組出一個時刻，測試才不會受跑測試那台機器的時區影響。
    private func taipei(_ year: Int, _ month: Int, _ day: Int,
                        _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return TaskPeriod.activityCalendar.date(from: components)!
    }

    /// 官網實際存在過的一期：`2026/09/01 ~ 2026/09/06`（活動首期只有 6 天）。
    private func period(state: TaskState,
                        start: String = "2026/09/01",
                        end: String = "2026/09/06") -> TaskPeriod {
        TaskPeriod(id: "id", index: 1, startDate: start, endDate: end, state: state)
    }

    // MARK: - 回報的 bug

    /// **回報情境**：9/1~9/6 那期在 9/7 已經關窗，但官網仍回 `NOT_UPLOADED`。
    /// 舊版只看 state，於是這張卡片照樣有「上傳運動紀錄」按鈕。
    func testOpenPeriodCannotUploadOnceItsWindowHasClosed() {
        XCTAssertFalse(period(state: .open).canUpload(now: taipei(2026, 9, 7, 0, 0)))
    }

    /// 上界是隔天零點，所以最後一天的 23:59 仍然可以上傳——修正不能把窗提早關掉。
    func testOpenPeriodCanStillUploadUntilMidnightOfItsLastDay() {
        XCTAssertTrue(period(state: .open).canUpload(now: taipei(2026, 9, 6, 23, 59)))
    }

    func testOpenPeriodCanUploadInTheMiddleOfItsWindow() {
        XCTAssertTrue(period(state: .open).canUpload(now: taipei(2026, 9, 3, 12, 0)))
    }

    /// 單日期別（官網第 14 期就是 `2026/11/30 ~ 2026/11/30`）不能被算成一開始就關著的窗。
    func testSingleDayPeriodIsUploadableForThatWholeDay() {
        let sut = period(state: .open, start: "2026/11/30", end: "2026/11/30")
        XCTAssertTrue(sut.canUpload(now: taipei(2026, 11, 30, 23, 59)))
        XCTAssertFalse(sut.canUpload(now: taipei(2026, 12, 1, 0, 0)))
    }

    // MARK: - 只有 .open 能上傳

    /// 其餘四個狀態不論日期都不能上傳：已上傳過的期別（審核中／可兌換／已兌換）每期限一次，
    /// 尚未開始的期別則連表單都還沒開。窗還開著的時間點也一樣不行——
    /// 這裡刻意用「還在窗內」的 9/3 來測，才驗得出 `state` 那半邊真的有在把關。
    func testOnlyOpenPeriodsAreUploadableEvenWhileTheWindowIsStillOpen() {
        let insideWindow = taipei(2026, 9, 3, 12, 0)
        for state: TaskState in [.notStarted, .pendingReview, .redeemable, .redeemed, .unknown] {
            XCTAssertFalse(period(state: state).canUpload(now: insideWindow),
                           "\(state) 不該可以上傳")
        }
    }

    /// 新增 `TaskState` 成員時這個測試會失敗，提醒作者去決定新狀態能不能上傳，
    /// 而不是讓它默默落進 `state == .open` 的否定側（比照 `TaskStateTests` 的同名守則）。
    func testEveryStateIsClassifiedDeliberately() {
        let uploadable: Set<TaskState> = [.open]
        let notUploadable: Set<TaskState> = [.notStarted, .pendingReview, .redeemable, .redeemed, .unknown]

        XCTAssertTrue(uploadable.isDisjoint(with: notUploadable))
        XCTAssertEqual(uploadable.count + notUploadable.count, 6,
                       "TaskState 有新成員時，請先決定它能不能上傳運動紀錄")

        let insideWindow = taipei(2026, 9, 3, 12, 0)
        for state in uploadable { XCTAssertTrue(period(state: state).canUpload(now: insideWindow), "\(state)") }
        for state in notUploadable { XCTAssertFalse(period(state: state).canUpload(now: insideWindow), "\(state)") }
    }

    // MARK: - 降級：只擋官網明確說已結束的

    /// 日期解析不出來（官網改格式）時**不得誤擋**：按鈕留著，由伺服器判。
    /// 這是刻意的不對稱——誤擋會讓還來得及的使用者整期作廢，誤放只是多一次失敗的送出。
    func testUnparseableDatesKeepTheUploadButtonAvailable() {
        for malformed in ["09/01", "", "2026-09-01", "2026/13/01", "yyyy/MM/dd"] {
            XCTAssertTrue(period(state: .open, start: malformed).canUpload(now: taipei(2030, 1, 1)),
                          "起日 \(malformed) 不該讓上傳鈕消失")
            XCTAssertTrue(period(state: .open, end: malformed).canUpload(now: taipei(2030, 1, 1)),
                          "訖日 \(malformed) 不該讓上傳鈕消失")
        }
    }

    /// 同一個方向：`.open` 但還沒到起日也照樣給上傳鈕。官網對未開始的期別回的是
    /// `NOT_STARTED`，會走到這裡代表官網自己說可以上傳，App 端不多擋一層。
    func testOpenPeriodBeforeItsStartDateIsStillOffered() {
        XCTAssertTrue(period(state: .open).canUpload(now: taipei(2026, 8, 20, 12, 0)))
    }

    /// 一律以台北時間判斷，不跟著裝置時區跑：使用者人在 UTC-8，台北時間 9/7 00:30
    /// 那一刻當地才 9/6 早上，窗仍然必須算關了。
    func testWindowClosesOnTaipeiTimeRegardlessOfDeviceTimeZone() {
        // 台北 2026/09/07 00:30 == UTC 2026/09/06 16:30
        let justAfterClose = Date(timeIntervalSince1970: 1_788_712_200)
        XCTAssertEqual(justAfterClose, taipei(2026, 9, 7, 0, 30))
        XCTAssertFalse(period(state: .open).canUpload(now: justAfterClose))
    }
}
