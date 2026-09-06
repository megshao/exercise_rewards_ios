import XCTest
@testable import SportsRewardsKit

/// 驗證 `TaskPeriod` 的日期區間解析。
///
/// 這一整組能力在 v1.0.0 之前不存在：`startDate`／`endDate` 是 `String`，全 App 沒有一處
/// 讀過它們，導致「本週是哪一期」與「上傳窗還開著嗎」兩件事都只能靠狀態猜。
final class TaskPeriodDatesTests: XCTestCase {

    /// 以台北時間組出一個時刻，測試才不會受跑測試那台機器的時區影響。
    private func taipei(_ year: Int, _ month: Int, _ day: Int,
                        _ hour: Int = 0, _ minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return TaskPeriod.activityCalendar.date(from: components)!
    }

    private func period(_ start: String, _ end: String, state: TaskState = .open) -> TaskPeriod {
        TaskPeriod(id: "id", index: 1, startDate: start, endDate: end, state: state)
    }

    // MARK: - 區間邊界

    func testSpanStartsAtMidnightOfStartDate() {
        let span = period("2026/09/01", "2026/09/06").dateSpan
        XCTAssertEqual(span?.start, taipei(2026, 9, 1, 0, 0))
    }

    /// `endDate` 是**包含**當天的，所以上界要落在隔天零點。
    func testSpanEndsAtMidnightAfterEndDate() {
        let span = period("2026/09/01", "2026/09/06").dateSpan
        XCTAssertEqual(span?.end, taipei(2026, 9, 7, 0, 0))
    }

    // MARK: - isCurrent / hasEnded

    func testLastDayBeforeMidnightIsStillCurrent() {
        let sut = period("2026/09/01", "2026/09/06")
        XCTAssertTrue(sut.isCurrent(now: taipei(2026, 9, 6, 23, 59)))
        XCTAssertFalse(sut.hasEnded(now: taipei(2026, 9, 6, 23, 59)))
    }

    /// 這就是回報的情境：9/7 一到，9/1~9/6 那期必須算結束。
    func testPeriodHasEndedTheDayAfterItsEndDate() {
        let sut = period("2026/09/01", "2026/09/06")
        XCTAssertFalse(sut.isCurrent(now: taipei(2026, 9, 7, 0, 0)))
        XCTAssertTrue(sut.hasEnded(now: taipei(2026, 9, 7, 0, 0)))
    }

    func testFirstDayIsCurrentFromMidnight() {
        let sut = period("2026/09/07", "2026/09/13")
        XCTAssertTrue(sut.isCurrent(now: taipei(2026, 9, 7, 0, 0)))
    }

    func testBeforeStartIsNeitherCurrentNorEnded() {
        let sut = period("2026/09/07", "2026/09/13")
        XCTAssertFalse(sut.isCurrent(now: taipei(2026, 9, 6, 23, 59)))
        XCTAssertFalse(sut.hasEnded(now: taipei(2026, 9, 6, 23, 59)))
    }

    /// 單日期別（官網第 14 期就是 `2026/11/30 ~ 2026/11/30`）不能被算成空區間。
    func testSingleDayPeriodCoversThatWholeDay() {
        let sut = period("2026/11/30", "2026/11/30")
        XCTAssertTrue(sut.isCurrent(now: taipei(2026, 11, 30, 23, 59)))
        XCTAssertTrue(sut.hasEnded(now: taipei(2026, 12, 1, 0, 0)))
    }

    // MARK: - 解析失敗一律降級，不得誤擋

    /// 官網若改格式，`dateSpan` 要回 nil，而不是硬湊出一個錯的區間。
    func testUnparseableDatesYieldNoSpan() {
        let malformed = ["09/01", "", "2026-09-01", "2026/09", "2026/09/01/02",
                         "yyyy/MM/dd", "2026/13/01", "2026/02/30", "202/09/01"]
        for value in malformed {
            XCTAssertNil(period(value, "2026/09/06").dateSpan, "起日 \(value) 不該解析成功")
            XCTAssertNil(period("2026/09/01", value).dateSpan, "訖日 \(value) 不該解析成功")
        }
    }

    /// 日期不可用時 `hasEnded` 必須是 false——寧可留著上傳鈕讓伺服器擋，
    /// 也不要因為官網換了格式就把還開著的窗誤判成已結束。
    func testUnparseableDatesNeverReportEnded() {
        let sut = period("09/01", "09/06")
        XCTAssertFalse(sut.hasEnded(now: taipei(2030, 1, 1)))
        XCTAssertFalse(sut.isCurrent(now: taipei(2030, 1, 1)))
    }

    /// 起訖顛倒視為無效，否則會得到一個負長度的區間。
    func testReversedRangeIsRejected() {
        XCTAssertNil(period("2026/09/06", "2026/09/01").dateSpan)
    }

    /// 日期一律以台北時間解讀，不跟著裝置時區跑：使用者在 UTC-8 的地方打開 App，
    /// 台北時間 9/7 00:30 仍然屬於 9/7 那一期。
    func testDatesAreInterpretedInTaipeiRegardlessOfDeviceTimeZone() {
        let span = period("2026/09/07", "2026/09/13").dateSpan
        // 台北 9/7 00:00 == UTC 9/6 16:00
        XCTAssertEqual(span?.start, Date(timeIntervalSince1970: 1_788_710_400))
    }
}
