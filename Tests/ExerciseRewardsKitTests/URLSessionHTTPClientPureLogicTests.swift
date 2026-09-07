import XCTest
@testable import ExerciseRewardsKit

/// 只測 `URLSessionHTTPClient` 抽出來的純函式（不發網路請求）：
/// 網域白名單判斷、redirect Location 正規化。
final class URLSessionHTTPClientPureLogicTests: XCTestCase {

    // MARK: isAllowedHost

    func testIsAllowedHostAcceptsExactRootDomain() {
        XCTAssertTrue(URLSessionHTTPClient.isAllowedHost("500.gov.tw"))
    }

    func testIsAllowedHostAcceptsSubdomain() {
        XCTAssertTrue(URLSessionHTTPClient.isAllowedHost("cdn.500.gov.tw"))
    }

    func testIsAllowedHostIsCaseInsensitive() {
        XCTAssertTrue(URLSessionHTTPClient.isAllowedHost("500.GOV.TW"))
    }

    func testIsAllowedHostRejectsUnrelatedDomain() {
        XCTAssertFalse(URLSessionHTTPClient.isAllowedHost("evil.com"))
    }

    func testIsAllowedHostRejectsSuffixSpoofTrick() {
        // "500.gov.tw" 只是這個惡意網域的前綴，真正的 host 是 evil.com 的子網域
        XCTAssertFalse(URLSessionHTTPClient.isAllowedHost("500.gov.tw.evil.com"))
    }

    // MARK: normalizeLocation

    func testNormalizeLocationDowngradesHttpAndExtractsPath() throws {
        // Arrange
        let location = "http://500.gov.tw/registrant/login"

        // Act
        let path = try URLSessionHTTPClient.normalizeLocation(location)

        // Assert: scheme 被捨棄（一律用 https 重組請求），只留下 base-relative path
        XCTAssertEqual(path, "/login")
    }

    func testNormalizeLocationKeepsHttpsAndQuery() throws {
        // Arrange
        let location = "https://500.gov.tw/registrant/access?_cookie_check=1"

        // Act
        let path = try URLSessionHTTPClient.normalizeLocation(location)

        // Assert
        XCTAssertEqual(path, "/access?_cookie_check=1")
    }

    func testNormalizeLocationHandlesRelativeLocationWithoutHost() throws {
        // Arrange
        let location = "/registrant/member/tasks"

        // Act
        let path = try URLSessionHTTPClient.normalizeLocation(location)

        // Assert
        XCTAssertEqual(path, "/member/tasks")
    }

    func testNormalizeLocationThrowsBlockedEgressForForeignHost() {
        // Arrange
        let location = "http://evil.com/phish"

        // Act & Assert
        XCTAssertThrowsError(try URLSessionHTTPClient.normalizeLocation(location)) { error in
            guard case .blockedEgress = error as? AppError else {
                return XCTFail("expected AppError.blockedEgress, got \(error)")
            }
        }
    }

    // MARK: buildURL(basePath:)

    func testBuildURLComposesBaseAndPath() throws {
        // Arrange & Act
        let url = try URLSessionHTTPClient.buildURL(basePath: "/access")

        // Assert
        XCTAssertEqual(url.absoluteString, "https://500.gov.tw/registrant/access")
    }

    func testBuildURLThrowsWhenPathMissingLeadingSlash() {
        XCTAssertThrowsError(try URLSessionHTTPClient.buildURL(basePath: "access")) { error in
            guard case .parsing = error as? AppError else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        }
    }

    // MARK: encodeForm

    func testEncodeFormEscapesSpacesAndReservedCharacters() {
        // Arrange
        let fields = [("idNo", "A123456789"), ("note", "a b&c")]

        // Act
        let encoded = URLSessionHTTPClient.encodeForm(fields)

        // Assert
        XCTAssertEqual(encoded, "idNo=A123456789&note=a+b%26c")
    }
}
