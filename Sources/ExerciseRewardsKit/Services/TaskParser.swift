import Foundation

/// 解析 `/member/tasks` 頁面的 HTML，取出 14 期任務卡片。純函式、無副作用、無網路呼叫。
///
/// 每一期為一張 `<li class="period-card ...">` 卡片，內含：
/// - `.period-no`：第 N 期
/// - `.period-range`：yyyy/MM/dd ~ yyyy/MM/dd
/// - `.period-state--XXX`：後端算好的互斥狀態（見 `TaskState`）
/// - `.period-remaining`：剩餘時間文字（可能沒有）
/// - `.period-detail` 內的上傳/審核時間（可能沒有）
/// - `.period-voucher` 內的「兌換內容：通路／品項」（只有已兌換的期別有）
/// - 兌換 `/member/redeem/{uuid}`、截圖 `/member/screenshot/{uuid}` 或券碼
///   `/member/voucher/{uuid}` 連結中的期別 UUID（可能沒有）
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

    /// 卡片的開頭標籤：class 屬性裡有 `period-card` 這個 token 的 `<li>`。
    /// **刻意不比對完整字串** `<li class="period-card"`——見 `splitCards` 的說明。
    ///
    /// `\bperiod-card\b` 的邊界行為是有意的：`period-card--current` 會匹配（`-` 不是 word char），
    /// 卡片內的子元素 `period-card__title`／`period-card__meta` 不會（`_` 是 word char）——
    /// 否則一張卡會被自己的子元素切成好幾張。
    private static let periodCardOpenTagPattern =
        #"<li\b[^<>]{0,400}\bclass\s{0,8}=\s{0,8}["'][^"']{0,300}\bperiod-card\b[^"']{0,300}["'][^<>]{0,400}>"#

    /// 一張卡片**該有**的內容：`period-no`／`period-range`／`period-state`。這三個是檔頭列的
    /// 卡片骨架（其餘 remaining／detail／voucher 都標了「可能沒有」）。切出來的塊至少要含其中之一，
    /// 否則只是 class 裡碰巧帶著 `period-card` 字樣的無關 `<li>`（例如圖例、說明列）。
    private static let periodCardContentPattern = #"\bperiod-(?:no|range|state)\b"#

    /// 把整份 HTML 依卡片的 `<li>` 開頭切成一張一張卡片的原始片段。每一塊從標記開始，
    /// 到下一個標記／`</ul>`／文件尾為止。
    ///
    /// **為什麼用正則而不是比對 `<li class="period-card` 這個完整字串**（這裡改過一次，
    /// 跟 `RedeemParser.splitRowBlocks` 是同一種病）：完整字串比對把 class 屬性的**寫法**也當成
    /// 契約的一部分。官網只要調換 class 順序（`class="card period-card"`）、在 `<li>` 上多加一個
    /// 排在 class 前面的屬性、改用單引號、或在 `=` 旁多一個空白，就一張卡都切不到 →
    /// `parse` 丟 `AppError.parsing` → **整個任務頁死掉**，而官網其實一個欄位都沒改。
    /// `RedeemParser` 那邊靜默退回舊路徑、按鈕消失；這邊沒有退路，直接全頁失效，
    /// 所以邊界同樣改成「class 裡有 `period-card` 這個 token」。
    ///
    /// 只保留**真的含有卡片內容**（見 `periodCardContentPattern`）的塊：放寬邊界之後，
    /// 頁面上任何 class 帶 `period-card` 字樣的 `<li>`（`period-card-legend` 之類）都會被切成一塊，
    /// 不過濾就會多出一張全是預設值的假卡片。
    ///
    /// ReDoS 防線同檔案其他樣式：屬性用 `[^<>]`／`[^"']` 且量詞都有上限，
    /// 大量未閉合的 `<li ` 在下一個 `<` 就停住。
    private static func splitCards(_ html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: periodCardOpenTagPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let starts = tagRegex.matches(in: html, range: fullRange).compactMap {
            Range($0.range, in: html)?.lowerBound
        }
        guard !starts.isEmpty else { return [] }

        var cards: [String] = []
        for (offset, cardStart) in starts.enumerated() {
            let cardEnd: String.Index
            if offset + 1 < starts.count {
                cardEnd = starts[offset + 1]
            } else if let closeULRange = html.range(of: "</ul>", range: cardStart..<html.endIndex) {
                cardEnd = closeULRange.lowerBound
            } else {
                cardEnd = html.endIndex
            }
            let card = String(html[cardStart..<cardEnd])
            if card.range(of: periodCardContentPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                cards.append(card)
            }
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
    private static let voucherSummaryPattern = #"兌換內容：([^<]{0,2000})<"#
    // 已兌換的期別在官網卡片上只剩 voucher／screenshot 連結（沒有 redeem 連結了），
    // 所以 UUID 必須也認 `voucher`，否則已兌換那期會抓不到 id。
    private static let idPattern = #"/member/(?:redeem|screenshot|voucher)/([0-9a-fA-F-]{1,64})"#

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
        let voucherSummary = trimmedMatch(in: card, pattern: voucherSummaryPattern)

        let id = firstMatch(in: card, pattern: idPattern) ?? ""

        return TaskPeriod(
            id: id,
            index: index,
            startDate: startDate,
            endDate: endDate,
            state: state,
            remainingText: remainingText,
            uploadedAt: uploadedAt,
            reviewedAt: reviewedAt,
            voucherSummary: voucherSummary.map(HTMLEntities.decode)
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
