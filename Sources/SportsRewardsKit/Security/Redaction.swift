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
