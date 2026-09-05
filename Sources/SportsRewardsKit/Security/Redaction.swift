import Foundation

/// 敏感字串遮罩工具。所有可能寫入 log / 錯誤訊息的個資都要先過這裡。
public enum Redact {
    /// 保留頭尾各 keep 碼，中間以 ● 遮罩。
    public static func middle(_ s: String, keepHead: Int = 3, keepTail: Int = 2) -> String {
        let chars = Array(s)
        guard chars.count > keepHead + keepTail else {
            return String(repeating: "●", count: max(chars.count, 1))
        }
        let head = String(chars.prefix(keepHead))
        let tail = String(chars.suffix(keepTail))
        return head + String(repeating: "●", count: chars.count - keepHead - keepTail) + tail
    }

    public static func idNo(_ s: String) -> String { middle(s, keepHead: 3, keepTail: 2) }
    public static func phone(_ s: String) -> String { middle(s, keepHead: 4, keepTail: 3) }
    public static func email(_ s: String) -> String {
        guard let at = s.firstIndex(of: "@") else { return middle(s) }
        let user = String(s[s.startIndex..<at])
        let domain = String(s[at...])
        return middle(user, keepHead: 1, keepTail: 1) + domain
    }
    public static func fully(_ s: String) -> String { String(repeating: "●", count: max(s.count, 1)) }
}

// MARK: - 敏感樣式偵測

/// 「這串字看起來像個資嗎？」的偵測器。
///
/// **為什麼需要**：`Redact.idNo(_:)` 那組函式是「呼叫端已經知道這是個資」才會用到的遮罩工具，
/// 靠的是自律。但遙測（Analytics/Crashlytics）與 log 的參數常常是層層轉手來的字串，
/// 呼叫端未必知道裡面夾了什麼。這組偵測器讓出口端（`Telemetry`、`SecureLog`）可以在送出前
/// 自己檢查一次，**把「不小心夾帶個資」從自律問題變成機制問題**。
///
/// **刻意寧可誤判**：樣式故意放寬（例如任何 10 碼以上連續數字都算可疑）。遙測參數本來就
/// 只該是有限集合的短字串與數字，誤判的代價是「少一個事件」，漏判的代價是「個資外流」。
extension Redact {
    /// 可辨識的敏感樣式種類。新增樣式時同步更新 `patterns`。
    public enum SensitiveKind: String, Sendable, CaseIterable {
        /// 中華民國身分證號 / 居留證號（1 英文字母 + 9 碼數字）
        case taiwanID
        /// 台灣手機門號（09xxxxxxxx、+8869xxxxxxxx）
        case phone
        /// 電子郵件位址
        case email
        /// 日期（生日；YYYY-MM-DD 或 YYYY/M/D）
        case birthDate
        /// UUID（裝置/安裝識別碼、券的內部 id）
        case uuid
        /// 10 碼以上連續數字（券碼、健保卡號、序號、身分證去掉字母後的樣子）
        case longDigitSequence
    }

    /// 已編譯的樣式表。`NSRegularExpression` 對 matching 是 thread-safe 的（Apple 文件明載），
    /// 但型別本身沒有 Sendable 標註，這裡用不可變的包裝盒過 Swift 6 strict concurrency。
    private struct PatternTable: @unchecked Sendable {
        let entries: [(kind: SensitiveKind, regex: NSRegularExpression)]

        init(_ raw: [(SensitiveKind, String)]) {
            entries = raw.compactMap { kind, pattern in
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
                return (kind, regex)
            }
        }
    }

    private static let patternTable = PatternTable([
        // 刻意比「合法身分證號」更寬：任何「1 個英文字母 + 9 碼數字」都算命中。
        // 檢查碼錯的、居留證號、以及示範模式的哨兵值 A000000000 都會被擋下來。
        (.taiwanID, #"(?<![A-Za-z0-9])[A-Za-z]\d{9}(?![A-Za-z0-9])"#),
        (.phone, #"(?<!\d)(?:\+?886-?|0)9\d{2}-?\d{3}-?\d{3}(?!\d)"#),
        (.email, #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#),
        (.birthDate, #"(?<!\d)(?:18|19|20)\d{2}[-/.]\d{1,2}[-/.]\d{1,2}(?!\d)"#),
        (.uuid, #"(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?![0-9a-f])"#),
        (.longDigitSequence, #"(?<!\d)\d{10,}(?!\d)"#),
    ])

    /// 回傳這段字串命中的所有敏感樣式（沒命中就是空集合）。
    public static func sensitiveKinds(in text: String) -> Set<SensitiveKind> {
        guard !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var found: Set<SensitiveKind> = []
        for entry in patternTable.entries
        where entry.regex.firstMatch(in: text, options: [], range: range) != nil {
            found.insert(entry.kind)
        }
        return found
    }

    /// 便利判斷：這段字串裡有沒有看起來像個資的東西。
    public static func containsSensitive(_ text: String) -> Bool {
        !sensitiveKinds(in: text).isEmpty
    }

    /// 把字串裡命中樣式的片段就地遮成 `[已遮蔽:種類]`，其餘原文保留。
    /// 用於錯誤訊息這種「必須保留上下文才有除錯價值」的場合。
    public static func scrub(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for entry in patternTable.entries {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = entry.regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "[已遮蔽:\(entry.kind.rawValue)]"
            )
        }
        return result
    }
}
