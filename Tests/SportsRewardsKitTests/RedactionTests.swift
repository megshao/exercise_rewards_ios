import XCTest
@testable import SportsRewardsKit

/// 驗證個資遮罩：確保任何進入 log/錯誤訊息前的敏感值都被遮蔽。
final class RedactionTests: XCTestCase {
    func testIdNoKeepsHeadTailMasksMiddle() {
        XCTAssertEqual(Redact.idNo("A123456789"), "A12●●●●●89")
    }

    func testPhoneMasksMiddle() {
        // 09 開頭門號，保留頭 4 尾 3
        XCTAssertEqual(Redact.phone("0912345678"), "0912●●●678")
    }

    func testEmailMasksUserKeepsDomain() {
        XCTAssertEqual(Redact.email("ming@mail.com"), "m●●g@mail.com")
    }

    func testShortStringFullyMasked() {
        // 長度不足以保留頭尾時，整串遮罩，不可洩漏原文
        let out = Redact.middle("AB", keepHead: 3, keepTail: 2)
        XCTAssertFalse(out.contains("A"))
        XCTAssertFalse(out.contains("B"))
        XCTAssertEqual(out, "●●")
    }

    func testFullyNeverEmpty() {
        XCTAssertEqual(Redact.fully(""), "●")
    }
}
