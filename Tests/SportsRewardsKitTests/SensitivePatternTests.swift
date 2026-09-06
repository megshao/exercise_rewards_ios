import XCTest
@testable import SportsRewardsKit

/// 驗證 `Redact.sensitiveKinds(in:)` / `containsSensitive` / `scrub`：
/// 這是遙測出口的最後一道防線，漏判 = 個資外流，誤判 = 合法事件被靜靜丟掉。
final class SensitivePatternTests: XCTestCase {
    private typealias Kind = Redact.SensitiveKind

    // MARK: - 共用斷言

    private func assertHits(
        _ text: String, _ kind: Kind,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let kinds = Redact.sensitiveKinds(in: text)
        XCTAssertTrue(kinds.contains(kind), "「\(text)」應命中 \(kind)，實際：\(kinds)", file: file, line: line)
        XCTAssertTrue(Redact.containsSensitive(text), "「\(text)」containsSensitive 應為 true", file: file, line: line)
    }

    private func assertClean(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let kinds = Redact.sensitiveKinds(in: text)
        XCTAssertTrue(kinds.isEmpty, "「\(text)」不該命中任何樣式，實際：\(kinds)", file: file, line: line)
        XCTAssertFalse(Redact.containsSensitive(text), "「\(text)」containsSensitive 應為 false", file: file, line: line)
        XCTAssertEqual(Redact.scrub(text), text, "「\(text)」scrub 後應原封不動", file: file, line: line)
    }

    /// App 裡真實會送進遙測的合法字串。任何一個被誤判都代表事件被靜靜丟掉。
    private static let legitimateStrings: [String] = [
        // 畫面名（ScreenName 封閉列舉）
        "home", "tasks", "health", "wallet", "profile", "redeem", "voucher", "upload", "onboarding",
        // 版本號
        "v1.0.0", "1.0.0", "12.18.0", "1.0.0 (42)",
        // 期數與狀態
        "period_3", "period_14", "NOT_STARTED", "NOT_UPLOADED", "UNDER_REVIEW", "REDEEMABLE", "REDEEMED",
        // UI 上真的存在的日期區間 / 倒數文字
        "10/06 ~ 10/12", "剩 2 天 7 小時可上傳", "12/30 ~ 01/05",
        // 錯誤分類
        "invalid_credentials", "not_registered", "blocked_egress", "parsing", "network", "timeout",
        // 數字型參數的字串化
        "8000", "14", "121", "0", "-1", "100", "999999999",
        // 識別字串
        "com.megshao.sportsrewards", "app_launched", "screen_view", "non_fatal_error",
        "health_auth_granted", "onboarding_completed", "telemetry_preference_changed",
        "true", "false", "iOS 18.0.1", "iPhone15,2",
    ]

    // MARK: - A. 必須命中：身分證號

    func testTaiwanIDStandard() {
        assertHits("A123456789", .taiwanID)
    }

    func testTaiwanIDLowercaseLetter() {
        assertHits("a123456789", .taiwanID)
    }

    func testTaiwanIDLooseFormatsStillHit() {
        // 刻意比合法身分證更寬：檢查碼錯的、新式居留證、示範模式哨兵值都要擋
        assertHits("Z999999999", .taiwanID)
        assertHits("A800000014", .taiwanID)
        assertHits("A000000000", .taiwanID)
    }

    func testTaiwanIDEmbeddedInEnglishText() {
        assertHits("login failed for A123456789", .taiwanID)
    }

    func testTaiwanIDEmbeddedInChineseText() {
        assertHits("身分證字號A123456789查無資料", .taiwanID)
        assertHits("id=A123456789&pwd=", .taiwanID)
    }

    func testTaiwanIDDoesNotAlsoCountAsLongDigits() {
        // 9 碼數字不足 10 碼，只該命中 taiwanID
        XCTAssertEqual(Redact.sensitiveKinds(in: "A123456789"), [.taiwanID])
    }

    // MARK: - A. 必須命中：手機

    func testPhoneStandard() {
        assertHits("0912345678", .phone)
        assertHits("0987654321", .phone)
    }

    func testPhoneWithDashes() {
        assertHits("0912-345-678", .phone)
        assertHits("0912-345678", .phone)
    }

    func testPhoneWithSpaces() {
        // 台灣常見的空白分隔寫法，一樣不可漏
        assertHits("0912 345 678", .phone)
        assertHits("+886 912 345 678", .phone)
    }

    func testPhoneInternationalFormat() {
        assertHits("+886912345678", .phone)
        assertHits("+886-912-345-678", .phone)
        assertHits("886912345678", .phone)
    }

    func testPhoneEmbeddedInText() {
        assertHits("sms sent to 0912345678 failed", .phone)
        assertHits("手機 0912345678 已被註冊", .phone)
        assertHits("phone=0912345678,retry=3", .phone)
    }

    func testPhoneAlsoHitsLongDigitSequence() {
        // 10 碼純數字同時符合兩個樣式；兩個都回報有助於除錯
        XCTAssertEqual(Redact.sensitiveKinds(in: "0912345678"), [.phone, .longDigitSequence])
    }

    // MARK: - A. 必須命中：Email

    func testEmailStandard() {
        assertHits("ming@mail.com", .email)
    }

    func testEmailCaseVariants() {
        assertHits("Ming@Mail.COM", .email)
        assertHits("MING.CHEN@EXAMPLE.ORG", .email)
    }

    func testEmailWithPlusTagAndSubdomain() {
        assertHits("ming.chen+tag@mail.example.co", .email)
        assertHits("a_b-c%d@sub.domain.tw", .email)
    }

    func testEmailEmbeddedInText() {
        assertHits("account ming@mail.com already exists", .email)
        assertHits("帳號ming@mail.com已存在", .email)
    }

    // MARK: - A. 必須命中：生日

    func testBirthDateISO() {
        assertHits("1990-01-01", .birthDate)
        assertHits("2005-12-31", .birthDate)
    }

    func testBirthDateSlashVariants() {
        assertHits("1990/01/01", .birthDate)
        assertHits("1990/1/1", .birthDate)
        assertHits("1990/1/31", .birthDate)
    }

    func testBirthDateDotSeparator() {
        assertHits("1990.01.01", .birthDate)
    }

    func testBirthDateCenturyBoundaries() {
        assertHits("1899-12-31", .birthDate)
        assertHits("2024-01-01", .birthDate)
    }

    func testBirthDateEmbeddedInText() {
        assertHits("birthday 1990-01-01 mismatch", .birthDate)
        assertHits("生日1990/1/1不符", .birthDate)
    }

    // MARK: - A. 必須命中：UUID

    func testUUIDLowercase() {
        assertHits("550e8400-e29b-41d4-a716-446655440000", .uuid)
    }

    func testUUIDUppercaseAndMixed() {
        assertHits("550E8400-E29B-41D4-A716-446655440000", .uuid)
        assertHits("550e8400-E29B-41d4-A716-446655440000", .uuid)
    }

    func testUUIDFromFoundation() {
        assertHits(UUID().uuidString, .uuid)
    }

    func testUUIDEmbeddedInText() {
        assertHits("device 550e8400-e29b-41d4-a716-446655440000 registered", .uuid)
        assertHits("券 550e8400-e29b-41d4-a716-446655440000 已核銷", .uuid)
    }

    // MARK: - A. 必須命中：長數字串

    func testLongDigitSequenceExactlyTen() {
        assertHits("1234567890", .longDigitSequence)
    }

    func testLongDigitSequenceLonger() {
        assertHits("12345678901234", .longDigitSequence)
        assertHits("000012345678", .longDigitSequence)     // 健保卡號樣式
        assertHits("1725580800000", .longDigitSequence)    // 毫秒 timestamp
    }

    func testLongDigitSequenceEmbeddedInText() {
        assertHits("voucher 1234567890123 redeemed", .longDigitSequence)
        assertHits("券碼1234567890已使用", .longDigitSequence)
    }

    func testPhoneGluedToMoreDigitsFallsBackToLongDigits() {
        // 手機樣式因為後面還有數字而不命中，但長數字串必須接住
        let kinds = Redact.sensitiveKinds(in: "09123456789012")
        XCTAssertTrue(kinds.contains(.longDigitSequence))
        XCTAssertFalse(kinds.isEmpty)
    }

    // MARK: - A. 多個敏感值同時出現

    func testMultipleKindsInOneString() {
        let text = "A123456789 0912345678 ming@mail.com 1990-01-01"
        let kinds = Redact.sensitiveKinds(in: text)
        XCTAssertTrue(kinds.isSuperset(of: [.taiwanID, .phone, .email, .birthDate]))
    }

    func testAllKindsInOneString() {
        let text = "id A123456789 tel 0912-345-678 mail ming@mail.com dob 1990/1/1 "
            + "dev 550e8400-e29b-41d4-a716-446655440000 card 000012345678"
        // `.overlong` 是「超過上限、沒掃」的短路結果，定義上不會與實際命中的樣式共存，
        // 所以這裡比對的是「所有可被掃描出來的種類」。
        let scannable = Set(Kind.allCases).subtracting([.overlong])
        XCTAssertEqual(Redact.sensitiveKinds(in: text), scannable)
    }

    func testSameKindTwiceStillReportsOnce() {
        XCTAssertEqual(Redact.sensitiveKinds(in: "0912345678 / 0987654321"), [.phone, .longDigitSequence])
    }

    // MARK: - B. 不可誤判

    func testLegitimateStringsAreNotFlagged() {
        for text in Self.legitimateStrings { assertClean(text) }
    }

    func testScreenNamesAreNotFlagged() {
        for name in ["home", "tasks", "health", "wallet", "profile", "redeem", "voucher", "upload", "onboarding"] {
            assertClean(name)
        }
    }

    func testVersionStringsAreNotFlagged() {
        assertClean("v1.0.0")
        assertClean("1.0.0")
        assertClean("12.18.0")
    }

    func testPeriodAndStatusValuesAreNotFlagged() {
        for value in ["period_3", "NOT_STARTED", "NOT_UPLOADED", "UNDER_REVIEW", "REDEEMABLE", "REDEEMED"] {
            assertClean(value)
        }
    }

    func testUIDateRangeTextIsNotFlagged() {
        // 沒有年份的區間文字不是生日
        assertClean("10/06 ~ 10/12")
        assertClean("剩 2 天 7 小時可上傳")
    }

    func testErrorCategoriesAreNotFlagged() {
        for value in ["invalid_credentials", "not_registered", "blocked_egress", "parsing"] {
            assertClean(value)
        }
    }

    func testStringifiedNumbersAreNotFlagged() {
        assertClean("8000")
        assertClean("14")
        assertClean("121")
    }

    func testBundleIdAndEventNamesAreNotFlagged() {
        assertClean("com.megshao.sportsrewards")
        assertClean("app_launched")
        assertClean("screen_view")
    }

    func testNineDigitsIsBelowLongDigitThreshold() {
        // 釘住門檻：9 碼不算長數字串（否則 8 碼步數/百分比等字串化參數都會中）
        assertClean("123456789")
    }

    func testRealisticCompositeParametersAreNotFlagged() {
        assertClean("period_3 REDEEMABLE 121")
        assertClean("screen=home version=1.0.0 build=42")
        assertClean("upload failed: blocked_egress (attempt 2/3)")
    }

    func testEmptyStringIsNotFlagged() {
        XCTAssertEqual(Redact.sensitiveKinds(in: ""), [])
        XCTAssertFalse(Redact.containsSensitive(""))
    }

    // MARK: - C. scrub 行為

    func testScrubEmptyStringReturnsEmpty() {
        XCTAssertEqual(Redact.scrub(""), "")
    }

    func testScrubReplacesWholePhoneWithMarker() {
        XCTAssertEqual(Redact.scrub("0912345678"), "[已遮蔽:phone]")
    }

    func testScrubIsIrreversibleKeepsNoHeadOrTail() {
        // 與 Redact.phone/idNo 不同：遙測用的 scrub 不可保留任何頭尾字元
        let phone = Redact.scrub("0912345678")
        XCTAssertFalse(phone.hasPrefix("0912"))
        XCTAssertFalse(phone.hasSuffix("678"))
        XCTAssertNil(phone.rangeOfCharacter(from: .decimalDigits), "scrub 後不該殘留任何數字：\(phone)")

        let id = Redact.scrub("A123456789")
        XCTAssertFalse(id.contains("A12"))
        XCTAssertFalse(id.contains("89"))
        XCTAssertNil(id.rangeOfCharacter(from: .decimalDigits))

        let email = Redact.scrub("ming@mail.com")
        XCTAssertFalse(email.contains("ming"))
        XCTAssertFalse(email.contains("mail.com"))
        XCTAssertFalse(email.contains("@"))

        let dob = Redact.scrub("1990-01-01")
        XCTAssertFalse(dob.contains("1990"))
        XCTAssertNil(dob.rangeOfCharacter(from: .decimalDigits))

        let uuid = Redact.scrub("550e8400-e29b-41d4-a716-446655440000")
        XCTAssertFalse(uuid.contains("550e8400"))
        XCTAssertFalse(uuid.contains("446655440000"))
    }

    func testScrubOutputIsItselfClean() {
        let samples = [
            "A123456789", "0912-345-678", "+886912345678", "ming@mail.com", "1990/1/1",
            "550e8400-e29b-41d4-a716-446655440000", "12345678901234",
            "login failed for A123456789 at 1990-01-01 via 0912345678",
        ]
        for sample in samples {
            let out = Redact.scrub(sample)
            XCTAssertFalse(Redact.containsSensitive(out), "scrub 後仍命中：\(out)")
        }
    }

    func testScrubPreservesSurroundingContext() {
        XCTAssertEqual(
            Redact.scrub("login failed for A123456789 (attempt 3)"),
            "login failed for [已遮蔽:taiwanID] (attempt 3)"
        )
    }

    func testScrubPreservesChineseContext() {
        XCTAssertEqual(
            Redact.scrub("使用者 A123456789 於 1990/01/01 登入失敗"),
            "使用者 [已遮蔽:taiwanID] 於 [已遮蔽:birthDate] 登入失敗"
        )
    }

    func testScrubHandlesEmoji() {
        XCTAssertEqual(Redact.scrub("🎉 0912345678 🎉 完成"), "🎉 [已遮蔽:phone] 🎉 完成")
        XCTAssertEqual(Redact.scrub("👨‍👩‍👧 ming@mail.com"), "👨‍👩‍👧 [已遮蔽:email]")
    }

    func testScrubReplacesEveryOccurrence() {
        let out = Redact.scrub("0912345678 和 0987654321 都失敗")
        XCTAssertEqual(out, "[已遮蔽:phone] 和 [已遮蔽:phone] 都失敗")
        XCTAssertEqual(out.components(separatedBy: "[已遮蔽:phone]").count - 1, 2)
    }

    func testScrubMultipleKindsInOneString() {
        let out = Redact.scrub("id=A123456789 tel=0912345678 mail=ming@mail.com dob=1990-01-01")
        XCTAssertEqual(
            out,
            "id=[已遮蔽:taiwanID] tel=[已遮蔽:phone] mail=[已遮蔽:email] dob=[已遮蔽:birthDate]"
        )
    }

    func testScrubLeavesLegitimateStringsUntouched() {
        for text in Self.legitimateStrings {
            XCTAssertEqual(Redact.scrub(text), text)
        }
    }

    /// 超長輸入必須「很快回來」而不是「算得出正確答案」。
    ///
    /// 這一條原本會無限期卡住：`.email` 樣式的 `[A-Za-z0-9._%+\-]+@` 遇到一長串
    /// 不含 `@` 的字元時會吃下整段再逐字元回溯（ReDoS）。修法是兩層——樣式改成
    /// 有界量詞，以及在掃描前先擋掉超過 `maxScanLength` 的輸入。
    ///
    /// 量的是 CPU 時間不是牆上時間：修好之後實測 0.17 秒，1.0 秒是 6 倍餘裕；
    /// 但牆上時間會把「整包測試同時在跑別的東西」算進來，實測可以灌大到十幾倍而誤判。
    /// 理由與數字見 `CPUTimeBudget.swift`。
    func testScrubVeryLongStringReturnsPromptly() {
        let padding = String(repeating: "x", count: 200_000)
        let text = padding + " 0912345678 " + padding

        let out = assertCPUBudget(1.0, rounds: 2, "Redact.scrub 超長輸入") { Redact.scrub(text) }

        // 只保留掃描過的前段，其餘截斷——沒掃過的內容不能留在輸出裡。
        XCTAssertTrue(out.hasSuffix("…[已截斷:超過 \(Redact.maxScanLength) 字元]"))
        XCTAssertLessThan(out.count, Redact.maxScanLength + 64)
    }

    /// 超長輸入在守門用途上一律當成「有敏感資料」——漏判是外洩，誤判只是丟事件。
    func testOverlongInputIsTreatedAsSensitive() {
        let text = String(repeating: "x", count: Redact.maxScanLength + 1)
        XCTAssertEqual(Redact.sensitiveKinds(in: text), [.overlong])
        XCTAssertTrue(Redact.containsSensitive(text))
    }

    /// 剛好在上限內的字串仍然要正常掃描，不可被誤判成 overlong。
    func testAtScanLimitStillScannedNormally() {
        let filler = String(repeating: "x", count: Redact.maxScanLength - 10)
        XCTAssertEqual(Redact.sensitiveKinds(in: filler), [])
        let withPhone = String(repeating: "x", count: Redact.maxScanLength - 11) + "0912345678"
        XCTAssertEqual(withPhone.count, Redact.maxScanLength - 1)
        // 10 碼手機同時命中 phone 與 longDigitSequence，兩者都是刻意的寬鬆樣式。
        XCTAssertEqual(Redact.sensitiveKinds(in: withPhone), [.phone, .longDigitSequence])
    }

    func testScrubLongStringWithManySensitiveValues() {
        // 控制在掃描上限內，驗證「一段合理長度的訊息裡每一筆都被遮到」。
        let line = "A123456789 0912345678 ming@mail.com 1990-01-01\n"
        // 遮蔽標記比被遮的原文長，所以輸出會膨脹。重複次數要讓**輸出**也留在上限內，
        // 否則下面對輸出做 containsSensitive 會得到 .overlong 而不是「乾淨」。
        let repeats = 50
        let text = String(repeating: line, count: repeats)
        XCTAssertLessThanOrEqual(text.count, Redact.maxScanLength)

        let out = Redact.scrub(text)
        XCTAssertLessThanOrEqual(out.count, Redact.maxScanLength, "輸出膨脹後仍須在上限內")
        XCTAssertFalse(Redact.containsSensitive(out))
        XCTAssertEqual(out.components(separatedBy: "[已遮蔽:taiwanID]").count - 1, repeats)
    }

    func testScrubMarkerNamesMatchKindRawValue() {
        for kind in Kind.allCases {
            XCTAssertFalse(kind.rawValue.isEmpty)
        }
        XCTAssertEqual(Redact.scrub("A123456789"), "[已遮蔽:\(Kind.taiwanID.rawValue)]")
    }

    // MARK: - D. 既有遮罩函式回歸

    func testExistingMaskFunctionsUnchanged() {
        XCTAssertEqual(Redact.idNo("A123456789"), "A12●●●●●89")
        XCTAssertEqual(Redact.phone("0912345678"), "0912●●●678")
        XCTAssertEqual(Redact.email("ming@mail.com"), "m●●g@mail.com")
        XCTAssertEqual(Redact.fully("abc"), "●●●")
        XCTAssertEqual(Redact.middle("ABCDEFG", keepHead: 2, keepTail: 2), "AB●●●FG")
    }

    func testMaskAndScrubServeDifferentPurposes() {
        // UI 遮罩保留頭尾（可辨識），遙測 scrub 完全不可還原
        XCTAssertTrue(Redact.phone("0912345678").hasPrefix("0912"))
        XCTAssertFalse(Redact.scrub("0912345678").hasPrefix("0912"))
        // 遮罩後的字串（含 ●）也不該被偵測器誤判
        XCTAssertFalse(Redact.containsSensitive(Redact.idNo("A123456789")))
        XCTAssertFalse(Redact.containsSensitive(Redact.phone("0912345678")))
    }
}
