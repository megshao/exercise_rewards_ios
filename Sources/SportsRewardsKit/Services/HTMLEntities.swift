import Foundation

/// 把 HTML 屬性／文字節點裡的字元參照還原成原字元。
///
/// **為什麼需要**：官網的商品頁把分類名放在屬性裡，例如
/// `data-category="Let&#x27;s Café"`。直接拿屬性值當畫面文字，使用者會看到
/// 「Let&#x27;s Café」這串原始碼。
///
/// **刻意只做這一件事**：這裡不是 HTML 剖析器，也不打算變成一個。只還原
/// 五個具名實體與數值字元參照——那是官方站（Thymeleaf 預設跳脫）唯一會產生的東西。
/// 遇到不認得的 `&...;` 一律**原樣保留**，不猜、不丟例外。
///
/// ReDoS 防線：整支函式不用正則，只做一次線性掃描，成本與輸入長度成正比。
public enum HTMLEntities {
    /// 官方站會產生的五個具名實體。順序無關，查表比對。
    private static let named: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        // `&nbsp;` 出現在少數排版用的空白，還原成一般空白比留著 U+00A0 好處理。
        "nbsp": " ",
    ]

    /// 數值字元參照的位數上限。`&#x1F600;` 是 6 碼，取 8 已經很寬鬆；
    /// 設上限是為了讓「一個 `&#` 後面接超長數字」不會拖著整段掃描。
    private static let maxNumericDigits = 8

    public static func decode(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var output = ""
        output.reserveCapacity(input.count)

        var index = input.startIndex
        while index < input.endIndex {
            let character = input[index]
            guard character == "&" else {
                output.append(character)
                index = input.index(after: index)
                continue
            }

            // 找這個 `&` 後面最近的 `;`，且中間不能超過具名實體的最長長度。
            let afterAmpersand = input.index(after: index)
            let limit = input.index(afterAmpersand, offsetBy: maxNumericDigits + 3, limitedBy: input.endIndex)
                ?? input.endIndex
            guard let semicolon = input[afterAmpersand..<limit].firstIndex(of: ";") else {
                // 不是字元參照（例如一個單獨的 `&`）——原樣保留。
                output.append(character)
                index = afterAmpersand
                continue
            }

            let body = String(input[afterAmpersand..<semicolon])
            if let decoded = decodeBody(body) {
                output.append(decoded)
            } else {
                // 不認得就原樣保留整段（含 `&` 與 `;`），不做任何猜測。
                output.append("&")
                output.append(body)
                output.append(";")
            }
            index = input.index(after: semicolon)
        }
        return output
    }

    /// 解析 `&` 與 `;` 之間那一段。認不得回傳 nil。
    private static func decodeBody(_ body: String) -> Character? {
        if let named = named[body.lowercased()] { return named }

        guard body.hasPrefix("#") else { return nil }
        let digits = String(body.dropFirst())
        let scalarValue: UInt32?
        if digits.hasPrefix("x") || digits.hasPrefix("X") {
            let hex = String(digits.dropFirst())
            guard !hex.isEmpty, hex.count <= maxNumericDigits,
                  hex.allSatisfy(\.isHexDigit) else { return nil }
            scalarValue = UInt32(hex, radix: 16)
        } else {
            guard !digits.isEmpty, digits.count <= maxNumericDigits,
                  digits.allSatisfy(\.isNumber) else { return nil }
            scalarValue = UInt32(digits, radix: 10)
        }
        guard let value = scalarValue, let scalar = Unicode.Scalar(value) else { return nil }
        return Character(scalar)
    }
}
