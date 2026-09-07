import SwiftUI
import ExerciseRewardsKit

/// 我的券夾：列出已兌換（可使用）的加碼券與任務完成待兌換的期別。
/// - 已兌換 → 點「檢視券碼」開 VoucherView（每次都要 OTP 驗證後才顯示條碼）。
/// - 已兌換且使用者標記過「已使用」→ 移到最下方的「已使用」區，**不再顯示「檢視券碼」**。
///   官網沒有這個狀態，只能靠使用者自己標記（見 `VoucherUsage`）。
/// - 待兌換 → 點「去兌換」開 RedeemView（兌換的二次確認在 RedeemView 內）。
struct WalletView: View {
    @Environment(\.appEnvironment) private var environment
    /// 「已使用」標記的共用真相來源（見 `VoucherUsageStore`）。
    @EnvironmentObject private var voucherUsage: VoucherUsageStore
    @StateObject private var viewModel = WalletViewModel()
    @State private var voucherPeriod: TaskPeriod?
    @State private var redeemPeriod: TaskPeriod?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("已取得的加碼券，最多可獲得 14 張")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.muted)

                if viewModel.isLoading && viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let error = viewModel.errorMessage,
                          viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    emptyOrError(icon: "exclamationmark.triangle.fill", text: error, showRetry: true)
                } else if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                    emptyOrError(icon: "ticket",
                                 text: "目前沒有加碼券。\n完成任務並兌換後，加碼券會出現在這裡。",
                                 showRetry: false)
                } else {
                    if !viewModel.redeemable.isEmpty {
                        sectionTitle("可兌換")
                        ForEach(viewModel.redeemable, id: \.index) { period in
                            redeemableCard(period)
                        }
                    }
                    let unused = viewModel.redeemed.filter { !voucherUsage.isUsed($0) }
                    let used = viewModel.redeemed.filter { voucherUsage.isUsed($0) }
                    if !unused.isEmpty {
                        sectionTitle("可使用的加碼券")
                        ForEach(unused, id: \.index) { period in
                            voucherCard(period)
                        }
                    }
                    if !used.isEmpty {
                        sectionTitle("已使用")
                        ForEach(used, id: \.index) { period in
                            usedVoucherCard(period)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.Colors.background)
        .navigationTitle("我的券夾")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .onAppear { Telemetry.screenAppeared(.wallet) }
        .task {
            viewModel.configure(tasks: environment.tasks)
            if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                await viewModel.refresh()
            }
        }
        // 不需要 onDismiss 重讀標記：`voucherUsage` 是共用的 `@Published`。
        .sheet(item: $voucherPeriod) { period in
            NavigationStack { VoucherView(taskID: period.id, source: .wallet, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                .environmentObject(voucherUsage)
        }
        .sheet(item: $redeemPeriod) { period in
            NavigationStack { RedeemView(taskID: period.id, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                // RedeemView 兌換成功後會再開 VoucherView，那一頁要 voucherUsage。
                .environmentObject(voucherUsage)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.displayFont(16, weight: .bold))
            .padding(.top, 4)
    }

    /// 已兌換的券卡：可檢視券碼（走 OTP）。
    private func voucherCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "ticket.fill").foregroundStyle(Theme.Colors.primary)
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(15, weight: .bold))
                }
                Spacer()
                StatusBadge(text: "已兌換",
                            foreground: Theme.Colors.dim,
                            background: Color(hex: 0xEEF0F3))
            }
            Text("\(period.startDate) ~ \(period.endDate)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
            // 官網卡片上的「兌換內容：通路／品項」。官網原文，只顯示、不進遙測。
            if let summary = period.voucherSummary {
                Text(summary)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                voucherPeriod = period
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                    Text("檢視券碼")
                }
            }
            .buttonStyle(.huihanPrimary)

            Button {
                toggleUsed(period)
            } label: {
                Text("標記為已使用")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.muted)
            }
            .accessibilityIdentifier("walletMarkUsed")
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 已標記為使用完畢的券：整張轉灰、**不提供「檢視券碼」**，只留「還原」。
    /// 標記是本機備忘，所以卡片上要講清楚它不影響官網。
    private func usedVoucherCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Colors.dim)
                    Text("第 \(period.index) 期加碼券")
                        .font(Theme.displayFont(15, weight: .bold))
                        .foregroundStyle(Theme.Colors.muted)
                }
                Spacer()
                StatusBadge(text: "已使用",
                            foreground: Theme.Colors.dim,
                            background: Color(hex: 0xEEF0F3))
            }
            if let summary = period.voucherSummary {
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("你在 App 內標記為已使用（本機紀錄顯示，使用與否以條碼能否使用為主）。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.Colors.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                toggleUsed(period)
            } label: {
                Text("還原成未使用")
            }
            .accessibilityIdentifier("walletRestoreUsed")
            .buttonStyle(.huihanSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: 0xFAFBFC))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(Theme.Colors.line, lineWidth: 1)
        )
    }

    /// 任務完成待兌換：去兌換。
    private func redeemableCard(_ period: TaskPeriod) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("第 \(period.index) 期")
                    .font(Theme.displayFont(15, weight: .bold))
                Spacer()
                StatusBadge(text: "可兌換",
                            foreground: .white,
                            background: Theme.Colors.success)
            }
            Text("任務完成 · 尚未兌換")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
            Button {
                // 兌換本身在 RedeemView 有「確認兌換」二次確認，這裡不再多一道驗證。
                redeemPeriod = period
            } label: {
                HStack {
                    Image(systemName: "gift.fill")
                    Text("去兌換")
                }
            }
            .buttonStyle(.huihanPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 切換「已使用」標記。寫進共用 store，三個分頁會一起重畫。
    private func toggleUsed(_ period: TaskPeriod) {
        let used = voucherUsage.toggle(id: period.id)
        // E29：只送方向，不帶期別 UUID／期數／兌換內容。
        Telemetry.logEvent(.voucherMarkUsed(used: used))
    }

    private func emptyOrError(icon: String, text: String, showRetry: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(Theme.Colors.dim)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .multilineTextAlignment(.center)
            if showRetry {
                Button { Task { await viewModel.refresh() } } label: { Text("重新載入") }
                    .buttonStyle(.huihanSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

@MainActor
final class WalletViewModel: ObservableObject {
    @Published var redeemed: [TaskPeriod] = []
    @Published var redeemable: [TaskPeriod] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var tasks: TasksServicing?

    func configure(tasks: TasksServicing) {
        guard self.tasks == nil else { return }
        self.tasks = tasks
    }

    func refresh() async {
        guard let tasks else { return }
        let hadCache = !redeemed.isEmpty || !redeemable.isEmpty
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let startedAt = DispatchTime.now()
        do {
            let periods = try await tasks.fetchTasks()
            redeemed = periods.filter { $0.state == .redeemed }
            redeemable = periods.filter { $0.state == .redeemable }
            TasksTelemetry.reportSuccess(source: .wallet, periods: periods,
                                         highlighted: HomeViewModel.highlightedPeriod(in: periods),
                                         hadCache: hadCache, startedAt: startedAt)
        } catch {
            TasksTelemetry.reportFailure(error, source: .wallet, hadCache: hadCache,
                                         startedAt: startedAt, sessionProbable: true)
            errorMessage = "無法載入券夾，請先回首頁登入，或稍後重試。"
        }
    }
}
