import XCTest
@testable import ExerciseRewardsKit

/// 驗證 TaskParser 對 `/member/tasks` 頁面的解析：14 期、第 1 期 redeemable 且有 uuid，其餘 notStarted。
final class TaskParserTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParseReturnsFourteenPeriods() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        XCTAssertEqual(periods.count, 14)
    }

    func testFirstPeriodIsRedeemableWithNonEmptyID() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)
        let first = try XCTUnwrap(periods.first)

        // Assert
        XCTAssertEqual(first.index, 1)
        XCTAssertEqual(first.state, .redeemable)
        XCTAssertFalse(first.id.isEmpty)
        XCTAssertEqual(first.id, "00000000-0000-4000-8000-000000000001")
        XCTAssertEqual(first.startDate, "2026/09/01")
        XCTAssertEqual(first.endDate, "2026/09/06")
        XCTAssertEqual(first.remainingText, "剩 1 天 22 小時")
        XCTAssertEqual(first.uploadedAt, "2026/09/03 21:42")
        XCTAssertEqual(first.reviewedAt, "2026/09/04 20:10")
    }

    func testRemainingPeriodsAreNotStartedWithEmptyID() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        let rest = periods.dropFirst()
        XCTAssertEqual(rest.count, 13)
        for period in rest {
            XCTAssertEqual(period.state, .notStarted, "period \(period.index) should be notStarted")
            XCTAssertTrue(period.id.isEmpty, "period \(period.index) should have no uuid")
        }
    }

    func testPeriodIndicesAreSequential() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        XCTAssertEqual(periods.map(\.index), Array(1...14))
    }

    func testParseThrowsWhenNoPeriodCardFound() {
        // Arrange
        let html = "<html><body><p>no cards here</p></body></html>"

        // Act & Assert
        XCTAssertThrowsError(try TaskParser.parse(html: html)) { error in
            XCTAssertEqual(error as? AppError, .parsing("no period-card found in /member/tasks HTML"))
        }
    }

    func testNotUploadedMapsToOpen() throws {
        // 當期尚未上傳 = period-state--NOT_UPLOADED，應對到 .open（可上傳）。
        let html = """
        <ul class="period-list">
        <li class="period-card period-card--current">
        <span class="period-no">第 1 期</span>
        <span class="period-range">2026/09/01 ~ 2026/09/06</span>
        <span class="period-remaining">剩 1 天 12 小時</span>
        <p class="period-state period-state--NOT_UPLOADED"><span>尚未上傳</span></p>
        <div class="period-actions"><a href="/registrant/member/upload" class="btn btn--primary">上傳運動紀錄</a></div>
        </li>
        </ul>
        """
        let periods = try TaskParser.parse(html: html)
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods[0].state, .open)
        XCTAssertEqual(periods[0].index, 1)
    }


    func testUnderReviewMapsToPendingReview() throws {
        // 上傳後待審核的 state class 是 UNDER_REVIEW，應對到 .pendingReview。
        let html = """
        <ul class="period-list">
        <li class="period-card">
        <span class="period-no">第 1 期</span>
        <span class="period-range">2026/09/01 ~ 2026/09/06</span>
        <p class="period-state period-state--UNDER_REVIEW"><span>待審核</span></p>
        </li>
        </ul>
        """
        let periods = try TaskParser.parse(html: html)
        XCTAssertEqual(periods.first?.state, .pendingReview)
    }

    // MARK: - 已兌換的期別（兌換內容 + voucher 連結的 UUID）

    /// 已兌換的卡片在官網長這樣：狀態是 REDEEMED、動作區只剩 voucher／screenshot 兩個連結
    /// （沒有 redeem 連結了），卡片最後有一行「兌換內容：通路／品項」。
    private static let redeemedCardHTML = """
    <ul class="period-list">
      <li class="period-card period-card--current">
        <div class="period-head">
          <span class="period-no">第 1 期</span>
          <span class="period-range">2026/09/01 ~ 2026/09/06</span>
          <span class="period-remaining">本期任務可上傳時間 剩 3 小時 20 分</span>
        </div>
        <p class="period-state period-state--REDEEMED"><span>已兌換</span></p>
        <p class="period-detail"><span>上傳時間：2026/09/03 21:42</span></p>
        <div class="period-actions">
          <a href="/registrant/member/voucher/00000000-0000-4000-8000-000000000009" class="btn btn--primary">檢視加碼券</a>
          <a href="/registrant/member/screenshot/00000000-0000-4000-8000-000000000009" class="btn btn--secondary">檢視我的截圖</a>
        </div>
        <p class="period-voucher"><span>兌換內容：示範超商 C／測試品項 C2 超值券</span></p>
      </li>
    </ul>
    """

    func testParsesVoucherSummaryFromRedeemedCard() throws {
        // Act
        let periods = try TaskParser.parse(html: Self.redeemedCardHTML)
        let first = try XCTUnwrap(periods.first)

        // Assert
        XCTAssertEqual(first.state, .redeemed)
        XCTAssertEqual(first.voucherSummary, "示範超商 C／測試品項 C2 超值券")
    }

    /// 已兌換的卡片只剩 `/member/voucher/{uuid}` 連結。idPattern 若沒認這個路徑，
    /// 已兌換那期的 id 會是空字串，券夾與首頁就點不進券碼頁。
    func testParsesIDFromVoucherLinkOnRedeemedCard() throws {
        // Act
        let periods = try TaskParser.parse(html: Self.redeemedCardHTML)

        // Assert
        XCTAssertEqual(periods.first?.id, "00000000-0000-4000-8000-000000000009")
    }

    /// 沒有「兌換內容」那一行的期別（未兌換、尚未開始）一律是 nil，不可以拿別的欄位頂替。
    func testVoucherSummaryIsNilWhenCardHasNoVoucherLine() throws {
        // Arrange
        let html = try loadFixture("member_tasks")

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        XCTAssertTrue(periods.allSatisfy { $0.voucherSummary == nil })
    }

    /// 官網文字會被 Thymeleaf 跳脫；沒還原的話畫面上會看到原始碼。
    func testDecodesEntitiesInVoucherSummary() throws {
        // Arrange
        let html = """
        <ul><li class="period-card">
          <span class="period-no">第 1 期</span>
          <p class="period-state period-state--REDEEMED"><span>已兌換</span></p>
          <p class="period-voucher"><span>兌換內容：全家便利商店／50&#43;3元加碼券 &amp; 贈品</span></p>
        </li></ul>
        """

        // Act
        let periods = try TaskParser.parse(html: html)

        // Assert
        XCTAssertEqual(periods.first?.voucherSummary, "全家便利商店／50+3元加碼券 & 贈品")
    }

    // MARK: - 切卡片的邊界：class 裡有 `period-card` 這個 token，而不是一段固定字串

    /// 一張最小但完整的卡片，只有 `<li>` 開頭標籤由呼叫端決定。
    private static func card(openTag: String, index: Int = 1, extra: String = "") -> String {
        """
        \(openTag)
          <span class="period-no">第 \(index) 期</span>
          <span class="period-range">2026/09/01 ~ 2026/09/06</span>
          <p class="period-state period-state--NOT_UPLOADED"><span>尚未上傳</span></p>
          \(extra)
        </li>
        """
    }

    private static func page(_ cards: String...) -> String {
        "<ul class=\"period-list\">\n" + cards.joined(separator: "\n") + "\n</ul>"
    }

    /// 舊做法比對完整字串 `<li class="period-card`，官網只要動到 class 的**寫法**（不是內容），
    /// 一張卡都切不到、整個任務頁死掉。這幾種寫法官網都可能改成，每一種都要切得到。
    func testSplitsCardWhenClassOrderIsSwapped() throws {
        let periods = try TaskParser.parse(html: Self.page(Self.card(openTag: #"<li class="card period-card">"#)))
        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.state, .open)
    }

    func testSplitsCardWithExtraClasses() throws {
        let html = Self.page(Self.card(openTag: #"<li class="period-card period-card--current is-highlighted">"#))
        XCTAssertEqual(try TaskParser.parse(html: html).count, 1)
    }

    func testSplitsCardWithAttributeBeforeClass() throws {
        let html = Self.page(Self.card(openTag: #"<li data-period-id="abc" id="p1" class="period-card">"#))
        XCTAssertEqual(try TaskParser.parse(html: html).count, 1)
    }

    func testSplitsCardWithSingleQuotedClass() throws {
        let html = Self.page(Self.card(openTag: "<li class='period-card'>"))
        XCTAssertEqual(try TaskParser.parse(html: html).count, 1)
    }

    func testSplitsCardWithSpacesAroundClassEquals() throws {
        let html = Self.page(Self.card(openTag: #"<li class = "period-card">"#))
        XCTAssertEqual(try TaskParser.parse(html: html).count, 1)
    }

    /// `period-card--current` 單獨出現也算卡片：`\bperiod-card\b` 後面接 `-`，`-` 不是 word char，
    /// 邊界成立。這是對的——修飾詞是這張卡的狀態，不是別的元素。
    func testModifierOnlyClassStillCountsAsCard() throws {
        let html = Self.page(Self.card(openTag: #"<li class="period-card--current">"#))
        XCTAssertEqual(try TaskParser.parse(html: html).count, 1)
    }

    /// 卡片內的子元素若用 BEM 命名（`period-card__title`／`period-card__meta`），**不能**被當成
    /// 下一張卡的開頭——`_` 是 word char，`\b` 在這裡不成立。否則一張卡會被自己的子元素切碎，
    /// 期數、狀態各落在不同的碎片裡。
    func testDoesNotSplitOnBEMChildElements() throws {
        let html = Self.page(
            Self.card(openTag: #"<li class="period-card">"#, index: 1, extra: """
            <h3 class="period-card__title">第一週</h3>
            <ul class="period-card__meta">
              <li class="period-card__meta-item">上傳時間：2026/09/03 21:42</li>
            </ul>
            <a href="/registrant/member/redeem/00000000-0000-4000-8000-000000000001">兌換</a>
            """),
            Self.card(openTag: #"<li class="period-card">"#, index: 2)
        )

        let periods = try TaskParser.parse(html: html)

        XCTAssertEqual(periods.count, 2)
        XCTAssertEqual(periods.map(\.index), [1, 2])
        // 子元素裡的內容仍然屬於第一張卡。
        XCTAssertEqual(periods[0].uploadedAt, "2026/09/03 21:42")
        XCTAssertEqual(periods[0].id, "00000000-0000-4000-8000-000000000001")
    }

    /// 邊界放寬之後，class 裡碰巧帶著 `period-card` 字樣但**不是卡片**的 `<li>`（圖例、說明列）
    /// 也會被切成一塊；沒有卡片內容（`period-no`／`period-range`／`period-state`）的塊要丟掉，
    /// 不然會多出一張全是預設值的假卡片。
    func testIgnoresListItemsThatOnlyLookLikeCards() throws {
        let html = Self.page(
            #"<li class="period-card-legend"><span class="legend-dot"></span>本週</li>"#,
            Self.card(openTag: #"<li class="period-card">"#, index: 1),
            #"<li class="period-card--placeholder">尚無資料</li>"#
        )

        let periods = try TaskParser.parse(html: html)

        XCTAssertEqual(periods.count, 1)
        XCTAssertEqual(periods.first?.index, 1)
    }

    /// 全部都是「長得像卡片但沒有內容」的 `<li>`，等同一張卡都沒有：這是頁面結構對不上的訊號。
    func testThrowsWhenOnlyLookalikeListItemsArePresent() {
        let html = Self.page(#"<li class="period-card-legend">本週</li>"#)
        XCTAssertThrowsError(try TaskParser.parse(html: html)) { error in
            XCTAssertEqual(error as? AppError, .parsing("no period-card found in /member/tasks HTML"))
        }
    }

    /// 完全無關的 `<li>`（class 裡沒有這個 token）不管內容長什麼樣都不算卡片。
    func testIgnoresUnrelatedListItems() throws {
        let html = Self.page(
            #"<li class="nav-item">首頁</li>"#,
            Self.card(openTag: #"<li class="period-card">"#, index: 3),
            #"<li class="periodcard">沒有連字號</li>"#
        )
        XCTAssertEqual(try TaskParser.parse(html: html).map(\.index), [3])
    }

    // MARK: - 端到端回歸：真實頁面 + 真實日期

    /// **回報的 bug（2026-09-07）**：拿官網真的回的那份 HTML，走完整條路徑
    /// （解析 → 挑當期），9/7 當天必須選到第 2 期（9/7~9/13），而不是已經過完的第 1 期。
    ///
    /// 這張 fixture 正是踩雷的形狀：卡片 1→14 遞增，第 1 期已 `REDEEMABLE`、
    /// 第 2 期仍 `NOT_STARTED`。舊的「取第一個非 notStarted」在這裡必然選錯。
    func testCurrentPeriodOnTheRealPageAdvancesOnTheSeventh() throws {
        let periods = try TaskParser.parse(html: loadFixture("member_tasks"))
        let sept7 = TaskPeriod.activityCalendar
            .date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!

        let current = TaskPeriod.current(in: periods, now: sept7)

        XCTAssertEqual(current?.index, 2)
        XCTAssertEqual(current?.startDate, "2026/09/07")
        XCTAssertEqual(current?.endDate, "2026/09/13")
    }

    /// 同一份頁面：第 1 期在 9/7 必須被判定為已結束，上傳 CTA 才會收起來。
    func testFirstPeriodOnTheRealPageHasEndedOnTheSeventh() throws {
        let periods = try TaskParser.parse(html: loadFixture("member_tasks"))
        let sept7 = TaskPeriod.activityCalendar
            .date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 9))!

        XCTAssertTrue(periods[0].hasEnded(now: sept7))
        XCTAssertFalse(periods[1].hasEnded(now: sept7))
    }

    /// 官網每一期的日期都必須解析得出來。這條在官網改日期格式時會第一個亮紅燈，
    /// 提醒我們當期判斷已經默默退回舊的狀態啟發式了。
    func testEveryPeriodOnTheRealPageHasAParseableDateSpan() throws {
        let periods = try TaskParser.parse(html: loadFixture("member_tasks"))
        for period in periods {
            XCTAssertNotNil(period.dateSpan,
                            "第 \(period.index) 期的日期 \(period.startDate) ~ \(period.endDate) 解析失敗")
        }
    }
}
