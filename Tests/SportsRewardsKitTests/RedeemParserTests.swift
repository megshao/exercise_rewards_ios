import XCTest
@testable import SportsRewardsKit

/// 驗證 RedeemParser 對 `/member/redeem/{uuid}` 頁面的解析：
/// Fixtures/redeem.html 有 5 家商店、其中萊爾富有兩個品項，共 6 支 item-row__form。
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

        // Assert: 全家、7-11、萊爾富x2、全聯、萬家福／樂家康 = 6
        XCTAssertEqual(options.count, 6)
    }

    func testFirstOptionIsFamilyMartWithVendorIdOne() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let first = try XCTUnwrap(options.first)

        // Assert
        XCTAssertEqual(first.vendorId, "1")
        XCTAssertTrue(first.vendorName.contains("全家"))
        XCTAssertFalse(first.itemId.isEmpty)
        XCTAssertEqual(first.itemId, "item-20260904-family")
        XCTAssertEqual(first.itemName, "50+3元加碼券")
        XCTAssertEqual(first.id, "1-item-20260904-family")
    }

    func testHilifeVendorHasTwoDistinctItems() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)
        let hilife = options.filter { $0.vendorName.contains("萊爾富") }

        // Assert
        XCTAssertEqual(hilife.count, 2)
        XCTAssertTrue(hilife.allSatisfy { $0.vendorId == "3" })
        XCTAssertEqual(Set(hilife.map(\.itemId)).count, 2)
    }

    func testSevenElevenAndPxMartAreParsed() throws {
        // Arrange
        let html = try loadFixture("redeem")

        // Act
        let options = try RedeemParser.parse(html: html)

        // Assert
        let seven = try XCTUnwrap(options.first { $0.vendorId == "2" })
        XCTAssertTrue(seven.vendorName.contains("7-11"))
        XCTAssertEqual(seven.itemId, "tmp-20260827-item-711")

        let pxmart = try XCTUnwrap(options.first { $0.vendorId == "5" })
        XCTAssertTrue(pxmart.vendorName.contains("全聯"))
    }

    func testThrowsParsingErrorWhenNoFormsFound() {
        // Act & Assert
        XCTAssertThrowsError(try RedeemParser.parse(html: "<html>no forms here</html>")) { error in
            guard case .parsing = error as? AppError else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        }
    }
}
