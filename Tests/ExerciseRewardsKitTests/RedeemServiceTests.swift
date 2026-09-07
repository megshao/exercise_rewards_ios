import XCTest
@testable import ExerciseRewardsKit

/// 驗證 RedeemService：不打真實網路，全部透過 MockHTTPClient（見 AuthServiceTests.swift）。
final class RedeemServiceTests: XCTestCase {
    private let taskID = "00000000-0000-4000-8000-000000000001"
    private var redeemPath: String { "/member/redeem/\(taskID)" }

    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - options

    func testOptionsFetchesRedeemPageAndParsesFixture() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath[redeemPath] = try loadFixture("redeem")
        let sut = RedeemService(http: mock)

        // Act
        let options = try await sut.options(taskID: taskID)

        // Assert
        XCTAssertEqual(mock.getPaths, [redeemPath])
        XCTAssertEqual(options.count, 6)
        XCTAssertEqual(options.first?.vendorId, "1")
    }

    func testOptionsThrowsParsingWhenTaskIDEmpty() async {
        // Arrange
        let mock = MockHTTPClient()
        let sut = RedeemService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.options(taskID: "  ")
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .parsing = error else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
        XCTAssertTrue(mock.getPaths.isEmpty, "should not hit network for an empty taskID")
    }

    // MARK: - redeem

    func testRedeemFetchesCsrfFirstThenPostsVendorAndItem() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath[redeemPath] = try loadFixture("redeem")
        mock.formResultByPath[redeemPath] = HTTPFormResult(statusCode: 302, location: "/member/tasks", body: "")
        let sut = RedeemService(http: mock)

        // Act
        let result = try await sut.redeem(taskID: taskID, vendorId: "1", item: "test-item-0001")

        // Assert: GET 先於 POST，且 POST 帶正確 path / fields
        XCTAssertTrue(result.submitted)
        XCTAssertFalse(result.message.isEmpty)
        XCTAssertEqual(mock.getPaths, [redeemPath])
        XCTAssertEqual(mock.postPaths, [redeemPath])

        let fields = try XCTUnwrap(mock.postFields[redeemPath])
        XCTAssertTrue(fields.contains { $0.0 == "_csrf" && $0.1 == "test-csrf-token-member" })
        XCTAssertTrue(fields.contains { $0.0 == "vendorId" && $0.1 == "1" })
        XCTAssertTrue(fields.contains { $0.0 == "item" && $0.1 == "test-item-0001" })
    }

    func testRedeemReturnsNotSubmittedWhenStaysOnPageWith200() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath[redeemPath] = try loadFixture("redeem")
        mock.formResultByPath[redeemPath] = HTTPFormResult(statusCode: 200, location: nil, body: "<html>redeem page</html>")
        let sut = RedeemService(http: mock)

        // Act
        let result = try await sut.redeem(taskID: taskID, vendorId: "1", item: "test-item-0001")

        // Assert
        XCTAssertFalse(result.submitted)
        XCTAssertFalse(result.message.isEmpty)
    }

    func testRedeemThrowsOnUnexpectedStatus() async {
        // Arrange
        let mock = MockHTTPClient()
        do {
            mock.htmlByPath[redeemPath] = try loadFixture("redeem")
        } catch {
            XCTFail("failed to load fixture: \(error)")
        }
        mock.formResultByPath[redeemPath] = HTTPFormResult(statusCode: 500, location: nil, body: "")
        let sut = RedeemService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.redeem(taskID: taskID, vendorId: "1", item: "test-item-0001")
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .unexpectedResponse(500))
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    func testRedeemThrowsCsrfNotFoundWhenRedeemPageHasNoCsrf() async {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath[redeemPath] = "<html>no csrf here</html>"
        let sut = RedeemService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.redeem(taskID: taskID, vendorId: "1", item: "test-item-0001")
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .csrfNotFound)
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
        XCTAssertTrue(mock.postPaths.isEmpty, "should not POST when csrf missing")
    }
}
