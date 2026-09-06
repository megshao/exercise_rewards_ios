import SwiftUI
import SportsRewardsKit

/// 兌換好禮：列出可兌換的商家品項，點「兌換」需先二次確認
/// 警語（兌換後不可更換、需簡訊驗證出示券碼）才會真的送出表單。

///
/// 兌換成功（`RedeemResult.submitted == true`）後導向 `VoucherView(taskID:)`——該期已經是
/// state=REDEEMED，要看券碼需再走一次簡訊 OTP 驗證（VoucherView 自己的狀態機負責）。
struct RedeemView: View {
    let taskID: String
    let periodIndex: Int?

    @Environment(\.appEnvironment) private var environment
    /// 這一頁自己不用它，但兌換成功後開的 `VoucherView` 需要——sheet 的內容在這個
    /// codebase 一律顯式注入依賴（見同檔的 `.environment(\.appEnvironment, …)`）。
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    @StateObject private var viewModel = RedeemViewModel()
    @State private var showVoucher = false

    init(taskID: String, periodIndex: Int? = nil) {
        self.taskID = taskID
        self.periodIndex = periodIndex
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                warningBanner
                content
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationTitle(periodIndex.map { "兌換好禮 · 第 \($0) 期" } ?? "兌換好禮")
        .navigationBarTitleDisplayMode(.inline)
        // E1：不帶 taskID。
        .onAppear { Telemetry.screenAppeared(.redeem) }
        .task {
            viewModel.configure(redeem: environment.redeem, taskID: taskID, periodIndex: periodIndex)
            if viewModel.options.isEmpty && viewModel.result == nil {
                await viewModel.load()
            }
        }
        .alert(
            "確認兌換",
            isPresented: Binding(
                get: { viewModel.pendingOption != nil },
                set: { isPresented in
                    // 滑掉 alert 等同取消。
                    if !isPresented { viewModel.cancelPending() }
                }
            ),
            presenting: viewModel.pendingOption
        ) { _ in
            Button("取消", role: .cancel) {
                // E17
                viewModel.cancelPending()
            }
            Button("確認兌換", role: .destructive) {
                Task { await viewModel.confirmRedeem() }
            }
        } message: { option in
            Text("將兌換「\(option.vendorName)．\(option.itemName)」。兌換後不可更換，需簡訊驗證出示券碼。")
        }
        .sheet(isPresented: $showVoucher) {
            NavigationStack {
                VoucherView(taskID: taskID, source: .redeemResult, periodIndex: periodIndex)
            }
            .environment(\.appEnvironment, environment)
            .environmentObject(voucherUsage)
        }
    }

    private var warningBanner: some View {
        Text("選一家合作商家後即完成兌換，每筆運動紀錄只能兌換一次，送出後不可更換。兌換後需簡訊驗證才會產生券碼。")
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.Colors.warnText)
            .padding(12)
            .background(Theme.Colors.warnBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if let result = viewModel.result {
            resultView(result)
        } else if viewModel.isLoading && viewModel.options.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if let errorMessage = viewModel.errorMessage, viewModel.options.isEmpty {
            errorState(errorMessage)
        } else if viewModel.options.isEmpty {
            Text("目前沒有可兌換的商家品項。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(viewModel.options) { option in
                    VendorRow(
                        option: option,
                        isSubmitting: viewModel.isSubmitting,
                        // E16：確認 alert 出現的那一刻。
                        onRedeem: { viewModel.selectOption(option) }
                    )
                }
            }
        }
    }

    private func resultView(_ result: RedeemResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: result.submitted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(result.submitted ? Theme.Colors.success : Theme.Colors.danger)
            Text(result.message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.center)

            if result.submitted {
                Button {
                    showVoucher = true
                } label: {
                    Text("檢視加碼券")
                }
                .buttonStyle(.huihanPrimary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.danger)
                .font(.system(size: 28))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("重新載入")
            }
            .buttonStyle(.huihanSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// 單一商家品項列：logo 色塊、品項名、兌換鈕（對齊設計稿的 `.store`）。
private struct VendorRow: View {
    let option: RedeemOption
    let isSubmitting: Bool
    let onRedeem: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VendorLogo(vendorName: option.vendorName)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.vendorName)
                    .font(Theme.displayFont(15, weight: .bold))
                Text(option.itemName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
            }

            Spacer()

            Button(action: onRedeem) {
                Text("兌換")
                    .font(Theme.displayFont(13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(isSubmitting ? Theme.Colors.dim : Theme.Colors.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(isSubmitting)
        }
        .padding(15)
        .background(Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.line2, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

/// 商家色塊 logo，依商家名稱對應設計稿的品牌色；辨識不出的商家用中性灰底。
private struct VendorLogo: View {
    let vendorName: String

    var body: some View {
        Text(shortLabel)
            .font(Theme.displayFont(13, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var color: Color {
        if vendorName.contains("全家") { return Color(hex: 0x0A8F4E) }
        if vendorName.contains("7-11") || vendorName.localizedCaseInsensitiveContains("7-eleven") {
            return Color(hex: 0xE8501F)
        }
        if vendorName.contains("萊爾富") { return Color(hex: 0xC1121F) }
        if vendorName.contains("全聯") { return Color(hex: 0xE4002B) }
        if vendorName.contains("萬家福") || vendorName.contains("樂家康") { return Theme.Colors.primary }
        return Theme.Colors.dim
    }

    private var shortLabel: String {
        if vendorName.contains("全家") { return "全家" }
        if vendorName.contains("7-11") || vendorName.localizedCaseInsensitiveContains("7-eleven") { return "7-11" }
        if vendorName.contains("萊爾富") { return "萊爾富" }
        if vendorName.contains("全聯") { return "全聯" }
        return String(vendorName.prefix(2))
    }
}

// MARK: - ViewModel

@MainActor
final class RedeemViewModel: ObservableObject {
    @Published var options: [RedeemOption] = []
    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var result: RedeemResult?
    @Published var pendingOption: RedeemOption?

    private var redeem: RedeemServicing?
    private var taskID = ""
    /// 活動週次（1–14）。遙測只送這個，不送 `taskID`。
    private var periodIndex: Int?

    func configure(redeem: RedeemServicing, taskID: String, periodIndex: Int? = nil) {
        guard self.redeem == nil else { return }
        self.redeem = redeem
        self.taskID = taskID
        self.periodIndex = periodIndex
    }

    /// E16：`Vendor` 是由**公開的商家名稱**分類出來的封閉列舉，
    /// **不是** `option.vendorId`／`option.itemId`（那是官網識別碼），
    /// 也不是 `option.itemName`（官網文字）。
    func selectOption(_ option: RedeemOption) {
        pendingOption = option
        Telemetry.logEvent(.redeemSelect(vendor: Vendor(vendorName: option.vendorName)))
    }

    /// E17：使用者在確認 alert 按了取消（或滑掉）。
    func cancelPending() {
        guard let option = pendingOption else { return }
        pendingOption = nil
        Telemetry.logEvent(.redeemCancel(vendor: Vendor(vendorName: option.vendorName)))
    }

    func load() async {
        guard let redeem else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await redeem.options(taskID: taskID)
            options = loaded
            // E15：`option_count` 是官網目錄大小（全體使用者一樣），不是個人資料。
            Telemetry.logEvent(.redeemOptions(outcome: loaded.isEmpty ? .empty : .ok,
                                              reason: nil, optionCount: loaded.count))
        } catch {
            errorMessage = "無法載入兌換清單，請確認網路連線後重新整理"
            let reason = Telemetry.reportFailure(error, endpoint: .redeem)
            Telemetry.logEvent(.redeemOptions(outcome: .error, reason: reason, optionCount: 0))
        }
    }

    func confirmRedeem() async {
        guard let redeem, let option = pendingOption else { return }
        let vendor = Vendor(vendorName: option.vendorName)
        pendingOption = nil
        isSubmitting = true
        defer { isSubmitting = false }
        // E18
        Telemetry.logEvent(.redeemSubmit(vendor: vendor, periodIndex: periodIndex))
        let startedAt = DispatchTime.now()
        do {
            let redeemResult = try await redeem.redeem(taskID: taskID, vendorId: option.vendorId,
                                                       item: option.itemId)
            result = redeemResult
            // E19：`RedeemResult.message` 即使是 App 自己的靜態文案也不送，維持「無字串」原則。
            Telemetry.logEvent(.redeemResult(outcome: redeemResult.submitted ? .submitted : .stayedOnPage,
                                             vendor: vendor,
                                             durationMs: Telemetry.elapsedMs(since: startedAt)))
        } catch {
            result = RedeemResult(submitted: false, message: "兌換失敗，請稍後再試，或改用官網確認任務狀態")
            let reason = Telemetry.reportFailure(error, endpoint: .redeem)
            let outcome: RedeemOutcome
            switch reason {
            case .network: outcome = .network
            case .siteStatus, .redirectLoop, .blockedEgress, .csrfMissing: outcome = .httpError
            default: outcome = .unknown
            }
            Telemetry.logEvent(.redeemResult(outcome: outcome, vendor: vendor,
                                             durationMs: Telemetry.elapsedMs(since: startedAt)))
        }
    }
}
