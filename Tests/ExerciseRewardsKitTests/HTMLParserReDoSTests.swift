import XCTest
@testable import ExerciseRewardsKit

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
///
/// 計時一律走 `CPUClock`（量 CPU 時間、多輪取最小值）而不是 `Date()`。
/// 理由與實測數字寫在 `CPUTimeBudget.swift`：`swift test` 跑整包時 process 有八成以上的
/// 牆上時間根本沒在 CPU 上，牆上時間量到的是「機器多忙」而不是「樣式多貴」。
///
/// 另一道獨立防線是 `URLSessionHTTPClient` 的 2 MB body 上限（見本檔最後一節）：
/// 逐條修 regex 擋不住之後新加的 parser，把輸入長度夾住才擋得住。
final class HTMLParserReDoSTests: XCTestCase {

    /// 對抗輸入的長度。遠大於任何真實欄位的量級。
    private static let adversarialLength = 4 * 1024
    /// 每個樣式的 CPU 成本上限。修好之後實測都在 2 ms 以內，100 ms 留了 50 倍餘裕。
    private static let budget: TimeInterval = 0.1

    /// 執行 `body` 並斷言在預算內完成。
    private func assertPrompt(
        _ label: String,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () -> Void
    ) {
        assertCPUBudget(
            Self.budget, "\(label)（4 KB 對抗輸入）",
            hint: "這代表樣式又出現了災難性回溯——檢查是不是有相鄰量詞的字元集合重疊"
                + "（例如 `\\s*([^<]+?)\\s*<`），或是有量詞少了長度上限。",
            file: file, line: line,
            body
        )
    }

    private var pad: String { String(repeating: " ", count: Self.adversarialLength) }
    private var digits: String { String(repeating: "1", count: Self.adversarialLength) }

    /// 對抗輸入用的卡片開頭。**帶一個空的 `period-range`**：`TaskParser.splitCards` 收緊之後，
    /// 塊內沒有 `period-no|range|state` 任一標記的 `<li>` 會被當成無關列丟掉，`parse` 在碰到被測
    /// 樣式之前就以 `parsing` 收場——測試會綠，但什麼都沒量到。空的 range 讓卡片過得了篩選、
    /// 又不會替 `period-range` 樣式製造額外的比對成本。
    private let cardOpen = #"<li class="period-card"><span class="period-range"></span>"#

    /// 一個合法的 `voucher-figure`，讓 `parseView` 不會在抓到 figure 之前就丟錯。
    private let figure =
        #"<section class="voucher-figure" data-format="CODE_128" data-value="X"></section>"#

    // MARK: - TaskParser

    /// 原 `period-remaining">\s*([^<]+?)\s*<`：`\s` ⊂ `[^<]`，三層量詞互相回溯。
    func testTaskParserRemainingTextWithUnterminatedWhitespace() {
        let html = cardOpen + #"<span class="period-remaining">"# + pad
        assertPrompt("TaskParser.period-remaining（純空白、無收尾 `<`）") {
            _ = try? TaskParser.parse(html: html)
        }
        // 哨兵：對抗輸入必須真的被切成一張卡、跑到欄位樣式。若 `splitCards` 日後再收緊而把它濾掉，
        // 上面那條會靠 early throw 變綠卻什麼都沒量到——這一行會先亮。
        XCTAssertEqual(try TaskParser.parse(html: html).count, 1, "對抗輸入沒有走到被測的欄位樣式")
    }

    /// 空白與非空白交錯的變體（實測最慢的一種形狀）。
    func testTaskParserRemainingTextWithMixedWhitespaceRun() {
        let filler = String(repeating: " a  b ", count: Self.adversarialLength / 6)
        let html = cardOpen + #"<span class="period-remaining">"# + filler
        assertPrompt("TaskParser.period-remaining（空白-字元-空白交錯）") {
            _ = try? TaskParser.parse(html: html)
        }
    }

    func testTaskParserUploadedAtWithUnterminatedWhitespace() {
        let html = cardOpen + "上傳時間：" + pad
        assertPrompt("TaskParser.上傳時間") { _ = try? TaskParser.parse(html: html) }
    }

    func testTaskParserReviewedAtWithUnterminatedWhitespace() {
        let html = cardOpen + "審核時間：" + pad
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
        let html = cardOpen
            + String(repeating: "<span ", count: Self.adversarialLength / 6)
        assertPrompt("TaskParser（大量未閉合標籤）") { _ = try? TaskParser.parse(html: html) }
    }

    /// 切卡片改用 `<li\b[^<>]{0,400}\bclass…` 之後，打的是那條開頭標籤樣式：大量未閉合的 `<li `
    /// 每一個都是候選起點，`[^<>]` 讓每個候選在下一個 `<` 就放棄，成本與整頁長度脫鉤。
    func testTaskParserWithManyUnclosedListItems() {
        let html = String(repeating: "<li ", count: Self.adversarialLength / 4)
        assertPrompt("TaskParser.splitCards（大量未閉合 <li）") { _ = try? TaskParser.parse(html: html) }
    }

    /// 有 `class="` 但屬性值永遠閉不起來：`[^"']{0,300}` 的上限讓它在 300 字元內就停。
    func testTaskParserWithUnterminatedClassAttribute() {
        let html = #"<li class=""# + String(repeating: "a", count: Self.adversarialLength)
        assertPrompt("TaskParser.splitCards（class 屬性未閉合）") { _ = try? TaskParser.parse(html: html) }
    }

    /// 合法的卡片開頭重複出現、每張都只有一點內容：切卡片本身是 O(卡片數)，不能因為卡片數多就變慢。
    func testTaskParserWithManyTinyCards() {
        let html = String(repeating: #"<li class="x period-card y"><span class="period-no">第 1 期</span>"#,
                          count: Self.adversarialLength / 64)
        assertPrompt("TaskParser.splitCards（大量小卡片）") { _ = try? TaskParser.parse(html: html) }
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
        // 空的 `period-range` 只是讓這張合成卡片過得了 `splitCards` 的骨架篩選（真實卡片每張都有），
        // 這條測的仍然只是 trim。
        let html = """
        <ul class="period-list">
        <li class="period-card">
        <span class="period-range"></span>
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

    /// 四個 parser 各自最壞形狀的對抗輸入，每條約 `bytes` 長。
    /// 刻意在計時範圍外建好：光是 `String(repeating:)` 產生這四條 2 MB 字串就要 60 ms CPU，
    /// 而那是測試自己的成本，不是 parser 的。
    private struct AdversarialInputs {
        let task: String
        let csrf: String
        let redeem: String
        let voucher: String
    }

    private func adversarialInputs(bytes: Int) -> AdversarialInputs {
        AdversarialInputs(
            task: cardOpen + #"<span class="period-remaining">"#
                + String(repeating: " ", count: bytes),
            csrf: String(repeating: "<input ", count: bytes / 7),
            redeem: String(repeating: "<form ", count: bytes / 6),
            voucher: figure + "兌換期限：" + String(repeating: " ", count: bytes)
        )
    }

    private func parseAll(_ inputs: AdversarialInputs) {
        _ = try? TaskParser.parse(html: inputs.task)
        _ = try? CsrfParser.extract(from: inputs.csrf)
        _ = try? RedeemParser.parse(html: inputs.redeem)
        _ = try? VoucherParser.parseView(html: inputs.voucher)
    }

    /// 即使有人把上限放寬到 2 MB 的邊界值，parser 也還是要撐得住。
    /// 這是「regex 修好了」的最終證明：滿載 2 MB 對抗輸入仍在預算內返回
    /// （修好之前光是 1.6 KB 就要 34–81 秒）。
    ///
    /// **2.0 秒這個門檻怎麼來的。** 本機（M 系列、debug build）連跑五輪取最短的 CPU 成本：
    /// TaskParser 185 ms、CsrfParser 54 ms、RedeemParser 59 ms、VoucherParser 40 ms，
    /// 合計 **0.34 秒**（TaskParser 佔一半以上，因為它要拿 8 條樣式各掃過 2 MB）。
    /// 2.0 秒 ≈ 6 倍餘裕，跟 `SensitivePatternTests.testScrubVeryLongStringReturnsPromptly`
    /// 的餘裕比例一致，足夠吸收「被排到效率核」的 3–4 倍膨脹與更慢的 CI 機器。
    ///
    /// **舊的 1.0 秒為什麼不合理**（而不是 parser 變慢了）：它量的是牆上時間，而這份工作
    /// 本來就要 0.5–0.9 秒牆上時間跑完（其中還有近兩成是產生那四條 2 MB 字串），餘裕不到
    /// 兩倍；`swift test` 整包跑時 process 大半時間被排開，同一份工作量到 1.29／2.34／8.11
    /// 秒都出現過。詳細實測見 `CPUTimeBudget.swift`。
    ///
    /// **6 倍餘裕為什麼仍守得住 ReDoS 防線：** 線性與非線性之間差的不是倍數而是量級。
    /// 檔頭那組實測是 1.6 KB → 34 秒（O(n³)）；同一組樣式吃 2 MB 是天文數字，連 O(n²) 的
    /// 舊 `[^>]*`（56 KB → 6.7 秒）放大到 2 MB 也要以小時計。任何回歸都會超過 2 秒好幾個
    /// 數量級，不可能剛好落在 0.34 與 2.0 之間而躲過這條斷言。把「線性」這件事真正釘死的
    /// 是下面那條 `testParserCostGrowsLinearlyWithInputSize`。
    func testParsersSurviveFullSizeAdversarialBody() {
        let inputs = adversarialInputs(bytes: URLSessionHTTPClient.maxResponseBytes)
        // rounds 用 2 不用 3：這份工作每輪 0.34 秒 CPU，多跑一輪只為抗噪不划算。
        assertCPUBudget(2.0, rounds: 2, "滿載 2 MB 對抗輸入", hint: "檢查最近改動的樣式。") {
            parseAll(inputs)
        }
    }

    /// 真正的 ReDoS 防線：成本必須**隨輸入長度線性成長**。
    ///
    /// 絕對秒數會隨機器速度與建置模式浮動（debug 沒有內聯，比 release 慢好幾倍），成長率不會：
    /// 輸入放大 8 倍，線性樣式的成本就是 8 倍上下，O(n²) 是 64 倍，O(n³) 是 512 倍。
    /// 這條斷言不管機器多快多慢都成立，所以它是這一整組測試裡唯一不需要「訂一個秒數」的一條。
    ///
    /// 本機實測（min-of-5 CPU，四個 parser 合計）：128 KB 23.2 ms、256 KB 44.5 ms、
    /// 512 KB 97.5 ms、1 MB 201.2 ms、2 MB 406.1 ms——每次倍增剛好 2.0 倍上下，
    /// 128 KB → 1 MB（8 倍輸入）的比值是 **8.7**。略高於 8 是因為輸入變大後就掉出快取，
    /// 每 byte 的成本本來就會漲一點，跟回溯無關。
    /// 上限取 24（3 倍線性）：離實測的 8.7 有 2.8 倍餘裕，離 O(n²) 的 64 倍還差得遠，
    /// 中間不存在會被誤判的形狀。
    ///
    /// 尺寸取 1/16 與 1/2 上限而不是直接用滿 2 MB：成長率不需要跑到邊界也量得出來，
    /// 而每多量一輪 2 MB 就要多花 0.4 秒 CPU——邊界值由上面那條負責。
    ///
    /// 兩個尺寸**交錯**量測（每輪都先小後大），是為了讓兩邊經歷相同的核心頻率與快取狀態；
    /// 各自量一次的話，小的那次剛好被排到效率核就會把比值灌大成偽陽性。
    func testParserCostGrowsLinearlyWithInputSize() {
        let smallBytes = URLSessionHTTPClient.maxResponseBytes / 16  // 128 KB
        let largeBytes = URLSessionHTTPClient.maxResponseBytes / 2   // 1 MB，= 8 倍
        let small = adversarialInputs(bytes: smallBytes)
        let large = adversarialInputs(bytes: largeBytes)

        var smallCost = TimeInterval.infinity
        var largeCost = TimeInterval.infinity
        for _ in 0..<2 {
            smallCost = min(smallCost, CPUClock.measure { parseAll(small) })
            largeCost = min(largeCost, CPUClock.measure { parseAll(large) })
        }

        // 分母太小的話比值會被雜訊主宰；128 KB 這份工作實測 23 ms，遠離時鐘的解析度。
        XCTAssertGreaterThan(smallCost, 0, "CPU 時鐘沒有前進，量測本身壞了")

        let sizeRatio = Double(largeBytes) / Double(smallBytes)
        let costRatio = largeCost / smallCost
        XCTAssertLessThan(
            costRatio, 3 * sizeRatio,
            "輸入放大 \(sizeRatio) 倍，成本卻放大了 \(costRatio) 倍"
                + "（\(smallBytes) bytes → \(smallCost) 秒、\(largeBytes) bytes → \(largeCost) 秒）。"
                + "線性樣式應該落在 \(sizeRatio) 倍上下；超過三倍代表有樣式退回成超線性——"
                + "檢查是不是有相鄰量詞的字元集合重疊、量詞少了長度上限，"
                + "或標籤屬性用了 `[^>]` 而不是 `[^<>]`。"
        )
    }
}
