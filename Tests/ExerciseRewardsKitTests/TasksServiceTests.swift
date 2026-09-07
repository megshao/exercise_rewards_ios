import XCTest
@testable import ExerciseRewardsKit

/// 驗證 TasksService.screenshotImageURL：用已登入的 client 打 /member/screenshot/{id}，
/// 取 302 導向的絕對 Location（S3 presigned URL）。不打真實網路，全部透過 MockHTTPClient
/// （見 AuthServiceTests.swift）。
final class TasksServiceTests: XCTestCase {
    private let taskID = "00000000-0000-4000-8000-000000000001"
    private var screenshotPath: String { "/member/screenshot/\(taskID)" }

    func testScreenshotImageURLReturnsRedirectLocationVerbatim() async throws {
        // Arrange
        let mock = MockHTTPClient()
        let s3URL = "https://example-bucket.s3.ap-northeast-1.amazonaws.com/uploads/photo123.jpg?X-Amz-Signature=abc123"
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

    // MARK: - M1：302 Location 的網域驗證
    //
    // `Location` 完全由官方站決定，是不受信任輸入。官網被入侵、或裝置信任了 MITM 憑證時
    // 它可以是任何東西，而這個 URL 會被直接交給圖片載入器。

    func testScreenshotImageURLBlocksThirdPartyHost() async {
        // Arrange：把使用者的 IP／UA／開啟時間送給第三方的典型 payload。
        let mock = MockHTTPClient()
        mock.redirectLocationByPath[screenshotPath] = "https://attacker.example/1x1.png"
        let sut = TasksService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.screenshotImageURL(taskID: taskID)
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .blockedEgress("attacker.example"))
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    func testScreenshotImageURLBlocksPlainHTTP() async {
        // Arrange：https 以外一律擋（明文載圖會洩漏截圖內容）。
        let mock = MockHTTPClient()
        mock.redirectLocationByPath[screenshotPath] = "http://bucket.s3.amazonaws.com/a.jpg"
        let sut = TasksService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.screenshotImageURL(taskID: taskID)
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .blockedEgress("bucket.s3.amazonaws.com"))
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    func testScreenshotImageURLAllowsOfficialSiteHost() async throws {
        // Arrange：官方站本身仍在白名單內（`ScreenshotView` 用 cookie-less session 下載，
        // 所以同源 GET 不會夾帶登入 cookie）。
        let mock = MockHTTPClient()
        let location = "https://500.gov.tw/registrant/member/screenshot/\(taskID)/raw"
        mock.redirectLocationByPath[screenshotPath] = location
        let sut = TasksService(http: mock)

        // Act
        let url = try await sut.screenshotImageURL(taskID: taskID)

        // Assert
        XCTAssertEqual(url.absoluteString, location)
    }

    func testIsAllowedScreenshotImageURLSuffixSpoofIsRejected() throws {
        // "amazonaws.com" 只是這個惡意網域的前綴，真正的 host 是 evil.com 的子網域。
        let spoof = try XCTUnwrap(URL(string: "https://amazonaws.com.evil.com/a.jpg"))
        XCTAssertFalse(TasksService.isAllowedScreenshotImageURL(spoof))

        let legit = try XCTUnwrap(URL(string: "https://bucket.s3.ap-northeast-1.amazonaws.com/a.jpg"))
        XCTAssertTrue(TasksService.isAllowedScreenshotImageURL(legit))
    }
}
