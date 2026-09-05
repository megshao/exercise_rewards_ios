import Foundation

/// 兌換服務：GET 兌換頁解析商家品項清單、POST 送出兌換申請。
///
/// ⚠️ `redeem(taskID:vendorId:item:)` 會實際消耗使用者的兌換次數且送出後不可更換。
/// 官網送出表單後該期即進入 state=REDEEMED；要看券碼還需再走一次簡訊 OTP 驗證，
/// 該流程由 `VoucherServicing`/`VoucherService` 負責，這裡只能 best-effort 判斷兌換表單是否送出成功，回一段友善訊息。
/// 呼叫端（UI）必須先讓使用者二次確認過警語，才可以呼叫這支方法。
public final class RedeemService: RedeemServicing {
    private let http: HTTPClienting
    private let log = SecureLog(.redeem)

    public init(http: HTTPClienting) {
        self.http = http
    }

    public func options(taskID: String) async throws -> [RedeemOption] {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        let html = try await http.getHTML(path: redeemPath(taskID))
        let options = try RedeemParser.parse(html: html)
        log.debug("parsed \(options.count) redeem options")
        return options
    }

    public func redeem(taskID: String, vendorId: String, item: String) async throws -> RedeemResult {
        guard !taskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.parsing("empty taskID")
        }
        let path = redeemPath(taskID)
        let html = try await http.getHTML(path: path)
        let csrf = try CsrfParser.extract(from: html)

        let result = try await http.postForm(
            path: path,
            fields: [
                ("_csrf", csrf),
                ("vendorId", vendorId),
                ("item", item)
            ]
        )

        // 官網送出兌換表單後該期即進入 state=REDEEMED；要看券碼還需再走一次簡訊 OTP 驗證，
        // 由 VoucherServicing（App 端 VoucherView）接手，這裡只回報表單是否成功送出。
        if result.statusCode == 302 {
            log.info("redeem form submitted (302)")
            return RedeemResult(submitted: true, message: "已送出兌換，請完成簡訊驗證後檢視加碼券")
        }
        if result.statusCode == 200 {
            // 停留在兌換頁：可能是表單驗證失敗，或該品項已被兌完/狀態已變化。
            log.info("redeem form stayed on page (200)")
            return RedeemResult(submitted: false, message: "兌換未成功，請重新整理頁面確認任務與品項狀態")
        }
        log.error("redeem form returned unexpected status")
        throw AppError.unexpectedResponse(result.statusCode)
    }

    private func redeemPath(_ taskID: String) -> String {
        "/member/redeem/" + taskID
    }
}
