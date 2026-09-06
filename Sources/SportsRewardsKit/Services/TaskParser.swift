import Foundation

/// 解析 `/member/tasks` 頁面的 HTML，取出 14 期任務卡片。純函式、無副作用、無網路呼叫。
///
/// 每一期為一張 `<li class="period-card ...">` 卡片，內含：
/// - `.period-no`：第 N 期
/// - `.period-range`：yyyy/MM/dd ~ yyyy/MM/dd
/// - `.period-state--XXX`：後端算好的互斥狀態（見 `TaskState`）
/// - `.period-remaining`：剩餘時間文字（可能沒有）
/// - `.period-detail` 內的上傳/審核時間（可能沒有）
/// - 兌換 `/member/redeem/{uuid}` 或截圖 `/member/screenshot/{uuid}` 連結中的期別 UUID（可能沒有）
public enum TaskParser {
    /// 解析整頁 HTML，回傳依卡片出現順序排列的任務清單。
    /// - Throws: `AppError.parsing` 當頁面內完全找不到任何 `period-card` 卡片時（代表頁面結構跟預期不符）。
    public static func parse(html: String) throws -> [TaskPeriod] {
        let cards = splitCards(html)
        guard !cards.isEmpty else {
            throw AppError.parsing("no period-card found in /member/tasks HTML")
        }
        return cards.enumerated().map { offset, card in
            parseCard(card, fallbackIndex: offset + 1)
        }
    }

    /// 把整份 HTML 依 `<li class="period-card` 切成一張一張卡片的原始片段。
    private static func splitCards(_ html: String) -> [String] {
        let marker = "<li class=\"period-card"
        var cards: [String] = []
        var searchStart = html.startIndex

        while let markerRange = html.range(of: marker, range: searchStart..<html.endIndex) {
            let cardStart = markerRange.lowerBound
            let nextSearchStart = markerRange.upperBound
            let cardEnd: String.Index
            if let nextMarkerRange = html.range(of: marker, range: nextSearchStart..<html.endIndex) {
                cardEnd = nextMarkerRange.lowerBound
            } else if let closeULRange = html.range(of: "</ul>", range: nextSearchStart..<html.endIndex) {
                cardEnd = closeULRange.lowerBound
            } else {
                cardEnd = html.endIndex
            }
            cards.append(String(html[cardStart..<cardEnd]))
            searchStart = nextSearchStart
        }
        return cards
    }

    // MARK: - Patterns
    //
    // ReDoS 防線：這些樣式吃的是官方站回傳的 HTML，屬**不受信任輸入**。
    // 三條規則，違反其中任一條都可能讓單一請求把 cooperative thread pool 卡死：
    // 1. 相鄰量詞的字元集合不得重疊。`\s*([^<]+?)\s*<` 就是反例——`\s` ⊂ `[^<]`，
    //    三層量詞互相回溯，實測 800 個空白要 4 秒、1600 個要 34 秒（O(n³)）。
    //    正解是 `([^<]*)<`：`[^<]` 貪婪一定停在第一個 `<`，零回溯，事後再 trim。
    // 2. 所有量詞都要有長度上限（`{0,N}`），別讓單次比對的成本跟整頁長度成正比。
    // 3. 標籤屬性用 `[^<>]` 而非 `[^>]`——屬性內不可能出現裸 `<`，排除它可讓
    //    「大量未閉合標籤」的攻擊在下一個 `<` 就停住，而不是掃到文件尾。
    //
    // 另一道獨立防線在 `URLSessionHTTPClient.send`：response body 超過 2 MB 直接
    // 丟 `AppError.responseTooLarge`，parser 根本不會看到超長輸入。

    private static let indexPattern = #"第\s{0,8}(\d{1,6})\s{0,8}期"#
    private static let rangePattern = #"period-range">\s{0,8}([0-9/]{1,40})\s{0,8}~\s{0,8}([0-9/]{1,40})"#
    private static let statePattern = #"period-state--([A-Z_]{1,40})"#
    private static let remainingPattern = #"period-remaining">([^<]{0,2000})<"#
    private static let uploadedAtPattern = #"上傳時間：([^<]{0,2000})<"#
    private static let reviewedAtPattern = #"審核時間：([^<]{0,2000})<"#
    private static let idPattern = #"/member/(?:redeem|screenshot)/([0-9a-fA-F-]{1,64})"#

    /// 解析單張卡片片段。所有欄位都容錯：抓不到就給合理預設值，不丟例外。
    private static func parseCard(_ card: String, fallbackIndex: Int) -> TaskPeriod {
        let index = firstMatch(in: card, pattern: indexPattern).flatMap { Int($0) } ?? fallbackIndex

        var startDate = ""
        var endDate = ""
        if let range = firstMatch(in: card, pattern: rangePattern, groups: 2) {
            startDate = range.0
            endDate = range.1
        }

        let stateRaw = firstMatch(in: card, pattern: statePattern) ?? ""
        let state = mapState(stateRaw)

        // `([^<]*)` 連同前後空白一起抓，再 trim——語意等同原本的 `\s*([^<]+?)\s*`，
        // 但沒有量詞重疊。全空白的欄位 trim 後為空字串，視同「沒有這個欄位」回傳 nil。
        let remainingText = trimmedMatch(in: card, pattern: remainingPattern)
        let uploadedAt = trimmedMatch(in: card, pattern: uploadedAtPattern)
        let reviewedAt = trimmedMatch(in: card, pattern: reviewedAtPattern)

        let id = firstMatch(in: card, pattern: idPattern) ?? ""

        return TaskPeriod(
            id: id,
            index: index,
            startDate: startDate,
            endDate: endDate,
            state: state,
            remainingText: remainingText,
            uploadedAt: uploadedAt,
            reviewedAt: reviewedAt
        )
    }

    private static func mapState(_ raw: String) -> TaskState {
        switch raw {
        case "NOT_STARTED": return .notStarted
        // 官網對應狀態：可上傳/尚未上傳的當期 state 是 NOT_UPLOADED（徽章「尚未上傳」）。
        case "OPEN", "NOT_UPLOADED": return .open
        // 官網對應狀態：待審核的 class 是 UNDER_REVIEW。PENDING_REVIEW 一併容錯。
        case "UNDER_REVIEW", "PENDING_REVIEW": return .pendingReview
        case "REDEEMABLE": return .redeemable
        case "REDEEMED": return .redeemed
        default: return .unknown
        }
    }

    /// 取第一個 capture group、去掉前後空白；trim 後為空字串時回傳 nil。
    private static func trimmedMatch(in text: String, pattern: String) -> String? {
        guard let raw = firstMatch(in: text, pattern: pattern) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 取第一個 capture group 的字串（找不到回傳 nil）。
    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[group])
    }

    /// 取前兩個 capture group 的字串組。
    private static func firstMatch(in text: String, pattern: String, groups: Int) -> (String, String)? {
        guard groups == 2,
              let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 2,
              let g1 = Range(match.range(at: 1), in: text),
              let g2 = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return (String(text[g1]), String(text[g2]))
    }
}
