import XCTest
@testable import SportsRewardsKit

/// 驗證 VoucherService：不打真實網路，全部透過 MockHTTPClient（見 AuthServiceTests.swift）。
final class VoucherServiceTests: XCTestCase {
    private let taskID = "9f746d24-213d-43c8-b291-5183cab4c64f"
    private var voucherPath: String { "/member/voucher/\(taskID)" }
    private var resendPath: String { "\(voucherPath)/resend" }
    private var viewPath: String { "\(voucherPath)/view" }

    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Fixtures") else {
            XCTFail("fixture \(name).html not found in bundle")
            return ""
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeVoucherPageHTML(csrf: String) -> String {
        """
        <form class="voucher-otp-resend-form" action="\(voucherPath)/resend" method="post">
        <input name="_csrf" value="\(csrf)"></form>
        <form class="voucher-otp-verify-form" action="\(voucherPath)" method="post">
        <input name="_csrf" value="\(csrf)"><input name="otp"></form>
        """
    }

    // MARK: - sendOtp

    func testSendOtpFetchesCsrfFirstThenPostsToResendPath() async throws {
        let mock = MockHTTPClient()
        mock.htmlByPath[voucherPath] = makeVoucherPageHTML(csrf: "resend-csrf")
        mock.formResultByPath[resendPath] = HTTPFormResult(statusCode: 200, location: nil, body: "")
        let sut = VoucherService(http: mock)

        try await sut.sendOtp(taskID: taskID)

        XCTAssertEqual(mock.getPaths, [voucherPath])
        XCTAssertEqual(mock.postPaths, [resendPath])
        let fields = try XCTUnwrap(mock.postFields[resendPath])
        XCTAssertTrue(fields.contains { $0.0 == "_csrf" && $0.1 == "resend-csrf" })
    }

    func testSendOtpThrowsCsrfNotFoundWhenPageHasNoCsrf() async {
        let mock = MockHTTPClient()
        mock.htmlByPath[voucherPath] = "<html>no csrf here</html>"
        let sut = VoucherService(http: mock)

        do {
            try await sut.sendOtp(taskID: taskID)
            XCTFail("expected throw")
        } catch let error as AppError {
            XCTAssertEqual(error, .csrfNotFound)
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
        XCTAssertTrue(mock.postPaths.isEmpty, "should not POST when csrf missing")
    }

    func testSendOtpThrowsParsingWhenTaskIDEmpty() async {
        let mock = MockHTTPClient()
        let sut = VoucherService(http: mock)

        do {
            try await sut.sendOtp(taskID: "   ")
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .parsing = error else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
        XCTAssertTrue(mock.getPaths.isEmpty, "should not hit network for an empty taskID")
    }

    // MARK: - verifyOtp

    func testVerifyOtpReturnsSuccessOn302ToViewPath() async throws {
        let mock = MockHTTPClient()
        mock.htmlByPath[voucherPath] = makeVoucherPageHTML(csrf: "verify-csrf")
        mock.formResultByPath[voucherPath] = HTTPFormResult(statusCode: 302, location: "\(voucherPath)/view", body: "")
        let sut = VoucherService(http: mock)

        let result = try await sut.verifyOtp(taskID: taskID, otp: "123456")

        XCTAssertEqual(result, .success)
        XCTAssertEqual(mock.getPaths, [voucherPath])
        XCTAssertEqual(mock.postPaths, [voucherPath])
        let fields = try XCTUnwrap(mock.postFields[voucherPath])
        XCTAssertTrue(fields.contains { $0.0 == "_csrf" && $0.1 == "verify-csrf" })
        XCTAssertTrue(fields.contains { $0.0 == "otp" && $0.1 == "123456" })
    }

    func testVerifyOtpReturnsWrongCodeWithRemainingOn200WithErrorFixture() async throws {
        let mock = MockHTTPClient()
        mock.htmlByPath[voucherPath] = makeVoucherPageHTML(csrf: "verify-csrf")
        mock.formResultByPath[voucherPath] = HTTPFormResult(
            statusCode: 200,
            location: nil,
            body: try loadFixture("voucher_verify_error")
        )
        let sut = VoucherService(http: mock)

        let result = try await sut.verifyOtp(taskID: taskID, otp: "000000")

        XCTAssertEqual(result, .wrongCode(remaining: 2))
    }

    func testVerifyOtpReturnsFailedOnUnexpectedStatus() async throws {
        let mock = MockHTTPClient()
        mock.htmlByPath[voucherPath] = makeVoucherPageHTML(csrf: "verify-csrf")
        mock.formResultByPath[voucherPath] = HTTPFormResult(statusCode: 500, location: nil, body: "")
        let sut = VoucherService(http: mock)

        let result = try await sut.verifyOtp(taskID: taskID, otp: "000000")

        guard case .failed = result else {
            return XCTFail("expected .failed, got \(result)")
        }
    }

    func testVerifyOtpThrowsParsingWhenTaskIDEmpty() async {
        let mock = MockHTTPClient()
        let sut = VoucherService(http: mock)

        do {
            _ = try await sut.verifyOtp(taskID: "", otp: "123456")
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .parsing = error else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
    }

    // MARK: - fetchVoucher

    func testFetchVoucherGetsViewPathAndParsesFixture() async throws {
        let mock = MockHTTPClient()
        mock.htmlByPath[viewPath] = try loadFixture("voucher_view")
        let sut = VoucherService(http: mock)

        let voucher = try await sut.fetchVoucher(taskID: taskID)

        XCTAssertEqual(mock.getPaths, [viewPath])
        XCTAssertEqual(voucher.figures.count, 2)
        XCTAssertTrue(voucher.vendorName.contains("萊爾富"))
    }

    func testFetchVoucherThrowsParsingWhenTaskIDEmpty() async {
        let mock = MockHTTPClient()
        let sut = VoucherService(http: mock)

        do {
            _ = try await sut.fetchVoucher(taskID: "  ")
            XCTFail("expected throw")
        } catch let error as AppError {
            guard case .parsing = error else {
                return XCTFail("expected AppError.parsing, got \(error)")
            }
        } catch {
            XCTFail("expected AppError, got \(error)")
        }
        XCTAssertTrue(mock.getPaths.isEmpty, "should not hit network for an empty taskID")
    }
}
