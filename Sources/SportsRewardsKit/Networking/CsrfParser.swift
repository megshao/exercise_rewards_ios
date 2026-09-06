import Foundation

/// 從 Thymeleaf 渲染的 HTML 表單中擷取隱藏欄位 `_csrf` 的 value。
public enum CsrfParser {
    // 先抓出整個 <input ... name="_csrf" ...> 標籤，再從標籤內找 value 屬性，
    // 這樣不論 name/value 屬性順序為何都能正確擷取。
    //
    // ReDoS 防線：`[^>]*` 在「大量未閉合 `<input `」的惡意頁面上是 O(n²)
    // （實測 56 KB → 6.7 秒）。改用 `[^<>]{0,2000}`：屬性內不可能有裸 `<`，
    // 排除它之後掃描會在下一個 `<` 停住，再加上長度上限，成本與整頁長度脫鉤。
    private static let inputTagPattern =
        #"<input\b[^<>]{0,2000}\bname\s{0,8}=\s{0,8}["']_csrf["'][^<>]{0,2000}>"#
    private static let valueAttrPattern = #"\bvalue\s{0,8}=\s{0,8}["']([^"']{0,2000})["']"#

    /// - Throws: `AppError.csrfNotFound` 若找不到 `_csrf` 欄位或其值為空。
    public static func extract(from html: String) throws -> String {
        guard
            let tagRegex = try? NSRegularExpression(pattern: inputTagPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
            let valueRegex = try? NSRegularExpression(pattern: valueAttrPattern, options: [.caseInsensitive])
        else {
            throw AppError.csrfNotFound
        }

        let fullRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard
            let tagMatch = tagRegex.firstMatch(in: html, options: [], range: fullRange),
            let tagRange = Range(tagMatch.range, in: html)
        else {
            throw AppError.csrfNotFound
        }

        let tag = String(html[tagRange])
        let tagFullRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard
            let valueMatch = valueRegex.firstMatch(in: tag, options: [], range: tagFullRange),
            let valueRange = Range(valueMatch.range(at: 1), in: tag)
        else {
            throw AppError.csrfNotFound
        }

        let token = String(tag[valueRange])
        guard !token.isEmpty else {
            throw AppError.csrfNotFound
        }
        return token
    }
}
