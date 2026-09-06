import XCTest
@testable import SportsRewardsKit

/// **效能回歸測試。**
///
/// 四個 HTML parser 吃的都是官方站回傳的 HTML——那是**不受信任的輸入**。官網被入侵、
/// 或使用者裝置信任了 MITM 憑證（本專案刻意不做 certificate pinning，理由見 README）
/// 時，回一頁精心構造的 HTML 就能讓正規表示式進入災難性回溯。
///
/// 這不會 watchdog crash：`TasksService.fetchTasks` 是 nonisolated async，卡住的是
/// cooperative thread pool 而不是主執行緒。症狀是任務／券夾／首頁的所有抓取**永遠不會
/// 回來**、CPU 滿載耗電，直到使用者自己殺掉 App——一個沒有錯誤訊息、看不出原因的當機。
///
/// 修好之前的實測（`period-remaining">` 後接 N 個空白且無 `<`）：
/// N=200 → 51 ms、400 → 447 ms、800 → 4.1 秒、1600 → **33.6 秒**。每倍增約 8×，
/// 確認是 O(n³)。`上傳時間：` 與 `兌換期限：` 兩條更慢，1600 → **78／81 秒**。
///
/// **這些測試是唯一能防止有人日後把樣式改回舊寫法的保險。** 每個修過的樣式餵 4 KB
/// 對抗輸入，斷言 100 ms 內完成——修好之後實測全部 < 2 ms，100 ms 是給 CI 機器的餘裕。
/// 寫法比照 `SensitivePatternTests.testScrubVeryLongStringReturnsPromptly`。
///
/// 另一道獨立防線是 `URLSessionHTTPClient` 的 2 MB body 上限（見本檔最後一節）：
/// 逐條修 regex 擋不住之後新加的 parser，把輸入長度夾住才擋得住。
final class HTMLParserReDoSTests: XCTestCase {

    /// 對抗輸入的長度。遠大於任何真實欄位的量級。
    private static let adversarialLength = 4 * 1024
    /// 每個樣式的時間上限。修好之後實測都在 2 ms 以內。
    private static let budget: TimeInterval = 0.1

    /// 執行 `body` 並斷言在預算內完成。
    private func assertPrompt(
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () -> Void
    ) {
        let start = Date()
        body()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, Self.budget,
            "\(label)：4 KB 對抗輸入必須在 \(Self.budget) 秒內返回，實際花了 \(elapsed) 秒。"
                + "這代表樣式又出現了災難性回溯——檢查是不是有相鄰量詞的字元集合重疊"
                + "（例如 `\\s*([^<]+?)\\s*<`），或是有量詞少了長度上限。",
            file: file, line: line
        )
    }

    private var pad: String { String(repeating: " ", count: Self.adversarialLength) }
    private var digits: String { String(repeating: "1", count: Self.adversarialLength) }

    /// 一個合法的 `voucher-figure`，讓 `parseView` 不會在抓到 figure 之前就丟錯。
    private let figure =
        #"<section class="voucher-figure" data-format="CODE_128" data-value="X"></section>"#

    // MARK: - TaskParser

    /// 原 `period-remaining">\s*([^<]+?)\s*<`：`\s` ⊂ `[^<]`，三層量詞互相回溯。
    func testTaskParserRemainingTextWithUnterminatedWhitespace() {
        let html = #"<li class="period-card"><span class="period-remaining">"# + pad
        assertPrompt("TaskParser.period-remaining（純空白、無收尾 `<`）") {
            _ = try? TaskParser.parse(html: html)
        }
    }

    /// 空白與非空白交錯的變體（實測最慢的一種形狀）。
    func testTaskParserRemainingTextWithMixedWhitespaceRun() {
        let filler = String(repeating: " a  b ", count: Self.adversarialLength / 6)
        let html = #"<li class="period-card"><span class="period-remaining">"# + filler
        assertPrompt("TaskParser.period-remaining（空白-字元-空白交錯）") {
            _ = try? TaskParser.parse(html: html)
        }
    }

    func testTaskParserUploadedAtWithUnterminatedWhitespace() {
        let html = #"<li class="period-card">上傳時間："# + pad
        assertPrompt("TaskParser.上傳時間") { _ = try? TaskParser.parse(html: html) }
    }

    func testTaskParserReviewedAtWithUnterminatedWhitespace() {
        let html = #"<li class="period-card">審核時間："# + pad
        assertPrompt("TaskParser.審核時間") { _ = try? TaskParser.parse(html: html) }
    }

    /// `第\s*(\d+)\s*期` / `period-range">…([0-9/]+)…`：長數字串的 O(n²)。
    func testTaskParserIndexAndRangeWithLongDigitRun() {
        let html = #"<li class="period-card">第"# + digits
            + #"<span class="period-range">"# + digits
        assertPrompt("TaskParser.第 N 期／period-range（超長數字串）") {
            _ = try? TaskParser.parse(html: html)
        }
    }

    /// 大量未閉合標籤：`[^>]*` 會一路掃到文件尾（改用 `[^<>]` 後在下一個 `<` 就停）。
    func testTaskParserWithManyUnclosedTags() {
        let html = #"<li class="period-card">"#
            + String(repeating: "<span ", count: Self.adversarialLength / 6)
        assertPrompt("TaskParser（大量未閉合標籤）") { _ = try? TaskParser.parse(html: html) }
    }

    // MARK: - VoucherParser

    /// 原 `兌換期限[：:]\s*([^<]*?)\s*</p>`：同樣的三層量詞重疊。
    func testVoucherParserExpiryWithUnterminatedWhitespace() {
        let html = figure + "兌換期限：" + pad
        assertPrompt("VoucherParser.兌換期限") { _ = try? VoucherParser.parseView(html: html) }
    }

    /// 原 `(\d+)\s*次`：`\d+` 每次貪婪到底再逐格回溯，O(n²)。
    func testVoucherParserRemainingCountWithLongDigitRun() {
        let html = #"<p class="notice notice--error">"# + digits + "</p>"
        assertPrompt("VoucherParser.剩餘次數（超長數字串）") {
            _ = VoucherParser.parseVerifyError(html: html)
        }
    }

    /// 原 `<li\b[^>]*>([\s\S]*?)</li>`：大量未閉合 `<li` 的 O(n²)。
    func testVoucherParserNoticesWithManyUnclosedListItems() {
        let html = figure + #"<section class="voucher-notices">"#
            + String(repeating: "<li ", count: Self.adversarialLength / 4) + "</section>"
        assertPrompt("VoucherParser.notices（大量未閉合 <li）") {
            _ = try? VoucherParser.parseView(html: html)
        }
    }

    /// 原 `<section\b[^>]*>`：大量未閉合 `<section` 的 O(n²)。
    func testVoucherParserFiguresWithManyUnclosedSections() {
        let html = String(repeating: "<section ", count: Self.adversarialLength / 9)
        assertPrompt("VoucherParser.figures（大量未閉合 <section）") {
            _ = try? VoucherParser.parseView(html: html)
        }
    }

    /// `voucher-meta__channel[\s\S]*?<span…`：跨標籤的惰性掃描，重複出現的錨點會放大成本。
    func testVoucherParserChannelWithRepeatedAnchors() {
        let anchor = "voucher-meta__channel"
        let html = figure
            + String(repeating: anchor, count: Self.adversarialLength / anchor.count)
        assertPrompt("VoucherParser.voucher-meta__channel（重複錨點）") {
            _ = try? VoucherParser.parseView(html: html)
        }
    }

    // MARK: - CsrfParser

    /// 原 `<input\b[^>]*\bname…`：大量未閉合 `<input` 的 O(n²)（56 KB 實測 6.7 秒）。
    func testCsrfParserWithManyUnclosedInputs() {
        let html = String(repeating: "<input ", count: Self.adversarialLength / 7)
        assertPrompt("CsrfParser（大量未閉合 <input）") { _ = try? CsrfParser.extract(from: html) }
    }

    /// 有 `name="_csrf"` 但 value 屬性永遠閉不起來。
    func testCsrfParserWithUnterminatedValueAttribute() {
        let html = #"<input name="_csrf" value=""# + String(repeating: "a", count: Self.adversarialLength)
        assertPrompt("CsrfParser（value 屬性未閉合）") { _ = try? CsrfParser.extract(from: html) }
    }

    // MARK: - RedeemParser

    /// 原 `<form\b[^>]*>`：大量未閉合 `<form` 的 O(n²)（48 KB 實測 1.9 秒）。
    func testRedeemParserWithManyUnclosedForms() {
        let html = String(repeating: "<form ", count: Self.adversarialLength / 6)
        assertPrompt("RedeemParser（大量未閉合 <form）") { _ = try? RedeemParser.parse(html: html) }
    }

    /// 合法的 `item-row__form` 開頭 + 大量未閉合 `<input`（打的是 `hiddenInputValue`）。
    func testRedeemParserWithManyUnclosedInputsInsideForm() {
        let html = #"<form class="item-row__form" data-vendor-name="V" data-item-name="I">"#
            + String(repeating: "<input ", count: Self.adversarialLength / 7)
        assertPrompt("RedeemParser.hiddenInputValue（大量未閉合 <input）") {
            _ = try? RedeemParser.parse(html: html)
        }
    }

    // MARK: - 正常 HTML 的解析結果不能被上面的修改弄壞
    //
    // 既有的 *ParserTests 已經覆蓋 fixture 的完整解析；這裡只補一個「全空白欄位」
    // 的邊界：舊樣式 `\s*([^<]+?)\s*<` 會回傳一個空白字元，新樣式 trim 後視為沒有值。

    func testWhitespaceOnlyRemainingTextIsTreatedAsAbsent() throws {
        let html = """
        <ul class="period-list">
        <li class="period-card">
        <span class="period-no">第 1 期</span>
        <span class="period-remaining">   </span>
        <p class="period-state period-state--NOT_UPLOADED"><span>尚未上傳</span></p>
        </li>
        </ul>
        """
        let period = try XCTUnwrap(TaskParser.parse(html: html).first)
        XCTAssertNil(period.remainingText, "只有空白的欄位應視同沒有值")
    }

    func testRemainingTextIsTrimmedButPreservesInnerSpacing() throws {
        let html = """
        <ul class="period-list">
        <li class="period-card">
        <span class="period-remaining">
          剩 1 天 22 小時
        </span>
        </li>
        </ul>
        """
        let period = try XCTUnwrap(TaskParser.parse(html: html).first)
        XCTAssertEqual(period.remainingText, "剩 1 天 22 小時")
    }

    // MARK: - 共用止血點：response body 大小上限

    func testBodySizeUnderLimitIsAccepted() {
        XCTAssertNoThrow(try URLSessionHTTPClient.validateBodySize(URLSessionHTTPClient.maxResponseBytes))
        XCTAssertNoThrow(try URLSessionHTTPClient.validateBodySize(0))
    }

    func testBodySizeOverLimitThrowsResponseTooLarge() {
        let tooBig = URLSessionHTTPClient.maxResponseBytes + 1
        XCTAssertThrowsError(try URLSessionHTTPClient.validateBodySize(tooBig)) { error in
            XCTAssertEqual(error as? AppError, .responseTooLarge(tooBig))
        }
    }

    /// 上限本身也要被測到——調小它等於放大所有 parser 的攻擊面。
    func testMaxResponseBytesIsTwoMegabytes() {
        XCTAssertEqual(URLSessionHTTPClient.maxResponseBytes, 2 * 1024 * 1024)
    }

    /// 即使有人把上限放寬到 2 MB 的邊界值，parser 也還是要撐得住。
    /// 這是「regex 修好了」的最終證明：滿載 2 MB 對抗輸入仍在 1 秒內返回
    /// （修好之前光是 1.6 KB 就要 34–81 秒）。
    func testParsersSurviveFullSizeAdversarialBody() {
        let twoMB = URLSessionHTTPClient.maxResponseBytes
        let start = Date()
        _ = try? TaskParser.parse(
            html: #"<li class="period-card"><span class="period-remaining">"#
                + String(repeating: " ", count: twoMB)
        )
        _ = try? CsrfParser.extract(from: String(repeating: "<input ", count: twoMB / 7))
        _ = try? RedeemParser.parse(html: String(repeating: "<form ", count: twoMB / 6))
        _ = try? VoucherParser.parseView(html: figure + "兌換期限：" + String(repeating: " ", count: twoMB))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "滿載 2 MB 對抗輸入應在 1 秒內返回，實際 \(elapsed) 秒")
    }
}
