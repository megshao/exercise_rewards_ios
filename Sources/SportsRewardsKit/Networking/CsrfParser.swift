import Foundation

/// 從 Thymeleaf 渲染的 HTML 表單中擷取隱藏欄位 `_csrf` 的 value。
public enum CsrfParser {
    // 先抓出整個 <input ... name="_csrf" ...> 標籤，再從標籤內找 value 屬性，
    // 這樣不論 name/value 屬性順序為何都能正確擷取。
    private static let inputTagPattern = #"<input\b[^>]*\bname\s*=\s*["']_csrf["'][^>]*>"#
    private static let valueAttrPattern = #"\bvalue\s*=\s*["']([^"']*)["']"#

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
