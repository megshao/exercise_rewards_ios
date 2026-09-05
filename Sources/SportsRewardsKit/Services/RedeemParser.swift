import Foundation

/// 解析 `/member/redeem/{uuid}` 頁面的 HTML，取出各商家可兌換品項。純函式、無副作用、無網路呼叫。
///
/// 每個品項是自己獨立的一支表單：
/// `<form action="/registrant/member/redeem/{uuid}" method="post" class="item-row__form"
///   data-vendor-name="全家便利商店" data-item-name="50+3元加碼券">`，
/// 內含 hidden input `vendorId`、`item` 與 `_csrf`（見 `Fixtures/redeem.html`）。
/// 2026-08-27 起一家商店可以有多個品項，因此以「表單」而非「商家」為單位解析。
public enum RedeemParser {
    // ReDoS 防線（H1）：`[^>]*` 在「大量未閉合 `<form `／`<input `」的惡意頁面上是
    // O(n²)（實測 48 KB → 1.9 秒）。屬性內不可能有裸 `<`，改用 `[^<>]{0,2000}` 後
    // 掃描會在下一個 `<` 停住，成本與整頁長度脫鉤。
    private static let formOpenTagPattern = #"<form\b[^<>]{0,2000}>"#
    private static let itemRowFormClassPattern = #"class\s{0,8}=\s{0,8}["']item-row__form["']"#
    private static let vendorNameAttrPattern = #"data-vendor-name\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#
    private static let itemNameAttrPattern = #"data-item-name\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#

    /// 解析整頁 HTML，回傳依表單出現順序排列的兌換品項清單。
    /// - Throws: `AppError.parsing` 當頁面內完全找不到任何 `item-row__form` 表單時。
    public static func parse(html: String) throws -> [RedeemOption] {
        let blocks = splitFormBlocks(html)
        guard !blocks.isEmpty else {
            throw AppError.parsing("no item-row__form found in redeem HTML")
        }
        return blocks.compactMap(parseBlock)
    }

    /// 把整份 HTML 切成一支支 `<form class="item-row__form" ...> ... </form>` 片段
    /// （片段包含開頭的 `<form>` 標籤本身，方便一併從中取出 data-* 屬性）。
    private static func splitFormBlocks(_ html: String) -> [String] {
        guard let tagRegex = try? NSRegularExpression(
            pattern: formOpenTagPattern,
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
            guard tag.range(of: itemRowFormClassPattern, options: [.regularExpression, .caseInsensitive]) != nil else {
                continue
            }
            let blockStart = tagRange.upperBound
            let blockEnd = html.range(of: "</form>", range: blockStart..<html.endIndex)?.lowerBound ?? html.endIndex
            blocks.append(tag + String(html[blockStart..<blockEnd]))
        }
        return blocks
    }

    /// 解析單支表單片段。任一必要欄位抓不到就回傳 nil（略過該筆，不整頁失敗）。
    private static func parseBlock(_ block: String) -> RedeemOption? {
        guard
            let vendorName = firstGroup(in: block, pattern: vendorNameAttrPattern),
            let itemName = firstGroup(in: block, pattern: itemNameAttrPattern),
            let vendorId = hiddenInputValue(in: block, name: "vendorId"),
            let itemId = hiddenInputValue(in: block, name: "item")
        else {
            return nil
        }
        return RedeemOption(vendorId: vendorId, vendorName: vendorName, itemName: itemName, itemId: itemId)
    }

    /// 從片段中找出 `<input ... name="X" ... value="Y">` 的 Y（不論屬性順序）。
    private static func hiddenInputValue(in block: String, name: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let inputPattern = #"<input\b[^<>]{0,2000}\bname\s{0,8}=\s{0,8}["']"# + escapedName + #"["'][^<>]{0,2000}>"#
        guard let tagRegex = try? NSRegularExpression(pattern: inputPattern, options: [.caseInsensitive]) else {
            return nil
        }
        let fullRange = NSRange(block.startIndex..<block.endIndex, in: block)
        guard
            let tagMatch = tagRegex.firstMatch(in: block, options: [], range: fullRange),
            let tagRange = Range(tagMatch.range, in: block)
        else {
            return nil
        }
        let tag = String(block[tagRange])
        return firstGroup(in: tag, pattern: #"\bvalue\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#)
    }

    /// 取第一個 capture group 的字串（找不到回傳 nil）。
    private static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[group])
    }
}
