import SwiftUI
import UIKit
import SportsRewardsKit

/// 檢視加碼券（design/Wallet.dc.html 券卡樣式 + design/Redeem.dc.html 的 OTP 輸入）：
/// 每次進入畫面都要重新走一次簡訊 OTP 驗證才會顯示券碼——依合規要求「須本人帳號即時畫面
/// 抵用、不得截圖」，本畫面（與底層的 VoucherServicing）完全不快取券碼，
/// 一律從 `.needsOtp` 開始，`dismiss` 後再進來就要重新驗證一次。
struct VoucherView: View {
    let taskID: String

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VoucherViewModel()
    @FocusState private var isOtpFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的加碼券")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("關閉") { dismiss() }
            }
        }
        .task {
            viewModel.configure(voucher: environment.voucher, taskID: taskID)
        }
        .onDisappear {
            // 離開畫面就丟棄倒數計時器；下次進來是全新的 VoucherView + 全新的
            // VoucherViewModel，狀態機一律從 .needsOtp 重來，不會殘留上次的券碼。
            viewModel.stopCountdown()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.stage {
        case .needsOtp:
            needsOtpView
        case .enterCode:
            enterCodeView
        case .showing(let voucher):
            voucherContentView(voucher)
        }
    }

    // MARK: - Stage 1: needsOtp

    private var needsOtpView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("為避免加碼券被截圖轉傳，每次檢視都需要重新完成手機簡訊驗證，驗證通過後才會顯示券碼。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)

            if let message = viewModel.needsOtpErrorMessage {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.danger)
            }

            Button {
                Task { await viewModel.sendOtp() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSendingOtp {
                        ProgressView().tint(.white)
                    }
                    Text("發送簡訊驗證碼")
                }
            }
            .buttonStyle(.huihanPrimary)
            .disabled(viewModel.isSendingOtp)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Stage 2: enterCode

    private var enterCodeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("簡訊驗證出示券碼")
                    .font(Theme.displayFont(17, weight: .bold))
                Text("驗證碼已發送至您登記的手機門號")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.muted)
            }

            OtpCodeField(code: $viewModel.otp, isFocused: $isOtpFieldFocused)
                .task { isOtpFieldFocused = true }

            if let message = viewModel.enterCodeErrorMessage {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.danger)
            }

            HStack {
                Button {
                    Task { await viewModel.resendOtp() }
                } label: {
                    Text(viewModel.resendCountdown > 0 ? "重新發送 (\(viewModel.resendCountdown)s)" : "重新發送")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(viewModel.resendCountdown > 0 ? Theme.Colors.dim : Theme.Colors.primary)
                }
                .disabled(viewModel.resendCountdown > 0 || viewModel.isSendingOtp)

                Spacer()
            }

            Button {
                isOtpFieldFocused = false
                Task { await viewModel.verify() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isVerifying || viewModel.isLoadingVoucher {
                        ProgressView().tint(.white)
                    }
                    Text("檢視券碼")
                }
            }
            // 券夾列表的卡片按鈕同樣叫「檢視券碼」，加上 id 讓截圖用 UI 測試能明確指到這一顆。
            .accessibilityIdentifier("voucherRevealButton")
            .buttonStyle(.huihanPrimary)
            .disabled(viewModel.otp.count != 6 || viewModel.isVerifying || viewModel.isLoadingVoucher)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Stage 3: showing

    private func voucherContentView(_ voucher: Voucher) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(voucher.itemName)
                    .font(Theme.displayFont(17, weight: .bold))
                Text("兌換通路：\(voucher.vendorName)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Colors.muted)
                if !voucher.expiry.isEmpty {
                    Text("兌換期限：\(voucher.expiry)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.primaryGradient)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .foregroundStyle(.white)

            if voucher.figures.count > 1 {
                Text("這是兩段式加碼券，請店員分別掃描下方每一段條碼，缺一不可。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.warnText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.warnBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            ForEach(Array(voucher.figures.enumerated()), id: \.offset) { _, figure in
                VoucherFigureView(figure: figure)
            }

            if !voucher.notices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("注意事項")
                        .font(.system(size: 13, weight: .bold))
                    ForEach(Array(voucher.notices.enumerated()), id: \.offset) { index, notice in
                        Text("\(index + 1). \(notice)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.Colors.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("離開此頁後，如需再次查看券碼，請重新完成簡訊驗證。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.Colors.dim)
        }
    }
}

/// 單一段券碼：caption + 條碼圖（CoreImage 依 data-format 分流產生）+ 號碼文字 fallback。
/// 條碼產不出來時（未知 format 或濾鏡失敗）只顯示錯誤提示文字，號碼文字仍照樣顯示，
/// 對齊官網 `.voucher-figure__fallback` 的設計——掃不過還能手動輸入。
private struct VoucherFigureView: View {
    let figure: VoucherFigure

    private var isQrCode: Bool { figure.format.uppercased() == "QR_CODE" }

    var body: some View {
        VStack(spacing: 10) {
            if !figure.caption.isEmpty {
                Text(figure.caption)
                    .font(Theme.displayFont(14, weight: .bold))
                    .foregroundStyle(Theme.Colors.text)
            }

            if let image = BarcodeGenerator.barcodeImage(value: figure.value, format: figure.format) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: isQrCode ? 170 : 90)
                    .padding(isQrCode ? 12 : 8)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.Colors.line2, lineWidth: 1)
                    )
            } else {
                Text("條碼無法顯示，請店員手動輸入下方號碼。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 20)
            }

            Text(figure.value)
                .font(Theme.displayFont(16, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.text)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.line2, lineWidth: 1)
        )
    }
}

// `OtpCodeField` / `OtpDigitBox` 共用元件已抽到 `OtpCodeField.swift`。

// MARK: - ViewModel

@MainActor
final class VoucherViewModel: ObservableObject {
    enum Stage: Equatable {
        case needsOtp
        case enterCode
        case showing(Voucher)
    }

    /// 一律從 `.needsOtp` 開始：合規要求每次進入都要重新走一次 OTP，不可以快取上次的券碼畫面。
    @Published private(set) var stage: Stage = .needsOtp
    @Published var otp = ""
    @Published var isSendingOtp = false
    @Published var isVerifying = false
    @Published var isLoadingVoucher = false
    @Published var needsOtpErrorMessage: String?
    @Published var enterCodeErrorMessage: String?
    @Published private(set) var resendCountdown = 0

    private var voucher: VoucherServicing?
    private var taskID = ""
    private var countdownTask: Task<Void, Never>?
    private let resendCooldownSeconds = 60

    func configure(voucher: VoucherServicing, taskID: String) {
        guard self.voucher == nil else { return }
        self.voucher = voucher
        self.taskID = taskID
    }

    func sendOtp() async {
        guard let voucher, !isSendingOtp else { return }
        isSendingOtp = true
        needsOtpErrorMessage = nil
        defer { isSendingOtp = false }
        do {
            try await voucher.sendOtp(taskID: taskID)
            otp = ""
            enterCodeErrorMessage = nil
            stage = .enterCode
            startCountdown()
        } catch {
            needsOtpErrorMessage = "驗證碼發送失敗，請確認網路連線後重試"
        }
    }

    func resendOtp() async {
        guard resendCountdown == 0 else { return }
        await sendOtp()
    }

    func verify() async {
        guard let voucher, otp.count == 6, !isVerifying else { return }
        isVerifying = true
        enterCodeErrorMessage = nil
        defer { isVerifying = false }
        do {
            let result = try await voucher.verifyOtp(taskID: taskID, otp: otp)
            switch result {
            case .success:
                await loadVoucher()
            case .wrongCode(let remaining):
                otp = ""
                if let remaining, remaining <= 0 {
                    enterCodeErrorMessage = "驗證碼錯誤次數已用罄，請重新發送驗證碼"
                } else if let remaining {
                    enterCodeErrorMessage = "驗證碼錯誤，還可以再試 \(remaining) 次"
                } else {
                    enterCodeErrorMessage = "驗證碼錯誤，請再試一次"
                }
            case .failed(let message):
                otp = ""
                enterCodeErrorMessage = message
            }
        } catch {
            enterCodeErrorMessage = "驗證失敗，請確認網路連線後重試"
        }
    }

    private func loadVoucher() async {
        guard let voucher else { return }
        isLoadingVoucher = true
        defer { isLoadingVoucher = false }
        do {
            let fetched = try await voucher.fetchVoucher(taskID: taskID)
            stopCountdown()
            stage = .showing(fetched)
        } catch {
            enterCodeErrorMessage = "驗證成功，但券碼載入失敗，請重新整理"
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        resendCountdown = resendCooldownSeconds
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.resendCountdown > 0 else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.resendCountdown = max(0, self.resendCountdown - 1)
            }
        }
    }

    func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }
}
