import XCTest
@testable import SportsRewardsKit

/// 驗證 `VendorIntroParser` 對廠商可兌換商品頁的解析。
///
/// 官網這幾頁有兩種版型，兩個 fixture 各對應一種（皆為合成測試資料，非官方頁面複製）：
/// - `vendor_intro_details.html`：`<details data-category>` 分類卡 + `<li data-name>` 逐項清單
/// - `vendor_intro_table.html`：`類別名稱 / 商品名稱（列舉）` 表格
final class VendorIntroParserTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - 版型 A：逐項列出

    func testDetailsLayoutParsesEveryCategory() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.categories.count, 4)
        XCTAssertEqual(intro.categories.map(\.name),
                       ["全部品項", "Let's Café", "瓶裝水類", "堅果 & 蛋類"])
    }

    func testDetailsLayoutParsesTitleAndSubtitle() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.title, "示範超商 A可兌換商品")
        XCTAssertEqual(intro.subtitle, "點選商品分類，即可展開查看相關兌換品項。")
    }

    /// 分類名稱在官網是放在屬性裡的跳脫字串（`Let&#x27;s Caf&#233;`），
    /// 沒有還原的話畫面上會直接看到原始碼。
    func testDetailsLayoutDecodesHTMLEntitiesInCategoryName() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertTrue(intro.categories.contains { $0.name == "Let's Café" })
        XCTAssertTrue(intro.categories.contains { $0.name == "堅果 & 蛋類" })
        XCTAssertFalse(intro.categories.contains { $0.name.contains("&#") })
    }

    func testDetailsLayoutParsesItemsInEachCategory() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)
        let all = try XCTUnwrap(intro.categories.first { $0.isAllItems })
        let coffee = try XCTUnwrap(intro.categories.first { $0.name == "Let's Café" })

        XCTAssertEqual(all.items.count, 5)
        XCTAssertEqual(all.items.first, "測試無糖茶")
        XCTAssertEqual(coffee.items, ["測試大冰拿鐵"])
    }

    /// 「全部品項」那張卡是官網用 `class="… all-items"` 標出來的彙總卡。
    func testDetailsLayoutMarksOnlyTheAllItemsCard() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.categories.filter(\.isAllItems).count, 1)
        XCTAssertEqual(intro.categories.first?.isAllItems, true)
    }

    /// `statedCount` 是官網自己標的數字，不是 `items.count` 的複製品——
    /// 官網沒標時要是 nil，這樣兩者兜不攏時才看得出來。
    func testDetailsLayoutKeepsStatedCountSeparateFromParsedItems() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)
        let all = try XCTUnwrap(intro.categories.first { $0.isAllItems })
        let nuts = try XCTUnwrap(intro.categories.first { $0.name == "堅果 & 蛋類" })

        XCTAssertEqual(all.statedCount, 5)
        XCTAssertNil(nuts.statedCount, "官網沒標「N 項」時不可以用 items.count 頂替")
        XCTAssertEqual(nuts.items.count, 2)
    }

    func testDetailsLayoutHasNoExamples() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertTrue(intro.categories.allSatisfy { $0.examples == nil })
    }

    func testParsesNotices() throws {
        let html = try loadFixture("vendor_intro_details")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.notices.count, 2)
        XCTAssertEqual(intro.notices.first, "實際可兌換品項、供應狀況及門市庫存，依各門市現場公告為準。")
    }

    // MARK: - 版型 B：類別 / 舉例 表格

    func testTableLayoutParsesEveryRow() throws {
        let html = try loadFixture("vendor_intro_table")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.categories.count, 4)
        XCTAssertEqual(intro.categories.map(\.name),
                       ["冷藏鮮乳", "豆漿/米漿/燕麥", "常溫鮮蛋", "堅果 & 核仁類"])
    }

    /// 表格版的第二欄是「列舉」不是完整清單，因此進 `examples` 而不是 `items`——
    /// 放進 `items` 會讓畫面看起來像「這就是全部品項」。
    func testTableLayoutPutsExamplesInExamplesNotItems() throws {
        let html = try loadFixture("vendor_intro_table")

        let intro = try VendorIntroParser.parse(html: html)
        let milk = try XCTUnwrap(intro.categories.first)

        XCTAssertEqual(milk.examples, "測試低脂鮮乳、測試高品質鮮乳等")
        XCTAssertTrue(milk.items.isEmpty)
        XCTAssertNil(milk.statedCount)
        XCTAssertFalse(milk.isAllItems)
    }

    func testTableLayoutSkipsHeaderRow() throws {
        let html = try loadFixture("vendor_intro_table")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertFalse(intro.categories.contains { $0.name == "類別名稱" })
    }

    func testTableLayoutDecodesEntities() throws {
        let html = try loadFixture("vendor_intro_table")

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertTrue(intro.categories.contains { $0.name == "堅果 & 核仁類" })
    }

    // MARK: - 失敗路徑

    /// **契約改過一次，理由留著**：兩種版型都不在時，原本是丟 `AppError.parsing`
    /// 讓上層報警。現在改成退到純文字仍給出內容（見下方 `.unrecognised` 的測試），
    /// 因為這一頁是純資訊，讓使用者看到「大概能換什麼」比看到錯誤畫面有用。
    /// 報警的責任因此轉移到 `VendorIntro.layout`——呼叫端看到 `.unrecognised` 要自己回報。
    ///
    /// 只有**連一段可讀文字都撈不到**時才還是丟例外：那種頁面根本不是商品頁
    /// （被導去登入頁、拿到錯誤頁），硬湊一個空清單給使用者看沒有意義。
    func testThrowsParsingWhenThereIsNothingToShowAtAll() throws {
        let html = "<html><body><h1>某頁</h1><div><span>沒有清單也沒有段落</span></div></body></html>"

        XCTAssertThrowsError(try VendorIntroParser.parse(html: html)) { error in
            guard case AppError.parsing = error else {
                return XCTFail("預期 AppError.parsing，實際是 \(error)")
            }
        }
    }

    func testFallsBackToDefaultTitleWhenHeadingMissing() throws {
        let html = """
        <main><table><tbody><tr><td>類別</td><td>舉例</td></tr></tbody></table></main>
        """

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.title, "可兌換商品")
        XCTAssertNil(intro.subtitle)
        XCTAssertTrue(intro.notices.isEmpty)
    }

    // MARK: - 認不出版型時的最小可用結果

    /// 兩種已知版型都對不上時**不丟例外**，退到純文字仍給出內容，
    /// 並把 `layout` 標成 `.unrecognised` 讓呼叫端發警報。
    func testFallsBackToPlainTextWhenLayoutIsUnrecognised() throws {
        let html = """
        <main>
          <h1>示範超商 Z可兌換商品</h1>
          <section class="catalog">
            <ul class="new-markup">
              <li><span>示範品項 A</span>示範品項 A</li>
              <li>示範品項 B</li>
              <li>示範品項 C</li>
            </ul>
          </section>
          <aside class="notice"><h2>兌換注意事項</h2><p>依門市現場公告為準。</p></aside>
        </main>
        """

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.layout, .unrecognised)
        XCTAssertEqual(intro.title, "示範超商 Z可兌換商品")
        XCTAssertEqual(intro.categories.count, 1)
        XCTAssertEqual(intro.categories.first?.name, "商品資訊")
        XCTAssertTrue(intro.categories.first?.items.contains("示範品項 B") == true)
    }

    /// 退路不可以把頁尾注意事項也當成品項——那段由 `notices` 另外解析。
    func testFallbackExcludesNoticeText() throws {
        let html = """
        <main>
          <h1>示範超商 Z</h1>
          <ul><li>示範品項 A</li></ul>
          <aside class="notice"><p>依門市現場公告為準。</p></aside>
        </main>
        """

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.notices, ["依門市現場公告為準。"])
        XCTAssertFalse(intro.categories.first?.items.contains("依門市現場公告為準。") == true)
    }

    /// 沒有 `<li>` 時退一步用 `<p>`。
    func testFallbackUsesParagraphsWhenThereAreNoListItems() throws {
        let html = """
        <main>
          <h1>示範超商 Z</h1>
          <section><p>示範品項 A</p><p>示範品項 B</p></section>
        </main>
        """

        let intro = try VendorIntroParser.parse(html: html)

        XCTAssertEqual(intro.layout, .unrecognised)
        XCTAssertEqual(intro.categories.first?.items, ["示範品項 A", "示範品項 B"])
    }

    /// 已知版型要標對，不能全部落到 `.unrecognised`。
    func testKnownLayoutsAreLabelled() throws {
        XCTAssertEqual(try VendorIntroParser.parse(html: try loadFixture("vendor_intro_details")).layout,
                       .itemList)
        XCTAssertEqual(try VendorIntroParser.parse(html: try loadFixture("vendor_intro_table")).layout,
                       .categoryTable)
    }
}
