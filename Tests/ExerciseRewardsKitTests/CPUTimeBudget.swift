import Foundation
import XCTest

/// 計時測試的共用量測工具：量的是 **CPU 時間**，而且連跑幾輪取最短的一次。
///
/// **為什麼不用 wall clock。** ReDoS 的症狀是「燒 CPU 燒到回不來」，但 `Date()` 量到的是
/// 牆上時間——裡面包含這個 process 被作業系統排開、完全沒在跑的那一段。實測（本機 M 系列、
/// debug build、`swift test` 跑滿整包 221 條）：整包 **8.43 秒牆上時間裡只有 0.98 user +
/// 0.50 sys 的 CPU**，也就是八成以上的時間根本沒在執行。同一條
/// `testParsersSurviveFullSizeAdversarialBody`、parser 一行都沒改：
/// 單獨跑 0.52 秒、用 `xctest` 直接跑整包 0.51–0.89 秒、透過 `swift test` 跑整包卻會變成
/// 1.29／1.37／2.34／8.11 秒。用牆上時間當門檻，等於把「機器當下有多忙」寫進斷言裡——
/// 那正是這組測試在多 agent／CI 環境下偽陽性的來源。
///
/// `CLOCK_THREAD_CPUTIME_ID` 只累計「這條執行緒真的站在 CPU 上」的時間，被排開的不計。
/// ReDoS 回歸一定會反映在這個數字上（回溯就是在燒 CPU），旁邊有人在編譯不會。
///
/// **為什麼還要取多輪最小值。** CPU 時間仍會被核心頻率影響：同一份工作被排到 Apple Silicon
/// 的效率核上，CPU 時間會膨脹到 3–4 倍。連跑幾輪取最短的一次等於取「沒被干擾時的成本」——
/// 干擾只會讓數字變大，不會讓它變小，所以最小值是這裡唯一穩定的估計量。
///
/// 只有本目標的效能／ReDoS 回歸測試會用到它；功能測試不該有任何時間斷言。
enum CPUClock {

    /// 目前這條執行緒累計用掉的 CPU 時間（秒）。
    /// 本專案只跑在 Apple 平台（見 Package.swift 的 platforms），直接用 Darwin 的 np API。
    static func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
    }

    /// 量一次 `body` 的 CPU 成本。
    static func measure(_ body: () -> Void) -> TimeInterval {
        let start = now()
        body()
        return now() - start
    }

    /// 連跑 `rounds` 輪，回傳「最短一輪的 CPU 成本」與最後一輪的回傳值。
    static func bestOf<T>(_ rounds: Int, _ body: () -> T) -> (cpu: TimeInterval, value: T) {
        precondition(rounds >= 1)
        var best = TimeInterval.infinity
        var value: T!
        for _ in 0..<rounds {
            let start = now()
            value = body()
            best = min(best, now() - start)
        }
        return (best, value)
    }
}

extension XCTestCase {

    /// 斷言 `body` 的 CPU 成本在預算內；回傳最後一輪的結果，方便同一支測試接著驗行為。
    ///
    /// - Parameters:
    ///   - budget: CPU 秒數上限。訂法見各呼叫端——都必須寫出實測值與餘裕的理由。
    ///   - rounds: 取最小值的輪數。輕量輸入用預設 3；吃滿 2 MB 的那幾條傳 2，
    ///             免得為了抗噪把整包測試的時間翻倍。
    @discardableResult
    func assertCPUBudget<T>(
        _ budget: TimeInterval,
        rounds: Int = 3,
        _ label: String,
        hint: String = "",
        file: StaticString = #filePath, line: UInt = #line,
        _ body: () -> T
    ) -> T {
        let (cpu, value) = CPUClock.bestOf(rounds, body)
        XCTAssertLessThan(
            cpu, budget,
            "\(label)：\(rounds) 輪取最短仍要 \(cpu) 秒 CPU，超過 \(budget) 秒的預算。\(hint)",
            file: file, line: line
        )
        return value
    }
}
