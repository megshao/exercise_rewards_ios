import XCTest
@testable import SportsRewardsKit

/// 驗證 RedeemParser 對 `/member/redeem/{uuid}` 頁面的解析：
/// Fixtures/redeem.html 為合成測試資料：5 家示範商家、其中示範超商 C 有兩個品項，共 6 支 item-row__form。
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
}
