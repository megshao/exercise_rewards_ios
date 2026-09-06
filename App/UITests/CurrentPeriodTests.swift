import XCTest

/// 只驗這次改動的 UI 行為：「本週任務」會不會跟著日曆前進。
///
/// 刻意**不拍截圖、不走完整流程**——上架素材那條長路徑在 `ScreenshotTests`，
/// 這裡只碰首頁與任務頁這兩個真的被改到的畫面。
///
/// ## 重跑指令
/// ```sh
/// cd App && xcodebuild test -project SportsRewards.xcodeproj \
///   -scheme SportsRewardsScreenshots \
///   -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
///   -only-testing:SportsRewardsUITests/CurrentPeriodTests
/// ```
///
/// **能驗到什麼、驗不到什麼**：示範資料的第 6 期永遠等於「本週」，所以這裡驗得到
/// 「當期依日期前進」這個回報的 bug。但示範資料裡**沒有**「已過期卻仍可上傳」的期別
/// （過去的 5 期都已走完審核），因此上傳鈕的過期防護只有 `TaskPeriodDatesTests`
/// 的邏輯測試守著，UI 這一層沒有涵蓋。
@MainActor
final class CurrentPeriodTests: XCTestCase {

    private let timeout: TimeInterval = 25

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 示範資料第 6 期的起訖日字串，用跟 App 端同一套規則算出來
    /// （台北時區、週一為一週之始、官網格式 `yyyy/MM/dd`）。
    private var thisWeekRange: (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        calendar.firstWeekday = 2

        let monday = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
        let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!

        func format(_ date: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!)
        }
        return (format(monday), format(sunday))
    }

    /// 首頁的「本週任務」卡必須是**涵蓋今天**的那一期。
    ///
    /// 修正前這裡會是第 1 期——那是清單裡第一個非「尚未開始」的期別，
    /// 而它一旦兌換完就永遠是第一個，當期整季不再前進。
    func testHomeShowsThePeriodThatContainsToday() {
        let app = launchDemo()

        XCTAssertTrue(app.staticTexts["本週任務"].waitForExistence(timeout: timeout), "首頁沒載入")
        XCTAssertTrue(app.staticTexts["第 6 期"].waitForExistence(timeout: timeout),
                      "本週任務不是第 6 期（示範資料的當期）")

        let range = thisWeekRange
        XCTAssertTrue(app.staticTexts["\(range.start) ~ \(range.end)"].waitForExistence(timeout: timeout),
                      "本週任務卡上的日期不是本週（預期 \(range.start) ~ \(range.end)）")

        // 已經過完的第 1 期不該再被當成本週。
        XCTAssertFalse(app.staticTexts["第 1 期"].exists, "首頁把已結束的第 1 期當成本週任務")
    }

    /// 任務頁置頂高亮的那一期同樣要是當期，而且它才是唯一給上傳鈕的期別。
    func testTasksPageHighlightsTheCurrentPeriodAndOffersUploadOnlyThere() {
        let app = launchDemo()
        app.tabBars.buttons["任務"].tap()

        XCTAssertTrue(app.navigationBars["我的任務"].waitForExistence(timeout: timeout), "任務頁沒載入")

        let uploadButtons = app.buttons.matching(identifier: "上傳運動紀錄")
        XCTAssertTrue(uploadButtons.firstMatch.waitForExistence(timeout: timeout),
                      "當期沒有「上傳運動紀錄」按鈕")
        XCTAssertEqual(uploadButtons.count, 1, "只有當期可以上傳，不該出現第二顆上傳鈕")

        let range = thisWeekRange
        XCTAssertTrue(app.staticTexts["\(range.start) ~ \(range.end)"].waitForExistence(timeout: timeout),
                      "置頂高亮的不是本週那一期")
    }

    // MARK: - Helper

    /// 直接以示範狀態啟動（跳過導覽與免責聲明），參數語意見 `ScreenshotTests.launch`。
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoModeEnabled", "YES",
            "-hasCompletedOnboarding", "YES",
            // 免責聲明的當前版本號，真相來源是 App 端的 `DisclaimerConsent.currentVersion`。
            "-disclaimerAgreedVersion", "1",
            "-hasSeenWelcome", "YES",
            "-AppleLanguages", "(zh-Hant)",
            "-AppleLocale", "zh_Hant_TW",
        ]
        app.launch()
        return app
    }
}
