import Foundation

/// 檢視加碼券服務：兌換完成（state=REDEEMED）後的簡訊 OTP 驗證 + 券碼頁解析。
///
/// ⚠️ 合規要求「須本人帳號即時畫面抵用、不得截圖」——本 service 完全不做任何快取，
/// `fetchVoucher` 每次呼叫都會重新打一次 `/member/voucher/{uuid}/view`；呼叫端（VoucherView）
/// 也絕不可以把解析出的 `Voucher` 存起來跨畫面重用，離開畫面就要丟棄，下次進入重新走一次
/// `sendOtp` → `verifyOtp` → `fetchVoucher`。
///
/// 端點：
/// - 檢視頁：`GET /member/voucher/{uuid}`（含 resend/verify 兩個 form 的 `_csrf`）
/// - 發送：`POST /member/voucher/{uuid}/resend`（body `_csrf`）
/// - 驗證：`POST /member/voucher/{uuid}`（body `_csrf`,`otp`）→ 200+`.notice--error` 或 302 到 `.../view`
/// - 券碼頁：`GET /member/voucher/{uuid}/view`
public final class VoucherService: VoucherServicing {
    private let http: HTTPClienting
    private let log = SecureLog(.voucher)

    public init(http: HTTPClienting) {
        self.http = http
    }

    public func sendOtp(taskID: String) async throws {
        let uuid = try validated(taskID)
        let path = voucherPath(uuid)
        let html = try await http.getHTML(path: path)
        let csrf = try CsrfParser.extract(from: html)

        let result = try await http.postForm(
            path: resendPath(uuid),
            fields: [("_csrf", csrf)]
        )

        guard result.statusCode == 200 || result.statusCode == 302 else {
            log.error("sendOtp returned unexpected status")
            throw AppError.unexpectedResponse(result.statusCode)
        }
        log.info("otp resend requested")
    }

    public func verifyOtp(taskID: String, otp: String) async throws -> VoucherOtpResult {
        let uuid = try validated(taskID)
        let path = voucherPath(uuid)
        let html = try await http.getHTML(path: path)
        let csrf = try CsrfParser.extract(from: html)

        let result = try await http.postForm(
            path: path,
            fields: [("_csrf", csrf), ("otp", otp)]
        )

        if result.statusCode == 302, let location = result.location, location.contains("/view") {
            log.info("otp verified (302 -> view)")
            return .success
        }
        if result.statusCode == 200 {
            let parsed = VoucherParser.parseVerifyError(html: result.body)
            log.info("otp verify stayed on page (200)")
            return .wrongCode(remaining: parsed.remaining)
        }
        log.error("otp verify returned unexpected status")
        return .failed(message: "驗證失敗，請稍後再試")
    }

    public func fetchVoucher(taskID: String) async throws -> Voucher {
        let uuid = try validated(taskID)
        let html = try await http.getHTML(path: viewPath(uuid))
        let voucher = try VoucherParser.parseView(html: html)
        log.debug("parsed voucher with \(voucher.figures.count) figure(s)")
        return voucher
    }

    private func validated(_ taskID: String) throws -> String {
        let trimmed = taskID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        return trimmed
    }

    private func voucherPath(_ taskID: String) -> String {
        "/member/voucher/" + taskID
    }

    private func resendPath(_ taskID: String) -> String {
        voucherPath(taskID) + "/resend"
    }

    private func viewPath(_ taskID: String) -> String {
        voucherPath(taskID) + "/view"
    }
}
