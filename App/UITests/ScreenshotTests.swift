import XCTest

/// 上架素材用的原始畫面截圖擷取流程（App Store Connect 需要 6.9" iPhone 直向截圖）。
///
/// 這支測試**只負責拍照**，不做斷言式驗收：它依序把 App 導覽到每一個要交付的畫面，
/// 在畫面穩定後呼叫 `XCUIScreen.main.screenshot()`，輸出 1320×2868 的 PNG。
///
/// 一律在**示範模式**下拍攝（`DemoMode`）：全部服務換成 `Mock*Service`，不發任何網路請求，
/// 畫面上是穩定的假資料，也不會有任何真實個資出現在素材裡。
///
/// ## 重跑指令
/// ```sh
/// cd App && xcodegen generate && \
///   xcodebuild test -project SportsRewards.xcodeproj -scheme SportsRewardsScreenshots \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
/// ```
/// 輸出目錄由 scheme（`project.yml` 的 `SportsRewardsScreenshots` test action）帶的環境變數
/// `SCREENSHOT_OUTPUT_DIR` 決定，預設是 `docs/screenshots/raw`；要換路徑就在指令尾端加
/// `TEST_RUNNER_SCREENSHOT_OUTPUT_DIR=<絕對路徑>` 覆蓋。無論寫檔成不成功，每張截圖都會
/// 以 `XCTAttachment`（`.keepAlways`）附進 `.xcresult`，可用
/// `xcrun xcresulttool export attachments --path <.xcresult> --output-path <dir>` 事後匯出。
///
/// 跑之前的兩件前置（各做一次就好，模擬器會記住）：
/// 1. 上傳頁那張需要相簿裡有圖：`xcrun simctl addmedia <udid> <某張 png>`
///    （可直接用 `App/Resources/DemoScreenshot.png`）。
/// 2. 乾淨狀態列：
///    `xcrun simctl status_bar <udid> override --time 9:41 --wifiBars 3 --cellularBars 4 \
///     --batteryState charged --batteryLevel 100`
///
/// 已驗證：模擬器可以直接寫檔到 host 的絕對路徑，所以 PNG 會直接落在 docs/screenshots/raw，
/// 不需要再從 .xcresult 匯出（附件仍會保留當備援）。
@MainActor
final class ScreenshotTests: XCTestCase {

    // MARK: - 設定

    /// 每個等待步驟的逾時。Mock 服務刻意有 0.4~0.5 秒延遲，健康頁還會連抓 7 天資料。
    private let timeout: TimeInterval = 25

    /// 寫檔目的地（由 `TEST_RUNNER_SCREENSHOT_OUTPUT_DIR` 指定）。沒設定就只走 XCTAttachment。
    private lazy var outputDirectory: URL? = {
        guard let path = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    /// 記錄哪些截圖成功寫到 host，最後一次印出來方便對帳。
    private var writtenFiles: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        if !writtenFiles.isEmpty {
            print("📸 已寫出截圖：\n" + writtenFiles.joined(separator: "\n"))
        }
        super.tearDown()
    }

    // MARK: - 主流程

    /// 依序拍完上架要用的 13 張畫面。刻意寫成單一測試方法，讓導覽順序固定、可重現。
    func testCaptureAppStoreScreenshots() throws {
        try captureOnboardingAndLogin()
        try captureMainFlow()
    }

    // MARK: - 第一段：Onboarding 導覽 + 個資填寫

    /// 以「尚未完成導覽、非示範模式」的乾淨狀態啟動，拍歡迎頁與個資填寫頁。
    private func captureOnboardingAndLogin() throws {
        let app = launch(demoMode: false, hasCompletedOnboarding: false)

        // 01 歡迎頁：品牌標題 + 一句隱私訴求（資料只存這支手機）。
        XCTAssertTrue(app.buttons["開始使用"].waitForExistence(timeout: timeout), "找不到「開始使用」")
        settle()
        capture(app, name: "01-onboarding")

        // 進入個資填寫頁，填入 App Store 審查用的示範三碼（DemoMode 的哨兵值，非真人個資）。
        app.buttons["開始使用"].tap()

        // 填寫順序刻意安排成「手機 → 出生日期 → 身分證」：
        // 手機是數字鍵盤（沒有 return 鍵，收不掉），身分證是一般鍵盤，最後在它上面按一次
        // return 就能把鍵盤收乾淨——不然截圖會被鍵盤蓋掉半個畫面。
        let phoneField = app.textFields["手機號碼"]
        XCTAssertTrue(phoneField.waitForExistence(timeout: timeout), "找不到手機號碼欄位")
        phoneField.tap()
        phoneField.typeText("0900000000")

        // 出生日期用自製滾輪（不吃系統語系），預設就是 1990/1/1＝示範帳號生日，直接按「完成」。
        app.buttons["出生日期"].tap()
        let doneButton = app.buttons["完成"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: timeout), "出生日期滾輪沒出現")
        doneButton.tap()

        let idField = app.textFields["身分證號"]
        XCTAssertTrue(idField.waitForExistence(timeout: timeout), "找不到身分證號欄位")
        idField.tap()
        idField.typeText("A000000000\n")

        // 02 登入／個資填寫頁：三欄皆已填、綠色隱私聲明、送出按鈕。
        settle(1.2)
        capture(app, name: "02-login")

        app.terminate()
    }

    // MARK: - 第二段：示範模式下的主要畫面

    /// 直接以示範狀態啟動（跳過導覽），逐一拍首頁 / 任務 / 健康 / 上傳 / 兌換 / 券夾 / 券碼 / 我的資料。
    private func captureMainFlow() throws {
        let app = launch(demoMode: true, hasCompletedOnboarding: true)

        captureHome(app)
        captureTasks(app)
        captureHealth(app)
        captureUpload(app)
        captureTaskScreenshot(app)
        captureRedeem(app)
        captureWalletAndVoucher(app)
        captureProfile(app)
    }

    /// 03 首頁：步數環（示範資料 9,688 步 / 目標 8,000）＋ 本週任務摘要卡。
    private func captureHome(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["本週任務"].waitForExistence(timeout: timeout), "首頁沒載入")
        // 等健康摘要與任務資料都回來（Mock 有延遲），避免拍到讀取中的占位圖。
        _ = app.staticTexts["9688"].waitForExistence(timeout: timeout)
        _ = app.staticTexts["第 6 期"].waitForExistence(timeout: timeout)
        settle(1.2)
        capture(app, name: "03-home")
    }

    /// 04 + 04b 任務儀表板：14 期卡片、狀態徽章、本週那期置頂高亮（含捲動後的版本）。
    private func captureTasks(_ app: XCUIApplication) {
        app.tabBars.buttons["任務"].tap()
        XCTAssertTrue(app.navigationBars["我的任務"].waitForExistence(timeout: timeout), "任務頁沒載入")
        _ = app.buttons["上傳運動紀錄"].waitForExistence(timeout: timeout)
        settle(1.2)
        capture(app, name: "04-tasks")

        // 04b 往下捲一段：讓 14 期的清單長度看得出來（審核中 / 尚未開始的期別）。
        app.swipeUp()
        app.swipeUp()
        settle(1.5)
        capture(app, name: "04b-tasks-scrolled")

        // 捲回頂端，後面的步驟才點得到第 6 期那顆「上傳運動紀錄」。
        app.swipeDown()
        app.swipeDown()
        app.swipeDown()
        settle(1.2)
    }

    /// 05 健康數據：步數環、達標百分比、三張指標卡、達標徽章。
    /// 這頁會連續抓 7 天資料算本週平均，等待時間拉長。
    private func captureHealth(_ app: XCUIApplication) {
        app.tabBars.buttons["健康"].tap()
        XCTAssertTrue(app.navigationBars["健康數據"].waitForExistence(timeout: timeout), "健康頁沒載入")
        _ = app.staticTexts["今日已符合任務條件"].waitForExistence(timeout: timeout)
        settle(1.2)
        capture(app, name: "05-health")
    }

    /// 06 上傳運動紀錄：從任務頁「上傳運動紀錄」進入，選一張相簿裡的示範截圖後拍預覽 + 確認上傳。
    /// 相簿內容由外部先用 `xcrun simctl addmedia` 塞好；若相片選擇器沒有可選項目，
    /// 就退回拍未選圖的狀態（畫面仍有說明卡與選擇按鈕，不是空白）。
    private func captureUpload(_ app: XCUIApplication) {
        app.tabBars.buttons["任務"].tap()
        let uploadButton = app.buttons["上傳運動紀錄"]
        XCTAssertTrue(uploadButton.waitForExistence(timeout: timeout), "找不到「上傳運動紀錄」")
        uploadButton.tap()

        let pickButton = app.buttons["從相簿選擇截圖"]
        XCTAssertTrue(pickButton.waitForExistence(timeout: timeout), "上傳頁沒載入")
        pickButton.tap()

        if let photo = firstPhotoCell(in: app) {
            // 用中心座標點，而不是 element.tap()：照片格子在無障礙樹上常被判為 not hittable。
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            // 單選的 PHPicker 點完就關閉；少數版本還要再按一次確認鈕。
            if !app.buttons["確認上傳"].waitForExistence(timeout: 8) {
                for label in ["加入", "完成", "Add", "Done"] where app.buttons[label].exists {
                    app.buttons[label].tap()
                    break
                }
                _ = app.buttons["確認上傳"].waitForExistence(timeout: timeout)
            }
            print("ℹ️ 上傳頁預覽狀態：確認上傳按鈕 exists=\(app.buttons["確認上傳"].exists)")
        } else {
            // 相片選擇器沒東西可選：關掉它，至少拍到上傳頁本身。
            print("⚠️ 相片選擇器找不到可選照片，改拍未選圖狀態")
            dismissPhotoPickerIfNeeded(app)
        }

        settle(1.5)
        capture(app, name: "06-upload")

        app.buttons["關閉"].tap()
        _ = app.navigationBars["我的任務"].waitForExistence(timeout: timeout)
    }

    /// 07 看截圖：回顧這期上傳的運動紀錄截圖。
    /// 示範模式下 `MockTasksService` 回傳的是 App bundle 內的示範圖 file URL，不會連外。
    private func captureTaskScreenshot(_ app: XCUIApplication) {
        let button = app.buttons["看截圖"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "找不到「看截圖」")
        button.tap()
        XCTAssertTrue(app.navigationBars["上傳截圖"].waitForExistence(timeout: timeout), "看截圖頁沒載入")
        // AsyncImage 載入本地圖也要一點時間，多等一下再拍。
        settle(2.5)
        capture(app, name: "07-task-screenshot")

        app.buttons["關閉"].tap()
        _ = app.navigationBars["我的任務"].waitForExistence(timeout: timeout)
    }

    /// 08 兌換好禮：從可兌換那期進入，列出合作商家品項。
    private func captureRedeem(_ app: XCUIApplication) {
        let redeemButton = app.buttons["立即兌換"]
        XCTAssertTrue(redeemButton.waitForExistence(timeout: timeout), "找不到「立即兌換」")
        redeemButton.tap()

        XCTAssertTrue(app.staticTexts["全家便利商店"].waitForExistence(timeout: timeout), "兌換清單沒載入")
        settle(1.2)
        capture(app, name: "08-redeem")

        // 兌換頁沒有「關閉」鈕（設計上靠下滑關閉 sheet），這裡模擬下滑手勢。
        dismissSheetByDragging(app)
        _ = app.navigationBars["我的任務"].waitForExistence(timeout: timeout)
    }

    /// 09 券夾清單 + 10 加碼券券碼（需先完成簡訊 OTP 才會出示條碼）。
    private func captureWalletAndVoucher(_ app: XCUIApplication) {
        app.tabBars.buttons["券夾"].tap()
        XCTAssertTrue(app.navigationBars["我的券夾"].waitForExistence(timeout: timeout), "券夾沒載入")
        _ = app.staticTexts["可使用的加碼券"].waitForExistence(timeout: timeout)
        settle(1.2)
        capture(app, name: "09-wallet")

        // 進券碼頁：發送驗證碼 → 輸入 6 碼（Mock 任何 6 碼都會通過）→ 出示條碼。
        app.buttons["檢視券碼"].firstMatch.tap()
        let sendButton = app.buttons["發送簡訊驗證碼"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: timeout), "券碼頁沒載入")
        sendButton.tap()

        let otpField = app.textFields["otpCodeField"]
        XCTAssertTrue(otpField.waitForExistence(timeout: timeout), "OTP 欄位沒出現")
        otpField.tap()
        otpField.typeText("123456")

        let reveal = app.buttons["voucherRevealButton"]
        XCTAssertTrue(reveal.waitForExistence(timeout: timeout), "找不到「檢視券碼」按鈕")
        reveal.tap()

        // 條碼由 CoreImage 產生，等第一段條碼的號碼文字出現代表已進到 showing 狀態。
        XCTAssertTrue(app.staticTexts["① 商品條碼"].waitForExistence(timeout: timeout), "券碼沒顯示")
        settle(1.5)
        capture(app, name: "10-voucher")

        app.buttons["關閉"].tap()
        _ = app.navigationBars["我的券夾"].waitForExistence(timeout: timeout)
    }

    /// 11 我的資料（上半：隱私三點聲明 + 三個遮罩欄位）
    /// 12 我的資料（下半：安全與隱私區塊）——一個 6.9" 螢幕放不下，所以拍兩張。
    private func captureProfile(_ app: XCUIApplication) {
        app.tabBars.buttons["首頁"].tap()
        let profileButton = app.buttons["我的資料"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: timeout), "找不到「我的資料」入口")
        profileButton.tap()

        XCTAssertTrue(app.navigationBars["我的資料"].waitForExistence(timeout: timeout), "我的資料頁沒載入")
        _ = app.staticTexts["個資不外傳，健康資料不出這支手機"].waitForExistence(timeout: timeout)
        settle(1.2)
        capture(app, name: "11-profile")

        // 往下捲到「安全與隱私」（本機資料 / 立即清除本機資料 / 離開示範模式）。
        app.swipeUp()
        settle(1.5)
        capture(app, name: "12-profile-security")
    }

    // MARK: - 工具

    /// 用固定的啟動參數啟動 App，讓每次跑的初始狀態都一樣。
    /// - `-demoModeEnabled`：`DemoMode.storageKey`，YES 代表整個 App 走 Mock 服務、不連網。
    /// - `-hasCompletedOnboarding`：`RootView` 用來決定要不要先跑一次導覽。
    ///
    /// 這兩個值是走 `NSArgumentDomain`，優先權高於 App 自己寫進 UserDefaults 的值，
    /// 因此不會被上一次執行留下的狀態污染。
    private func launch(demoMode: Bool, hasCompletedOnboarding: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoModeEnabled", demoMode ? "YES" : "NO",
            "-hasCompletedOnboarding", hasCompletedOnboarding ? "YES" : "NO",
            // 素材一律繁體中文（台灣）。
            "-AppleLanguages", "(zh-Hant)",
            "-AppleLocale", "zh_Hant_TW",
            // 截圖模式：收起示範模式橫幅，讓素材的畫面上緣乾淨（見 App 端的 ScreenshotMode）。
            // 只有這裡（XCUITest 啟動 App 時）給得出這個參數，真機使用者無從觸發。
            "-uiTestScreenshotMode",
        ]
        app.launch()
        return app
    }

    /// 拍一張全螢幕截圖：附進 .xcresult，並（若有指定輸出目錄）直接寫成 host 上的 PNG。
    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = outputDirectory else {
            print("ℹ️ 未設定 SCREENSHOT_OUTPUT_DIR，\(name) 只存進 .xcresult 附件")
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(name).png")
            try screenshot.pngRepresentation.write(to: url, options: .atomic)
            writtenFiles.append(url.path)
        } catch {
            // 寫不進 host 路徑不算失敗——.xcresult 裡還有附件可以事後匯出。
            print("⚠️ 無法寫入 \(name).png：\(error)")
        }
    }

    /// 等畫面動畫與非同步資料穩定下來再拍，避免拍到轉場中的半透明畫面。
    private func settle(_ seconds: TimeInterval = 0.8) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// 找出系統相片選擇器（PHPickerViewController）裡的第一張照片。
    ///
    /// iOS 26 的照片格子是 `Image` 元素、identifier 為 `PXGGridLayout-Info`（實測自
    /// `app.debugDescription`）。identifier 是私有實作細節，所以後面再備幾種以 label
    /// 開頭字串比對的查法；全部落空就回 nil，由呼叫端退回「未選圖」的截圖。
    /// 注意不要用 `app.scrollViews.images.firstMatch` 這種寬鬆查法——它會先命中上傳頁
    /// 自己那顆按鈕裡的 SF Symbol。
    private func firstPhotoCell(in app: XCUIApplication) -> XCUIElement? {
        let queries: [XCUIElementQuery] = [
            app.images.matching(identifier: "PXGGridLayout-Info"),
            app.images.matching(NSPredicate(format: "label BEGINSWITH '照片'")),
            app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")),
            app.cells.images,
        ]
        for query in queries {
            let element = query.firstMatch
            // 這裡只看 exists 不看 isHittable：照片格子是自繪的 PXG 圖層，
            // isHittable 常回 false，但用座標點下去是可以選取的。
            if element.waitForExistence(timeout: 8) { return element }
        }
        return nil
    }

    /// 相片選擇器沒有可選項目時，把它關掉（不同版本的取消鈕文字不同，都試一次）。
    private func dismissPhotoPickerIfNeeded(_ app: XCUIApplication) {
        for label in ["取消", "Cancel"] where app.buttons[label].exists {
            app.buttons[label].tap()
            return
        }
        dismissSheetByDragging(app)
    }

    /// 沒有關閉鈕的 sheet：從畫面上緣往下拖曳關閉。
    private func dismissSheetByDragging(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        start.press(forDuration: 0.05, thenDragTo: end)
        settle(1.0)
    }
}
