import XCTest
@testable import SportsRewardsKit

/// 可程式化每個 path 回應的假 HTTPClienting，供 AuthServiceTests 使用。不打真實網路。
final class MockHTTPClient: HTTPClienting, @unchecked Sendable {
    var htmlByPath: [String: String] = [:]
    var formResultByPath: [String: HTTPFormResult] = [:]
    var redirectLocationByPath: [String: String?] = [:]

    private(set) var getPaths: [String] = []
    private(set) var postPaths: [String] = []
    private(set) var postFields: [String: [(String, String)]] = [:]
    private(set) var redirectPaths: [String] = []
    private(set) var resetSessionCallCount = 0

    func getHTML(path: String) async throws -> String {
        getPaths.append(path)
        guard let html = htmlByPath[path] else {
            throw AppError.unexpectedResponse(404)
        }
        return html
    }

    func postForm(path: String, fields: [(String, String)]) async throws -> HTTPFormResult {
        postPaths.append(path)
        postFields[path] = fields
        guard let result = formResultByPath[path] else {
            throw AppError.unexpectedResponse(404)
        }
        return result
    }

    /// 非 3xx（或未事先程式化）一律回 nil，對齊真實 `redirectLocation` 的語意。
    func redirectLocation(path: String) async throws -> String? {
        redirectPaths.append(path)
        return redirectLocationByPath[path] ?? nil
    }

    private(set) var uploadPaths: [String] = []
    private(set) var uploadFileFields: [String] = []
    var uploadResultByPath: [String: HTTPFormResult] = [:]

    func uploadMultipart(path: String, fields: [(String, String)], fileField: String,
                         fileName: String, mimeType: String, fileData: Data) async throws -> HTTPFormResult {
        uploadPaths.append(path)
        uploadFileFields.append(fileField)
        guard let result = uploadResultByPath[path] else {
            throw AppError.unexpectedResponse(404)
        }
        return result
    }

    func resetSession() async {
        resetSessionCallCount += 1
    }
}

final class AuthServiceTests: XCTestCase {
    private let credentials = LoginCredentials(idNo: "A123456789", birthDate: "1990-01-01", phone: "0912345678")

    private func makeAccessHTML(csrf: String) -> String {
        "<input type=\"hidden\" name=\"_csrf\" value=\"\(csrf)\"/>"
    }

    // MARK: - success

    func testLoginReturnsSuccessWhenLoginRedirectsToMemberTasks() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/access"] = makeAccessHTML(csrf: "access-csrf")
        mock.htmlByPath["/login"] = makeAccessHTML(csrf: "login-csrf")
        mock.formResultByPath["/access"] = HTTPFormResult(statusCode: 302, location: "/login", body: "")
        mock.formResultByPath["/login"] = HTTPFormResult(statusCode: 302, location: "/member/tasks", body: "")
        let sut = AuthService(http: mock)

        // Act
        let outcome = try await sut.login(credentials)

        // Assert
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(mock.getPaths, ["/access", "/login"])
        XCTAssertEqual(mock.postPaths, ["/access", "/login"])

        let accessFields = try XCTUnwrap(mock.postFields["/access"])
        XCTAssertTrue(accessFields.contains { $0.0 == "_csrf" && $0.1 == "access-csrf" })
        XCTAssertTrue(accessFields.contains { $0.0 == "idNo" && $0.1 == credentials.idNo })

        let loginFields = try XCTUnwrap(mock.postFields["/login"])
        XCTAssertTrue(loginFields.contains { $0.0 == "_csrf" && $0.1 == "login-csrf" })
        XCTAssertTrue(loginFields.contains { $0.0 == "birthDate" && $0.1 == credentials.birthDate })
        XCTAssertTrue(loginFields.contains { $0.0 == "phone" && $0.1 == credentials.phone })
    }

    // MARK: - notRegistered

    func testLoginReturnsNotRegisteredWhenAccessRedirectsToRegister() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/access"] = makeAccessHTML(csrf: "access-csrf")
        mock.formResultByPath["/access"] = HTTPFormResult(statusCode: 302, location: "/register", body: "")
        let sut = AuthService(http: mock)

        // Act
        let outcome = try await sut.login(credentials)

        // Assert
        XCTAssertEqual(outcome, .notRegistered)
        // 未註冊時不應該再打 /login
        XCTAssertEqual(mock.getPaths, ["/access"])
        XCTAssertEqual(mock.postPaths, ["/access"])
    }

    // MARK: - invalidCredentials

    func testLoginReturnsInvalidCredentialsWhenLoginRedirectsBackToLoginPage() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/access"] = makeAccessHTML(csrf: "access-csrf")
        mock.htmlByPath["/login"] = makeAccessHTML(csrf: "login-csrf")
        mock.formResultByPath["/access"] = HTTPFormResult(statusCode: 302, location: "/login", body: "")
        mock.formResultByPath["/login"] = HTTPFormResult(statusCode: 302, location: "/login", body: "")
        let sut = AuthService(http: mock)

        // Act
        let outcome = try await sut.login(credentials)

        // Assert
        XCTAssertEqual(outcome, .invalidCredentials)
        XCTAssertEqual(mock.getPaths, ["/access", "/login"])
        XCTAssertEqual(mock.postPaths, ["/access", "/login"])
    }

    func testLoginReturnsInvalidCredentialsWhenLoginStaysOnPageWith200() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/access"] = makeAccessHTML(csrf: "access-csrf")
        mock.htmlByPath["/login"] = makeAccessHTML(csrf: "login-csrf")
        mock.formResultByPath["/access"] = HTTPFormResult(statusCode: 302, location: "/login", body: "")
        mock.formResultByPath["/login"] = HTTPFormResult(statusCode: 200, location: nil, body: "<html>login page</html>")
        let sut = AuthService(http: mock)

        // Act
        let outcome = try await sut.login(credentials)

        // Assert
        XCTAssertEqual(outcome, .invalidCredentials)
    }

    // MARK: - error scenarios

    func testLoginThrowsWhenAccessStepReturnsUnexpectedStatus() async {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/access"] = makeAccessHTML(csrf: "access-csrf")
        mock.formResultByPath["/access"] = HTTPFormResult(statusCode: 500, location: nil, body: "")
        let sut = AuthService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.login(credentials)
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .unexpectedResponse(500))
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    func testLoginThrowsCsrfNotFoundWhenAccessHTMLHasNoCsrf() async {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/access"] = "<html>no csrf here</html>"
        let sut = AuthService(http: mock)

        // Act & Assert
        do {
            _ = try await sut.login(credentials)
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .csrfNotFound)
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    // MARK: - logout

    func testLogoutPostsCsrfAndResetsSession() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/member/tasks"] = makeAccessHTML(csrf: "tasks-csrf")
        mock.formResultByPath["/logout"] = HTTPFormResult(statusCode: 302, location: "/", body: "")
        let sut = AuthService(http: mock)

        // Act
        try await sut.logout()

        // Assert
        XCTAssertEqual(mock.getPaths, ["/member/tasks"])
        XCTAssertEqual(mock.postPaths, ["/logout"])
        let fields = try XCTUnwrap(mock.postFields["/logout"])
        XCTAssertTrue(fields.contains { $0.0 == "_csrf" && $0.1 == "tasks-csrf" })
        XCTAssertEqual(mock.resetSessionCallCount, 1)
    }

    func testLogoutFallsBackToLoginPageWhenTasksPageUnavailable() async throws {
        // Arrange
        let mock = MockHTTPClient()
        mock.htmlByPath["/login"] = makeAccessHTML(csrf: "login-csrf")
        mock.formResultByPath["/logout"] = HTTPFormResult(statusCode: 302, location: "/", body: "")
        let sut = AuthService(http: mock)

        // Act
        try await sut.logout()

        // Assert
        XCTAssertEqual(mock.getPaths, ["/member/tasks", "/login"])
        let fields = try XCTUnwrap(mock.postFields["/logout"])
        XCTAssertTrue(fields.contains { $0.0 == "_csrf" && $0.1 == "login-csrf" })
        XCTAssertEqual(mock.resetSessionCallCount, 1)
    }
}
