import Foundation

/// 登入/登出服務。實作官方站無 OTP 的兩段式登入序列：
/// access（身分證核對）→ login（三碼核對）。
public final class AuthService: AuthServicing {
    private let http: HTTPClienting
    private let log = SecureLog(.auth)

    public init(http: HTTPClienting) {
        self.http = http
    }

    public func login(_ credentials: LoginCredentials) async throws -> LoginOutcome {
        // 明確重新登入前先清掉舊 cookie/session：持久化 cookie 若殘留過期的 JSESSIONID／
        // LBSCookie，會讓 GET /access 拿到的 _csrf 綁在死掉的舊 session 上，POST 被打回，
        // 造成登入一直失敗。清乾淨再走 access→login 握手，確保每次登入都是全新 session。
        await http.resetSession()

        let accessCsrf = try await fetchCsrf(path: "/access")

        let accessResult = try await http.postForm(
            path: "/access",
            fields: [
                ("_csrf", accessCsrf),
                ("idNo", credentials.idNo)
            ]
        )

        guard accessResult.statusCode == 302, let accessLocation = accessResult.location else {
            log.error("access step returned unexpected status")
            throw AppError.unexpectedResponse(accessResult.statusCode)
        }

        if accessLocation.contains("/register") {
            log.info("access redirected to register: idNo not registered")
            return .notRegistered
        }

        guard accessLocation.contains("/login") else {
            log.error("access step redirected to unexpected location")
            throw AppError.unexpectedResponse(accessResult.statusCode)
        }

        let loginCsrf = try await fetchCsrf(path: "/login")

        let loginResult = try await http.postForm(
            path: "/login",
            fields: [
                ("_csrf", loginCsrf),
                ("idNo", credentials.idNo),
                ("birthDate", credentials.birthDate),
                ("phone", credentials.phone)
            ]
        )

        if loginResult.statusCode == 302, let loginLocation = loginResult.location {
            if loginLocation.contains("/member/tasks") {
                log.info("login succeeded")
                return .success
            }
            if loginLocation.contains("/login") {
                log.info("login redirected back to login page: invalid credentials")
                return .invalidCredentials
            }
            log.error("login step redirected to unexpected location")
            throw AppError.unexpectedResponse(loginResult.statusCode)
        }

        if loginResult.statusCode == 200 {
            // 停在登入頁（表單驗證失敗），三碼不符
            log.info("login stayed on login page: invalid credentials")
            return .invalidCredentials
        }

        log.error("login step returned unexpected status")
        throw AppError.unexpectedResponse(loginResult.statusCode)
    }

    public func logout() async throws {
        let html: String
        do {
            html = try await http.getHTML(path: "/member/tasks")
        } catch {
            html = try await http.getHTML(path: "/login")
        }
        let csrf = try Self.extractCsrf(from: html)
        _ = try await http.postForm(path: "/logout", fields: [("_csrf", csrf)])
        await http.resetSession()
        log.info("logout completed")
    }

    private func fetchCsrf(path: String) async throws -> String {
        let html = try await http.getHTML(path: path)
        return try Self.extractCsrf(from: html)
    }

    /// 從 HTML 取出 `_csrf` hidden input 的 value（委派給共用的 `CsrfParser`）。
    private static func extractCsrf(from html: String) throws -> String {
        try CsrfParser.extract(from: html)
    }
}
