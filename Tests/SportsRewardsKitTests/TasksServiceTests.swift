import XCTest
@testable import SportsRewardsKit

/// 驗證 TasksService.screenshotImageURL：用已登入的 client 打 /member/screenshot/{id}，
/// 取 302 導向的絕對 Location（S3 presigned URL）。不打真實網路，全部透過 MockHTTPClient
/// （見 AuthServiceTests.swift）。
final class TasksServiceTests: XCTestCase {
    private let taskID = "9f746d24-213d-43c8-b291-5183cab4c64f"
    private var screenshotPath: String { "/member/screenshot/\(taskID)" }

    func testScreenshotImageURLReturnsRedirectLocationVerbatim() async throws {
        // Arrange
        let mock = MockHTTPClient()
        let s3URL = "https://s3.hicloud.net.tw/bucket/uploads/photo123.jpg?X-Amz-Signature=abc123"
        mock.redirectLocationByPath[screenshotPath] = s3URL
        let sut = TasksService(http: mock)

        // Act
        let url = try await sut.screenshotImageURL(taskID: taskID)

        // Assert
        XCTAssertEqual(mock.redirectPaths, [screenshotPath])
        XCTAssertEqual(url.absoluteString, s3URL)
    }

    func testScreenshotImageURLThrowsWhenNoRedirect() async {
        // Arrange: 未程式化任何 redirectLocation，等同真實情境的「非 3xx」。
        let mock = MockHTTPClient()
        let sut = TasksService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.screenshotImageURL(taskID: taskID)
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .unexpectedResponse(0))
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    func testScreenshotImageURLThrowsParsingForEmptyTaskID() async {
        // Arrange
        let mock = MockHTTPClient()
        let sut = TasksService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.screenshotImageURL(taskID: "  ")
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .parsing = error else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
        XCTAssertTrue(mock.redirectPaths.isEmpty, "should not hit network for an empty taskID")
    }
}
