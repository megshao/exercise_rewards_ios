import XCTest
@testable import ExerciseRewardsKit

/// 驗證 VoucherParser 對合成最小 fixture 的解析（見 Tests/ExerciseRewardsKitTests/Fixtures/
/// voucher_view.html／voucher_verify_error.html）。純函式測試，不打網路。
final class VoucherParserTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - parseView

    func testParseViewExtractsTwoFiguresWithCode128() throws {
        let html = try loadFixture("voucher_view")

        let voucher = try VoucherParser.parseView(html: html)

        XCTAssertEqual(voucher.figures.count, 2)
        XCTAssertEqual(voucher.figures[0].format, "CODE_128")
        XCTAssertEqual(voucher.figures[0].value, "00000000")
        XCTAssertEqual(voucher.figures[1].format, "CODE_128")
        XCTAssertEqual(voucher.figures[1].value, "AAAA0000BBBB1111")
    }

    func testParseViewExtractsCaptionsInOrder() throws {
        let html = try loadFixture("voucher_view")

        let voucher = try VoucherParser.parseView(html: html)

        XCTAssertTrue(voucher.figures[0].caption.contains("商品條碼"))
        XCTAssertTrue(voucher.figures[1].caption.contains("券號條碼"))
    }

    func testParseViewExtractsVendorItemAndExpiry() throws {
        let html = try loadFixture("voucher_view")

        let voucher = try VoucherParser.parseView(html: html)

        XCTAssertTrue(voucher.vendorName.contains("示範超商 C"), "vendorName was: \(voucher.vendorName)")
        XCTAssertTrue(voucher.itemName.contains("超值"), "itemName was: \(voucher.itemName)")
        XCTAssertTrue(voucher.expiry.contains("115"), "expiry was: \(voucher.expiry)")
    }

    func testParseViewExtractsNotices() throws {
        let html = try loadFixture("voucher_view")

        let voucher = try VoucherParser.parseView(html: html)

        XCTAssertFalse(voucher.notices.isEmpty)
        XCTAssertTrue(voucher.notices.contains { $0.contains("不得以紙本列印") })
    }

    func testParseViewThrowsParsingWhenNoFigures() {
        let html = "<html><body>沒有券碼區塊</body></html>"

        XCTAssertThrowsError(try VoucherParser.parseView(html: html)) { error in
            guard let appError = error as? AppError, case .parsing = appError else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        }
    }

    // MARK: - parseVerifyError

    func testParseVerifyErrorExtractsRemainingCount() throws {
        let html = try loadFixture("voucher_verify_error")

        let parsed = VoucherParser.parseVerifyError(html: html)

        XCTAssertEqual(parsed.remaining, 2)
        XCTAssertTrue(parsed.message.contains("驗證碼錯誤"))
    }

    func testParseVerifyErrorFallsBackWhenNoticeMissing() {
        let html = "<html><body>沒有錯誤提示</body></html>"

        let parsed = VoucherParser.parseVerifyError(html: html)

        XCTAssertNil(parsed.remaining)
        XCTAssertFalse(parsed.message.isEmpty)
    }
}
