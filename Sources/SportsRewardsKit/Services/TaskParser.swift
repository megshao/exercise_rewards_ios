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

    /// 解析單張卡片片段。所有欄位都容錯：抓不到就給合理預設值，不丟例外。
    private static func parseCard(_ card: String, fallbackIndex: Int) -> TaskPeriod {
        let index = firstMatch(in: card, pattern: #"第\s*(\d+)\s*期"#).flatMap { Int($0) } ?? fallbackIndex

        var startDate = ""
        var endDate = ""
        if let range = firstMatch(in: card, pattern: #"period-range">\s*([0-9/]+)\s*~\s*([0-9/]+)"#, groups: 2) {
            startDate = range.0
            endDate = range.1
        }

        let stateRaw = firstMatch(in: card, pattern: #"period-state--([A-Z_]+)"#) ?? ""
        let state = mapState(stateRaw)

        let remainingText = firstMatch(in: card, pattern: #"period-remaining">\s*([^<]+?)\s*<"#)

        let uploadedAt = firstMatch(in: card, pattern: #"上傳時間：\s*([^<]+?)\s*<"#)
        let reviewedAt = firstMatch(in: card, pattern: #"審核時間：\s*([^<]+?)\s*<"#)

        let id = firstMatch(in: card, pattern: #"/member/(?:redeem|screenshot)/([0-9a-fA-F-]+)"#) ?? ""

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
        // 實測（測試帳號）：可上傳/尚未上傳的當期真實 state 是 NOT_UPLOADED（徽章「尚未上傳」）。
        case "OPEN", "NOT_UPLOADED": return .open
        // 實測（上傳後）：待審核的真實 class 是 UNDER_REVIEW。PENDING_REVIEW 一併容錯。
        case "UNDER_REVIEW", "PENDING_REVIEW": return .pendingReview
        case "REDEEMABLE": return .redeemable
        case "REDEEMED": return .redeemed
        default: return .unknown
        }
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
