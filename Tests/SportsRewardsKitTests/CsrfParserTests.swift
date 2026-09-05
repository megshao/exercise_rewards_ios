import XCTest
@testable import SportsRewardsKit

final class CsrfParserTests: XCTestCase {
    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            throw AppError.parsing("fixture missing")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testExtractReturnsTokenFromAccessFixture() throws {
        // Arrange
        let html = try loadFixture("access")

        // Act
        let token = try CsrfParser.extract(from: html)

        // Assert
        XCTAssertEqual(token, "test-csrf-token-access")
    }

    func testExtractReturnsTokenFromLoginFixture() throws {
        // Arrange
        let html = try loadFixture("login")

        // Act
        let token = try CsrfParser.extract(from: html)

        // Assert
        XCTAssertEqual(token, "test-csrf-token-member")
    }

    func testExtractThrowsCsrfNotFoundOnEmptyString() {
        // Arrange
        let html = ""

        // Act & Assert
        XCTAssertThrowsError(try CsrfParser.extract(from: html)) { error in
            XCTAssertEqual(error as? AppError, .csrfNotFound)
        }
    }

    func testExtractThrowsCsrfNotFoundWhenValueAttributeMissing() {
        // Arrange
        let html = #"<input type="hidden" name="_csrf"/>"#

        // Act & Assert
        XCTAssertThrowsError(try CsrfParser.extract(from: html)) { error in
            XCTAssertEqual(error as? AppError, .csrfNotFound)
        }
    }

    func testExtractWorksRegardlessOfAttributeOrder() throws {
        // Arrange: value 屬性在 name 之前
        let html = #"<input type="hidden" value="tokenXYZ" name="_csrf"/>"#

        // Act
        let token = try CsrfParser.extract(from: html)

        // Assert
        XCTAssertEqual(token, "tokenXYZ")
    }
}
