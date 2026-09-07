import XCTest
@testable import ExerciseRewardsKit

/// 驗證 `TaskPeriod.current(in:now:)`——首頁「本週任務」與任務頁置頂高亮的唯一依據。
///
/// v1.0.0 的規則是「第一個非 `.notStarted` 的期別」，完全不看日期，而且**沒有任何測試**
/// 覆蓋它。這個檔案就是補上那張網。
final class PeriodSelectionTests: XCTestCase {

    private func taipei(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        TaskPeriod.activityCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 官網實際的排法：1→14 遞增，第 1 期是 9/1~9/6（6 天的首期），其後每期週一～週日。
    private func officialSchedule(states: [Int: TaskState] = [:]) -> [TaskPeriod] {
        let ranges: [(String, String)] = [
            ("2026/09/01", "2026/09/06"), ("2026/09/07", "2026/09/13"),
            ("2026/09/14", "2026/09/20"), ("2026/09/21", "2026/09/27"),
            ("2026/09/28", "2026/10/04"), ("2026/10/05", "2026/10/11"),
        ]
        return ranges.enumerated().map { offset, range in
            TaskPeriod(id: "id-\(offset + 1)", index: offset + 1,
                       startDate: range.0, endDate: range.1,
                       state: states[offset + 1] ?? .notStarted)
        }
    }

    // MARK: - 回報的 bug

    /// **回報情境（2026-09-07）**：第 1 期 9/1~9/6 已 `REDEEMABLE`、第 2 期 9/7~9/13 仍
    /// `NOT_STARTED`。舊規則會選中第 1 期，首頁「本週任務」因此顯示已經過完的那一週。
    func testCurrentWeekAdvancesEvenWhenTheNewPeriodIsStillNotStarted() {
        let periods = officialSchedule(states: [1: .redeemable])
        let current = TaskPeriod.current(in: periods, now: taipei(2026, 9, 7))
        XCTAssertEqual(current?.index, 2)
        XCTAssertEqual(current?.startDate, "2026/09/07")
    }

    /// 9/6 當天還在第 1 期——修正不能把當期提早翻過去。
    func testCurrentWeekStillPointsAtPeriodOneOnItsLastDay() {
        let periods = officialSchedule(states: [1: .redeemable])
        XCTAssertEqual(TaskPeriod.current(in: periods, now: taipei(2026, 9, 6, 23))?.index, 1)
    }

    /// 舊規則真正的規模：第 1 期一旦不是 `.notStarted` 就**永遠**被選中。
    /// 逐週往前走，當期必須跟著前進，不能整季卡在第 1 期。
    func testCurrentWeekKeepsAdvancingAcrossTheWholeSeason() {
        let periods = officialSchedule(states: [1: .redeemed, 2: .redeemed, 3: .redeemable])
        let expected: [(Date, Int)] = [
            (taipei(2026, 9, 3), 1), (taipei(2026, 9, 10), 2), (taipei(2026, 9, 17), 3),
            (taipei(2026, 9, 24), 4), (taipei(2026, 10, 1), 5), (taipei(2026, 10, 8), 6),
        ]
        for (now, index) in expected {
            XCTAssertEqual(TaskPeriod.current(in: periods, now: now)?.index, index,
                           "\(now) 應該落在第 \(index) 期")
        }
    }

    /// 陣列順序不該影響結果——官網哪天改成倒序排也一樣。
    func testResultDoesNotDependOnArrayOrder() {
        let periods = officialSchedule(states: [1: .redeemable])
        let reversed = Array(periods.reversed())
        XCTAssertEqual(TaskPeriod.current(in: reversed, now: taipei(2026, 9, 7))?.index, 2)
    }

    // MARK: - 活動邊界

    /// 活動還沒開始：顯示最早的一期，讓使用者看得到即將開始的任務。
    func testBeforeTheSeasonStartsShowsTheEarliestPeriod() {
        XCTAssertEqual(TaskPeriod.current(in: officialSchedule(), now: taipei(2026, 8, 20))?.index, 1)
    }

    /// 活動全部結束：停在最後一期，而不是變成空白。
    func testAfterTheSeasonEndsShowsTheLastPeriod() {
        let periods = officialSchedule(states: [1: .redeemed])
        XCTAssertEqual(TaskPeriod.current(in: periods, now: taipei(2027, 1, 1))?.index, 6)
    }

    func testEmptyInputYieldsNil() {
        XCTAssertNil(TaskPeriod.current(in: [], now: taipei(2026, 9, 7)))
    }

    // MARK: - 官網改格式時的退路

    /// 日期全部解析不出來時退回舊的狀態啟發式，而不是讓區塊空白。
    func testFallsBackToStateHeuristicWhenNoDateParses() {
        let periods = [
            TaskPeriod(id: "a", index: 1, startDate: "09/01", endDate: "09/06", state: .notStarted),
            TaskPeriod(id: "b", index: 2, startDate: "09/07", endDate: "09/13", state: .open),
        ]
        XCTAssertEqual(TaskPeriod.current(in: periods, now: taipei(2026, 9, 7))?.index, 2)
    }

    /// 只要**有一期**日期可用就走日期路徑，不因其他期別壞掉而整組降級。
    func testPartiallyParseableScheduleStillUsesDates() {
        var periods = officialSchedule(states: [1: .redeemable])
        periods[0].startDate = "壞掉的日期"
        XCTAssertEqual(TaskPeriod.current(in: periods, now: taipei(2026, 9, 7))?.index, 2)
    }
}
