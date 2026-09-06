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

    /// 兩種版型的標記都不在＝官網換版型了，要丟 parsing 讓上層有機會報警，
    /// 而不是安靜地回一頁空清單。
    func testThrowsParsingWhenNeitherLayoutIsPresent() throws {
        let html = "<html><body><h1>某頁</h1><p>沒有分類卡也沒有表格</p></body></html>"

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
}
