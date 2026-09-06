import Foundation

/// 解析 `/member/redeem/{uuid}` 頁面的 HTML，取出各商家可兌換品項。純函式、無副作用、無網路呼叫。
///
/// 每個品項是一列 `<li class="item-row">`，列內有兩個東西：
/// - `<a class="… item-row__intro" href="/registrant/intro/vendor-{id}.html">兌換品項</a>`
/// - `<form action="/registrant/member/redeem/{uuid}" method="post" class="item-row__form"
///   data-vendor-name="全家便利商店" data-item-name="50+3元加碼券">`，
///   內含 hidden input `vendorId`、`item` 與 `_csrf`（見 `Fixtures/redeem.html`）。
///
/// 2026-08-27 起一家商店可以有多個品項，因此以「品項列」而非「商家」為單位解析。
///
/// **為什麼切「列」而不是切「表單」**（這裡改過一次，理由留著）：介紹頁連結在官網的 DOM 上是
/// `<form>` 的**前一個兄弟節點**（按鈕排在「兌換」左側）。原本從 `<form>` 開始切塊的做法
/// 看不到它，只好把邊界往外推到 `<li class="item-row">`。找不到任何 `item-row` 時會退回
/// 舊的切表單邏輯——那樣仍解析得到品項，只是沒有介紹頁連結。
public enum RedeemParser {
    // ReDoS 防線：`[^>]*` 在「大量未閉合 `<form `／`<input `」的惡意頁面上是
    // O(n²)（實測 48 KB → 1.9 秒）。屬性內不可能有裸 `<`，改用 `[^<>]{0,2000}` 後
    // 掃描會在下一個 `<` 停住，成本與整頁長度脫鉤。
    private static let formOpenTagPattern = #"<form\b[^<>]{0,2000}>"#
    private static let itemRowFormClassPattern = #"class\s{0,8}=\s{0,8}["']item-row__form["']"#
    private static let vendorNameAttrPattern = #"data-vendor-name\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#
    private static let itemNameAttrPattern = #"data-item-name\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#
    /// 「兌換品項」連結。官網的 class 是 `btn btn--primary btn--small item-row__intro`，
    /// 且屬性跨行，所以用 `[^<>]` 跨過中間的空白與其他屬性。
    private static let introAnchorPattern =
        #"<a\b[^<>]{0,2000}\bclass\s{0,8}=\s{0,8}["'][^"']{0,200}item-row__intro[^"']{0,200}["'][^<>]{0,2000}>"#
    private static let hrefAttrPattern = #"\bhref\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#

    /// 官方站的 context path。`href` 是站根絕對路徑（`/registrant/intro/…`），
    /// 而 `HTTPClienting.getHTML` 收的是 base-relative path，所以要把它剝掉。
    private static let contextPathPrefix = "/registrant"

    /// 介紹頁 path 的白名單樣式。見 `introPath(in:)` 說明為什麼是白名單。
    private static let allowedIntroPathPattern = #"^/intro/[A-Za-z0-9._-]{1,64}\.html$"#

    /// 解析整頁 HTML，回傳依出現順序排列的兌換品項清單。
    /// - Throws: `AppError.parsing` 當頁面內完全找不到任何 `item-row__form` 表單時。
    public static func parse(html: String) throws -> [RedeemOption] {
        let rows = splitRowBlocks(html)
        let blocks = rows.isEmpty ? splitFormBlocks(html) : rows
        guard !blocks.isEmpty else {
            throw AppError.parsing("no item-row__form found in redeem HTML")
        }
        return blocks.compactMap(parseBlock)
    }

    /// 把整份 HTML 依 `<li class="item-row"` 切成一列一列。切法與 `TaskParser.splitCards` 相同：
    /// 每一塊從標記開始，到下一個標記／`</ul>`／文件尾為止。
    ///
    /// 只保留**真的含有 `item-row__form`** 的塊，這樣 `parse` 才能用「切得到列嗎」
    /// 決定要不要退回舊路徑，而不會被一列不含表單的 `item-row` 誤導。
    private static func splitRowBlocks(_ html: String) -> [String] {
        let marker = "<li class=\"item-row\""
        var blocks: [String] = []
        var searchStart = html.startIndex

        while let markerRange = html.range(of: marker, range: searchStart..<html.endIndex) {
            let blockStart = markerRange.lowerBound
            let nextSearchStart = markerRange.upperBound
            let blockEnd: String.Index
            if let nextMarker = html.range(of: marker, range: nextSearchStart..<html.endIndex) {
                blockEnd = nextMarker.lowerBound
            } else if let closeUL = html.range(of: "</ul>", range: nextSearchStart..<html.endIndex) {
                blockEnd = closeUL.lowerBound
            } else {
                blockEnd = html.endIndex
            }
            let block = String(html[blockStart..<blockEnd])
            if block.range(of: itemRowFormClassPattern, options: [.regularExpression, .caseInsensitive]) != nil {
                blocks.append(block)
            }
            searchStart = nextSearchStart
        }
        return blocks
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

    /// 解析單一片段（一列 `item-row`，或退回模式下的單支表單）。
    /// 任一必要欄位抓不到就回傳 nil（略過該筆，不整頁失敗）。
    private static func parseBlock(_ block: String) -> RedeemOption? {
        guard
            let vendorName = firstGroup(in: block, pattern: vendorNameAttrPattern),
            let itemName = firstGroup(in: block, pattern: itemNameAttrPattern),
            let vendorId = hiddenInputValue(in: block, name: "vendorId"),
            let itemId = hiddenInputValue(in: block, name: "item")
        else {
            return nil
        }
        return RedeemOption(
            vendorId: vendorId,
            vendorName: HTMLEntities.decode(vendorName),
            itemName: HTMLEntities.decode(itemName),
            itemId: itemId,
            introPath: introPath(in: block)
        )
    }

    /// 取出該列「兌換品項」連結的 base-relative path。
    ///
    /// **這個 href 是不受信任輸入**（官方站改版、被入侵、被 MITM 都可能塞進別的東西），
    /// 而它的用途是「拿去餵給 HTTP client 發請求」，所以這裡採白名單而非黑名單：
    /// 剝掉 context path 之後必須完全長得像 `/intro/<檔名>.html` 才收，其餘一律回 nil
    /// （畫面上就是不顯示這顆按鈕）。絕對網址、`..`、query 通通擋在外面。
    private static func introPath(in block: String) -> String? {
        guard let anchorTag = firstMatch(in: block, pattern: introAnchorPattern),
              let rawHref = firstGroup(in: anchorTag, pattern: hrefAttrPattern) else {
            return nil
        }
        var path = HTMLEntities.decode(rawHref).trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix(contextPathPrefix + "/") {
            path = String(path.dropFirst(contextPathPrefix.count))
        }
        guard path.range(of: allowedIntroPathPattern, options: .regularExpression) != nil,
              !path.contains("..") else {
            return nil
        }
        return path
    }

    /// 取整個比對到的字串（不是 capture group）。
    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matched = Range(match.range, in: text) else {
            return nil
        }
        return String(text[matched])
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
