import XCTest
@testable import SportsRewardsKit

final class GoalEvaluatorTests: XCTestCase {
    private func summary(steps: Int, meters: Double, mins: Int) -> HealthSummary {
        HealthSummary(date: Date(timeIntervalSince1970: 0), steps: steps,
                      distanceMeters: meters, exerciseMinutes: mins)
    }

    func testStepsThresholdInclusive() {
        XCTAssertTrue(GoalEvaluator.evaluate(summary(steps: 8000, meters: 0, mins: 0)).met.contains(.steps8000))
        XCTAssertFalse(GoalEvaluator.evaluate(summary(steps: 7999, meters: 0, mins: 0)).met.contains(.steps8000))
    }

    func testExerciseMinutes() {
        XCTAssertTrue(GoalEvaluator.evaluate(summary(steps: 0, meters: 0, mins: 30)).met.contains(.walk30min))
    }

    func testDistanceKm() {
        XCTAssertTrue(GoalEvaluator.evaluate(summary(steps: 0, meters: 5000, mins: 0)).met.contains(.run5km))
        XCTAssertFalse(GoalEvaluator.evaluate(summary(steps: 0, meters: 4999, mins: 0)).met.contains(.run5km))
    }

    func testNoneMet() {
        XCTAssertFalse(GoalEvaluator.evaluate(summary(steps: 100, meters: 100, mins: 1)).isMet)
    }

    func testMultipleMet() {
        let e = GoalEvaluator.evaluate(summary(steps: 9688, meters: 6400, mins: 42))
        XCTAssertEqual(Set(e.met), Set([.steps8000, .walk30min, .run5km]))
    }
}
