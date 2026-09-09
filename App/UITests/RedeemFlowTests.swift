import XCTest

/// 兌換流程的端到端回歸測試：兌換 → 確認 → 結果卡 → 檢視加碼券 → OTP 入口。
///
/// **為什麼需要它**：這條路徑原本零覆蓋，於是漏掉了一個「確認兌換完全沒作用」的 bug——
/// alert 的 `isPresented` binding 在 `set` 裡呼叫了會清空 `pendingOption` 的方法，
/// 而 SwiftUI 是先關 alert 再跑按鈕的 action，所以 `confirmRedeem()` 的 guard 永遠先失敗。
/// 畫面上「dialog 開得起來、關得掉」，但兌換從來沒送出去。
///
/// `ScreenshotTests` 摸不到這個 bug：它在兌換頁只點「兌換品項」就下滑關掉 sheet，
/// 而券碼頁（09／10）是從**券夾**進去的，走 `WalletView` 自己那條 sheet。
///
/// 示範模式走 `MockRedeemService`（`redeem()` 固定回傳 `submitted: true`），不打網路。
///
/// ## 重跑指令
/// ```sh
/// cd App && xcodebuild test -project ExerciseRewards.xcodeproj \
///   -scheme ExerciseRewardsScreenshots \
///   -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
///   -only-testing:ExerciseRewardsUITests/RedeemFlowTests
/// ```
@MainActor
final class RedeemFlowTests: XCTestCase {

    private let timeout: TimeInterval = 25

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 走完整條兌換路徑。每一步都各自斷言，失敗訊息要直接指出斷在哪一步——
    /// 「結果卡沒出現」與「sheet 開不起來」的成因完全不同，混在一起就失去診斷價值。
    func testRedeemThenViewVoucherEndToEnd() {
        let app = launchDemo()
        openRedeemPage(app)

        // 1：點「兌換」跳出二次確認。
        let redeemButton = app.buttons.matching(NSPredicate(format: "label == %@", "兌換")).firstMatch
        XCTAssertTrue(redeemButton.waitForExistence(timeout: timeout), "找不到「兌換」鈕")
        redeemButton.tap()
        let alert = app.alerts["確認兌換"]
        XCTAssertTrue(alert.waitForExistence(timeout: timeout), "「確認兌換」alert 沒出現")

        // 2：按下確認。
        let confirm = alert.buttons["確認兌換"]
        XCTAssertTrue(confirm.exists, "alert 上沒有「確認兌換」鈕")
        confirm.tap()

        // 3：結果卡。**這一步就是原本的迴歸點**——bug 在時整頁留在商家清單，
        // 既沒有結果卡也沒有失敗卡，因為 `confirmRedeem()` 根本沒往下走。
        XCTAssertTrue(
            app.staticTexts["已送出兌換，請完成簡訊驗證後檢視加碼券"].waitForExistence(timeout: timeout),
            "兌換結果卡沒出現——確認鈕可能又變成空操作了，先檢查 RedeemView 的 alert binding"
        )

        // 兌換頁是蓋在任務頁上的 sheet，而任務頁已兌換的卡片也有一顆同名的「檢視加碼券」，
        // 所以同名元素不只一個，直接 tap 會是「Multiple matching elements found」。
        // 被 sheet 蓋住的那顆不可點，用 isHittable 挑前景那顆。
        guard let voucherButton = frontVoucherButton(app) else {
            return XCTFail("結果卡上沒有可點的「檢視加碼券」")
        }

        // 4 + 5：開 VoucherView，停在 OTP 入口（券碼一律要重新驗證一次簡訊）。
        voucherButton.tap()
        XCTAssertTrue(app.navigationBars["我的加碼券"].waitForExistence(timeout: timeout),
                      "「檢視加碼券」的 sheet 沒有呈現")
        let sendOtp = app.buttons["發送簡訊驗證碼"]
        XCTAssertTrue(sendOtp.exists, "OTP 入口沒有「發送簡訊驗證碼」鈕")

        // 6：進到驗證碼輸入畫面。
        sendOtp.tap()
        XCTAssertTrue(app.staticTexts["簡訊驗證出示券碼"].waitForExistence(timeout: timeout),
                      "沒有進到簡訊驗證碼輸入畫面")
    }

    // MARK: - Helpers

    /// 畫面上第一顆**真的可點**的「檢視加碼券」（見呼叫端關於同名元素的說明）。
    private func frontVoucherButton(_ app: XCUIApplication) -> XCUIElement? {
        let matches = app.buttons.matching(identifier: "檢視加碼券")
        return (0..<matches.count)
            .map { matches.element(boundBy: $0) }
            .first { $0.exists && $0.isHittable }
    }

    private func openRedeemPage(_ app: XCUIApplication) {
        app.tabBars.buttons["任務"].tap()
        XCTAssertTrue(app.navigationBars["我的任務"].waitForExistence(timeout: timeout), "任務頁沒載入")
        let enter = app.buttons["立即兌換"]
        XCTAssertTrue(enter.waitForExistence(timeout: timeout), "找不到「立即兌換」")
        enter.tap()
        XCTAssertTrue(app.staticTexts["全家便利商店"].waitForExistence(timeout: timeout), "兌換清單沒載入")
    }

    /// 與 `CurrentPeriodTests.launchDemo()` 相同的示範狀態啟動參數。
    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoModeEnabled", "YES",
            "-hasCompletedOnboarding", "YES",
            "-disclaimerAgreedVersion", "1",
            "-hasSeenWelcome", "YES",
            "-AppleLanguages", "(zh-Hant)",
            "-AppleLocale", "zh_Hant_TW",
        ]
        app.launch()
        return app
    }
}
