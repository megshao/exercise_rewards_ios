import XCTest
@testable import SportsRewardsKit

/// 驗證 `HTMLEntities.decode`。這支的用途是把官網屬性值（Thymeleaf 跳脫過）還原成
/// 給人看的文字，因此重點在「認得的要還原」與「不認得的原樣保留、不亂猜」兩件事。
final class HTMLEntitiesTests: XCTestCase {
    func testDecodesNamedEntities() {
        XCTAssertEqual(HTMLEntities.decode("堅果 &amp; 蛋類"), "堅果 & 蛋類")
        XCTAssertEqual(HTMLEntities.decode("&lt;script&gt;"), "<script>")
        XCTAssertEqual(HTMLEntities.decode("&quot;引號&quot;"), "\"引號\"")
        XCTAssertEqual(HTMLEntities.decode("Let&apos;s Café"), "Let's Café")
    }

    func testDecodesNumericReferences() {
        XCTAssertEqual(HTMLEntities.decode("Let&#x27;s Caf&#233;"), "Let's Café")
        XCTAssertEqual(HTMLEntities.decode("&#20013;&#25991;"), "中文")
    }

    func testIsCaseInsensitiveForNamedAndHexEntities() {
        XCTAssertEqual(HTMLEntities.decode("&AMP;"), "&")
        XCTAssertEqual(HTMLEntities.decode("&#X27;"), "'")
    }

    /// 沒有 `&` 的字串要原樣回來（也是最常見的快速路徑）。
    func testLeavesPlainTextUntouched() {
        XCTAssertEqual(HTMLEntities.decode("全家便利商店可兌換商品"), "全家便利商店可兌換商品")
        XCTAssertEqual(HTMLEntities.decode(""), "")
    }

    /// 認不得的一律原樣保留：這裡不是 HTML 剖析器，猜錯比留著原文更糟。
    func testKeepsUnknownOrMalformedSequencesAsIs() {
        XCTAssertEqual(HTMLEntities.decode("A &不是實體; B"), "A &不是實體; B")
        XCTAssertEqual(HTMLEntities.decode("&notarealentity;"), "&notarealentity;")
        XCTAssertEqual(HTMLEntities.decode("100% 純果汁 & 蔬菜"), "100% 純果汁 & 蔬菜")
        XCTAssertEqual(HTMLEntities.decode("&#;"), "&#;")
        XCTAssertEqual(HTMLEntities.decode("&#xZZ;"), "&#xZZ;")
    }

    /// 沒有結尾分號、或分號離得太遠，都不算字元參照。
    func testRequiresNearbySemicolon() {
        XCTAssertEqual(HTMLEntities.decode("&amp"), "&amp")
        XCTAssertEqual(HTMLEntities.decode("&" + String(repeating: "a", count: 40) + ";"),
                       "&" + String(repeating: "a", count: 40) + ";")
    }

    /// 超出 Unicode 範圍的碼位不可以讓解碼器崩潰。
    func testRejectsOutOfRangeScalar() {
        XCTAssertEqual(HTMLEntities.decode("&#xFFFFFF;"), "&#xFFFFFF;")
        XCTAssertEqual(HTMLEntities.decode("&#99999999;"), "&#99999999;")
    }

    /// 只解一輪，不重複解碼——`&amp;#x27;` 的原意就是要顯示 `&#x27;` 這串字。
    func testDoesNotDoubleDecode() {
        XCTAssertEqual(HTMLEntities.decode("&amp;#x27;"), "&#x27;")
    }

    /// 這支會吃到整頁 HTML 大小的輸入，必須是線性成本。
    ///
    /// 量 CPU 時間不是牆上時間——牆上時間量到的是「機器當下多忙」，
    /// 整包測試一起跑時同一份工作可以被灌大十幾倍。理由見 `CPUTimeBudget.swift`。
    func testHandlesLongInputQuickly() {
        let input = String(repeating: "商品名稱 &amp; 說明 &#x27;A&#x27; ", count: 5_000)

        let decoded = assertCPUBudget(2.0, "HTMLEntities.decode 長輸入") { HTMLEntities.decode(input) }

        XCTAssertFalse(decoded.contains("&amp;"))
    }
}
