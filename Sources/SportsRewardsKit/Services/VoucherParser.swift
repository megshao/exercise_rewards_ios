import Foundation

/// 解析檢視加碼券相關頁面的 HTML。純函式、無副作用、無網路呼叫。
///
/// 兩個入口對應官網的兩種頁面：
/// - `parseView(html:)`：正確 OTP 通過後 302 到 `/member/voucher/{uuid}/view` 的券碼頁，
///   內含 `.voucher-banner`/`.voucher-meta`（通路／品項／兌換期限）與一或多個
///   `.voucher-figure`（`data-format`/`data-value`/caption）。
/// - `parseVerifyError(html:)`：OTP 驗證錯誤時原地回傳的同一頁，
///   含 `<p class="notice notice--error">驗證碼錯誤，還可以再試 N 次。</p>`。
///
/// 容錯策略：任何欄位抓不到就給合理預設（空字串／nil／略過該筆），不整頁拋錯——
/// 頁面版型微調時，App 應該退化成「資訊少一點」而不是整個功能掛掉。
public enum VoucherParser {

    // MARK: - parseView

    // MARK: - Patterns
    //
    // ReDoS 防線（H1）：輸入是官方站回傳的 HTML，屬**不受信任輸入**。三條規則：
    // 1. 相鄰量詞的字元集合不得重疊。`\s*([^<]*?)\s*</p>` 是反例（`\s` ⊂ `[^<]`），
    //    實測 800 個空白要 9 秒、1600 個要 81 秒（O(n³)）。正解 `([^<]*)</p>` + trim。
    // 2. 每個量詞都要長度上限，讓單次比對成本不隨整頁長度成長。
    // 3. 標籤屬性掃描用 `[^<>]`——屬性內不會有裸 `<`，排除它可讓「大量未閉合標籤」
    //    的攻擊在下一個 `<` 就停住（原本 `[^>]*` 會一路掃到文件尾，O(n²)）。
    // 另有一道獨立防線：`URLSessionHTTPClient.send` 對 body 設 2 MB 上限。

    private static let itemNameTagPattern =
        #"<strong\b[^<>]{0,2000}\bclass\s{0,8}=\s{0,8}["']voucher-meta__item["'][^<>]{0,2000}>([^<]{0,2000})</strong>"#
    private static let channelBlockPattern =
        #"voucher-meta__channel[\s\S]{0,2000}?<span[^<>]{0,2000}>([^<]{0,2000})</span>"#
    // `([^<]*)` 貪婪一定停在第一個 `<`（零回溯），trim 由 `firstGroup` 統一處理。
    private static let expiryPattern = #"兌換期限[：:]([^<]{0,2000})</p>"#

    private static let figureSectionOpenTagPattern = #"<section\b[^<>]{0,2000}>"#
    private static let figureSectionClassPattern =
        #"class\s{0,8}=\s{0,8}["'][^"'<>]{0,500}\bvoucher-figure\b[^"'<>]{0,500}["']"#
    private static let figureCaptionPattern =
        #"<h2\b[^<>]{0,2000}\bclass\s{0,8}=\s{0,8}["']voucher-figure__caption["'][^<>]{0,2000}>([^<]{0,2000})</h2>"#
    private static let figureFormatPattern = #"data-format\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#
    private static let figureValuePattern = #"data-value\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#

    // 注意事項區塊的長度上限同時也是 `listItemPattern` 的成本上限——
    // `parseNotices` 只在這個已被截短的片段內找 `<li>`，不會掃整頁。
    private static let noticesSectionPattern =
        #"<section\b[^<>]{0,2000}\bclass\s{0,8}=\s{0,8}["']voucher-notices["'][\s\S]{0,8000}?</section>"#
    private static let listItemPattern = #"<li\b[^<>]{0,2000}>([\s\S]{0,2000}?)</li>"#
    private static let tagStripPattern = #"<[^<>]{1,2000}>"#

    /// 解析券碼頁（`/member/voucher/{uuid}/view`）。
    /// - Throws: `AppError.parsing` 只在完全找不到任何 `voucher-figure` 時拋出——
    ///   沒有券碼就不成一張「加碼券」，這種情況才視為解析失敗。
    public static func parseView(html: String) throws -> Voucher {
        let figures = parseFigures(html)
        guard !figures.isEmpty else {
            throw AppError.parsing("no voucher-figure found in voucher view HTML")
        }
        return Voucher(
            vendorName: firstGroup(in: html, pattern: channelBlockPattern) ?? "",
            itemName: firstGroup(in: html, pattern: itemNameTagPattern) ?? "",
            expiry: firstGroup(in: html, pattern: expiryPattern) ?? "",
            figures: figures,
            notices: parseNotices(html)
        )
    }

    private static func parseFigures(_ html: String) -> [VoucherFigure] {
        splitFigureBlocks(html).compactMap { block in
            guard
                let format = firstGroup(in: block, pattern: figureFormatPattern),
                let value = firstGroup(in: block, pattern: figureValuePattern)
            else {
                return nil
            }
            let caption = firstGroup(in: block, pattern: figureCaptionPattern) ?? ""
            return VoucherFigure(format: format, value: value, caption: caption)
        }
    }

    /// 把整份 HTML 切成一支支 `<section class="voucher-figure" ...> ... </section>` 片段
    /// （片段包含開頭的 `<section>` 標籤本身，方便一併抓 data-* / class 屬性）。
    private static func splitFigureBlocks(_ html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: figureSectionOpenTagPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = tagRegex.matches(in: html, range: fullRange)

        var blocks: [String] = []
        for match in matches {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard tag.range(of: figureSectionClassPattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                continue
            }
            let blockStart = tagRange.upperBound
            let blockEnd = html.range(of: "</section>", range: blockStart..<html.endIndex)?.lowerBound ?? html.endIndex
            blocks.append(tag + String(html[blockStart..<blockEnd]))
        }
        return blocks
    }

    private static func parseNotices(_ html: String) -> [String] {
        guard let section = firstMatch(in: html, pattern: noticesSectionPattern) else {
            return []
        }
        guard let regex = try? NSRegularExpression(pattern: listItemPattern, options: [.caseInsensitive]) else {
            return []
        }
        let fullRange = NSRange(section.startIndex..<section.endIndex, in: section)
        let matches = regex.matches(in: section, range: fullRange)
        return matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: section) else { return nil }
            let raw = String(section[range])
            let stripped = raw.replacingOccurrences(of: tagStripPattern, with: "", options: .regularExpression)
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    // MARK: - parseVerifyError

    private static let errorNoticePattern =
        #"<p\b[^<>]{0,2000}\bclass\s{0,8}=\s{0,8}["'][^"'<>]{0,500}\bnotice--error\b[^"'<>]{0,500}["'][^<>]{0,2000}>([^<]{0,2000})</p>"#
    // `(\d+)\s*次` 對 8000 位連續數字要 4.6 秒（O(n²)：`\d+` 每次貪婪到底再逐格回溯）。
    // 剩餘次數是個位數，上限 9 位綽綽有餘，且讓每個起點的成本變成常數。
    private static let remainingCountPattern = #"(\d{1,9})\s{0,8}次"#

    /// 解析 OTP 驗證錯誤時原地回傳的同一頁：`.notice--error` 文字與其中的剩餘次數 N。
    /// 找不到 `.notice--error` 或抓不到數字時給合理預設（`remaining: nil`、通用錯誤訊息）。
    public static func parseVerifyError(html: String) -> (remaining: Int?, message: String) {
        guard let message = firstGroup(in: html, pattern: errorNoticePattern) else {
            return (nil, "驗證碼錯誤")
        }
        let remaining = firstGroup(in: message, pattern: remainingCountPattern).flatMap { Int($0) }
        return (remaining, message)
    }

    // MARK: - regex helpers

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), let matchRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matchRange])
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[group]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
