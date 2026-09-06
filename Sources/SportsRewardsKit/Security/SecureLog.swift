import Foundation
import os

/// 全專案唯一 log 入口。設計原則：
/// - 個資（身分證/生日/手機/email/健保卡/cookie/CSRF/OTP/session）一律禁止進 log。
/// - 呼叫端只能傳「已遮罩或非敏感」的訊息；提供 category 分流。
/// - release build 下 debug/info 不輸出敏感層級（僅保留 error 的非敏感訊息）。
public enum LogCategory: String, Sendable {
    case auth, network, tasks, redeem, voucher, ui, security
}

public struct SecureLog: Sendable {
    private let logger: Logger
    private let category: LogCategory

    public init(_ category: LogCategory) {
        self.category = category
        self.logger = Logger(subsystem: "com.megshao.sportsrewards", category: category.rawValue)
    }

    /// 開發用細節。release 不輸出。
    public func debug(_ message: @autoclosure @escaping () -> String) {
        #if DEBUG
        logger.debug("\(message(), privacy: .public)")
        #endif
    }

    /// 一般事件（不得含個資）。
    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    /// 錯誤（不得含個資；如需帶值請先用 Redact）。
    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
