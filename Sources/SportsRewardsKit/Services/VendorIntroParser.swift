import Foundation

/// 解析廠商可兌換商品頁（`/intro/vendor-{id}.html`）。純函式、無副作用、無網路呼叫。
///
/// 這幾頁是官網的**靜態頁**，不需要登入也拿得到，內容只有商品名稱，沒有任何個資。
///
/// ## 兩種版型（都得吃）
///
/// **A. 逐項列出**（全家 / 7-11 / 萊爾富）：
/// ```html
/// <details class="category-card all-items" data-category="全部品項">
///   <summary class="category-trigger">
///     <span class="category-title">全部品項<span class="item-count">308 項</span></span>
///   </summary>
///   <div class="category-content">
///     <ul><li data-name="ＦＭＣ不知春茶">ＦＭＣ不知春茶</li>…</ul>
///   </div>
/// </details>
/// ```
///
/// **B. 只給類別與舉例**（全聯 / 萬家福・樂家康）：
/// ```html
/// <table>
///   <thead><tr><th>類別名稱</th><th>商品名稱（列舉）</th></tr></thead>
///   <tbody><tr><td>冷藏鮮乳</td><td>光泉低脂鮮乳、林鳳營高品質鮮乳等</td></tr>…</tbody>
/// </table>
/// ```
///
/// 版型 A 有就用 A，沒有才找 B——不是「猜哪一種」，而是「A 的標記存在與否」這個確定的訊號。
///
/// ## ReDoS 防線
///
/// 與 `TaskParser` / `RedeemParser` 同一套規矩（相鄰量詞字元集合不重疊、量詞一律有上限、
/// 標籤屬性用 `[^<>]`）。分類卡的切割用字串搜尋而非正則，因為 `<details>` 可以巢狀，
/// 用 `.*?</details>` 在惡意輸入上會退化。
public enum VendorIntroParser {
    // MARK: - Patterns

    private static let titlePattern = #"<h1\b[^<>]{0,400}>([^<]{0,300})<"#
    private static let heroSubtitlePattern = #"<div class="hero-copy">.{0,2000}?<p\b[^<>]{0,200}>([^<]{0,500})<"#
    private static let categoryAttrPattern = #"data-category\s{0,8}=\s{0,8}["']([^"']{0,300})["']"#
    private static let detailsOpenTagPattern = #"<details\b[^<>]{0,600}>"#
    private static let itemCountPattern = #"item-count["'][^<>]{0,200}>([^<]{0,60})<"#
    private static let itemNamePattern = #"<li\b[^<>]{0,400}\bdata-name\s{0,8}=\s{0,8}["']([^"']{0,500})["']"#
    private static let tableBodyPattern = #"<tbody\b[^<>]{0,200}>"#
    private static let cellPattern = #"<td\b[^<>]{0,200}>([^<]{0,2000})<"#
    private static let noticePattern = #"<aside\b[^<>]{0,200}\bclass\s{0,8}=\s{0,8}["'][^"']{0,120}notice[^"']{0,120}["'][^<>]{0,200}>"#
    private static let paragraphPattern = #"<p\b[^<>]{0,200}>([^<]{0,2000})<"#

    /// 解析整頁 HTML。
    /// - Throws: `AppError.parsing` 當兩種版型的標記都找不到時（代表官網換版型了）。
    public static func parse(html: String) throws -> VendorIntro {
        let categories = parseDetailCategories(html).isEmpty
            ? parseTableCategories(html)
            : parseDetailCategories(html)

        guard !categories.isEmpty else {
            throw AppError.parsing("no category-card or table row found in vendor intro HTML")
        }

        return VendorIntro(
            title: text(in: html, pattern: titlePattern) ?? "可兌換商品",
            subtitle: text(in: html, pattern: heroSubtitlePattern),
            categories: categories,
            notices: parseNotices(html)
        )
    }

    // MARK: - 版型 A：<details> 分類卡

    private static func parseDetailCategories(_ html: String) -> [VendorIntroCategory] {
        splitDetailBlocks(html).compactMap { block in
            guard let rawName = firstGroup(in: block, pattern: categoryAttrPattern) else { return nil }
            let openTag = firstMatch(in: block, pattern: detailsOpenTagPattern) ?? ""
            return VendorIntroCategory(
                name: HTMLEntities.decode(rawName),
                items: allGroups(in: block, pattern: itemNamePattern).map(HTMLEntities.decode),
                examples: nil,
                statedCount: statedCount(in: block),
                // 官網用 `class="category-card all-items"` 標出彙總卡。
                isAllItems: openTag.range(of: "all-items") != nil
            )
        }
    }

    /// 把整份 HTML 依 `<details` 切成一張一張分類卡（到下一個 `<details` 或文件尾）。
    ///
    /// 官網目前不巢狀 `<details>`，用「下一個開頭」當邊界因此等同用 `</details>`；
    /// 但真的巢狀時這個切法只會讓某一卡多含一些內容，不會像正則那樣爆炸。
    private static func splitDetailBlocks(_ html: String) -> [String] {
        let marker = "<details"
        var blocks: [String] = []
        var searchStart = html.startIndex

        while let markerRange = html.range(of: marker, range: searchStart..<html.endIndex) {
            let blockStart = markerRange.lowerBound
            let nextSearchStart = markerRange.upperBound
            let blockEnd = html.range(of: marker, range: nextSearchStart..<html.endIndex)?.lowerBound
                ?? html.endIndex
            blocks.append(String(html[blockStart..<blockEnd]))
            searchStart = nextSearchStart
        }
        return blocks
    }

    /// 從「308 項」取出 308。抓不到或不是數字回傳 nil——**不拿 `items.count` 頂替**，
    /// 官網數字與解析結果不一致時要看得出來。
    private static func statedCount(in block: String) -> Int? {
        guard let raw = firstGroup(in: block, pattern: itemCountPattern) else { return nil }
        let digits = raw.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    // MARK: - 版型 B：類別 / 舉例 表格

    private static func parseTableCategories(_ html: String) -> [VendorIntroCategory] {
        // 只看 <tbody> 之後的內容，避開表頭那一列（`<th>` 本來就不會被 `<td>` 樣式抓到，
        // 這一步是為了在頁面有多張表時仍從資料列開始）。
        guard let tbodyTag = range(of: tableBodyPattern, in: html) else { return [] }
        let body = String(html[tbodyTag.upperBound...])

        var categories: [VendorIntroCategory] = []
        for row in body.components(separatedBy: "<tr") {
            let cells = allGroups(in: row, pattern: cellPattern)
                .map { HTMLEntities.decode($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard cells.count >= 2, !cells[0].isEmpty else { continue }
            categories.append(
                VendorIntroCategory(
                    name: cells[0],
                    items: [],
                    examples: cells[1].isEmpty ? nil : cells[1],
                    statedCount: nil,
                    isAllItems: false
                )
            )
        }
        return categories
    }

    // MARK: - 注意事項

    private static func parseNotices(_ html: String) -> [String] {
        guard let asideTag = range(of: noticePattern, in: html) else { return [] }
        let tail = String(html[asideTag.upperBound...])
        let block = tail.range(of: "</aside>").map { String(tail[..<$0.lowerBound]) } ?? tail
        return allGroups(in: block, pattern: paragraphPattern)
            .map { HTMLEntities.decode($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Regex helpers

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    /// 取第一個 capture group，去頭尾空白；空字串視同沒有。
    private static func text(in html: String, pattern: String) -> String? {
        guard let raw = firstGroup(in: html, pattern: pattern) else { return nil }
        let trimmed = HTMLEntities.decode(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = regex(pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let group = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[group])
    }

    private static func allGroups(in text: String, pattern: String) -> [String] {
        guard let regex = regex(pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1, let group = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[group])
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        range(of: pattern, in: text).map { String(text[$0]) }
    }

    private static func range(of pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = regex(pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return Range(match.range, in: text)
    }
}
