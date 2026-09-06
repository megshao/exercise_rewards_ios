import XCTest
@testable import SportsRewardsKit

/// 驗證 RedeemParser 對 `/member/redeem/{uuid}` 頁面的解析：
/// Fixtures/redeem.html 為合成測試資料：5 家示範商家、其中示範超商 C 有兩個品項，共 6 支 item-row__form。
///
/// fixture 也刻意涵蓋「兌換品項」連結的四種情形：帶 context path、不帶 context path、
/// 完全沒有連結、以及指向站外的惡意 href。
final class RedeemParserTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParseReturnsAllItemsAcrossAllVendors() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)

        // Assert: 示範超商 A、B、C x2、示範超市 D、示範量販 E = 6
        XCTAssertEqual(options.count, 6)
    }

    func testFirstOptionIsVendorAWithVendorIdOne() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let first = try XCTUnwrap(options.first)

        // Assert
        XCTAssertEqual(first.vendorId, "1")
        XCTAssertTrue(first.vendorName.contains("示範超商 A"))
        XCTAssertFalse(first.itemId.isEmpty)
        XCTAssertEqual(first.itemId, "test-item-0001")
        XCTAssertEqual(first.itemName, "測試品項 A1")
        XCTAssertEqual(first.id, "1-test-item-0001")
    }

    func testVendorCHasTwoDistinctItems() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let vendorC = options.filter { $0.vendorName.contains("示範超商 C") }

        // Assert
        XCTAssertEqual(vendorC.count, 2)
        XCTAssertTrue(vendorC.allSatisfy { $0.vendorId == "3" })
        XCTAssertEqual(Set(vendorC.map(\.itemId)).count, 2)
    }

    func testVendorBAndVendorDAreParsed() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)

        // Assert
        let vendorB = try XCTUnwrap(options.first { $0.vendorId == "2" })
        XCTAssertTrue(vendorB.vendorName.contains("示範超商 B"))
        XCTAssertEqual(vendorB.itemId, "test-item-0002")

        let vendorD = try XCTUnwrap(options.first { $0.vendorId == "5" })
        XCTAssertTrue(vendorD.vendorName.contains("示範超市 D"))
    }

    func testThrowsParsingErrorWhenNoFormsFound() {
        // Act & Assert
        XCTAssertThrowsError(try RedeemParser.parse(html: "<html>no forms here</html>")) { error in
            guard case .parsing = error as? AppError else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        }
    }

    // MARK: - 兌換品項連結（introPath）

    func testIntroPathStripsContextPath() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let first = try XCTUnwrap(options.first)

        // Assert：官網的 href 是 `/registrant/intro/vendor-1.html`，
        // 但 HTTPClienting.getHTML 收的是 base-relative path。
        XCTAssertEqual(first.introPath, "/intro/vendor-1.html")
    }

    func testIntroPathAcceptsHrefWithoutContextPath() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let vendorD = try XCTUnwrap(options.first { $0.vendorName.contains("示範超市 D") })

        // Assert
        XCTAssertEqual(vendorD.introPath, "/intro/vendor-5.html")
    }

    /// 官網的規則是「靜態頁存在才長出連結」，所以沒有連結是正常狀況，
    /// 不可以自己用 vendorId 拼一個網址出來（那會拼出 404）。
    func testIntroPathIsNilWhenVendorHasNoIntroLink() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let vendorB = try XCTUnwrap(options.first { $0.vendorName.contains("示範超商 B") })

        // Assert
        XCTAssertNil(vendorB.introPath)
    }

    /// href 是不受信任輸入，而它會被拿去發請求，因此採白名單：
    /// 只收 `/intro/<檔名>.html`，站外絕對網址一律不採用。
    func testIntroPathRejectsOffSiteAbsoluteURL() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let vendorE = try XCTUnwrap(options.first { $0.vendorName.contains("示範量販 E") })

        // Assert
        XCTAssertNil(vendorE.introPath)
    }

    func testIntroPathRejectsPathTraversalAndOtherNamespaces() throws {
        // Arrange：同一列裡塞進三種不該被採用的 href。
        let cases = [
            "/registrant/intro/../member/tasks",
            "/registrant/member/redeem/00000000-0000-4000-8000-000000000001",
            "/registrant/intro/vendor-1.html?next=https://evil.example.com",
        ]

        for href in cases {
            let html = """
            <li class="item-row">
              <div class="item-row__actions">
                <a href="\(href)" class="btn item-row__intro">兌換品項</a>
                <form class="item-row__form" data-vendor-name="示範超商 A" data-item-name="測試品項 A1">
                  <input type="hidden" name="vendorId" value="1">
                  <input type="hidden" name="item" value="test-item-0001">
                </form>
              </div>
            </li>
            """

            // Act
            let options = try RedeemParser.parse(html: html)

            // Assert
            XCTAssertNil(options.first?.introPath, "不該採用的 href：\(href)")
        }
    }

    /// 介紹頁連結是 `<form>` 的前一個兄弟節點。切塊邊界若退回以 form 為單位，
    /// 這個測試會抓到——品項照樣解析得到，但 introPath 會變成 nil。
    func testIntroPathBelongsToItsOwnRowNotTheNeighbouringOne() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)

        // Assert：B 沒有連結，不可以把 A 的連結沾過來；C 的兩個品項各自都有。
        XCTAssertEqual(options.map(\.introPath),
                       ["/intro/vendor-1.html",
                        nil,
                        "/intro/vendor-3.html",
                        "/intro/vendor-3.html",
                        "/intro/vendor-5.html",
                        nil])
    }
}
