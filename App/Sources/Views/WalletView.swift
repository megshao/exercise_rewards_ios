import SwiftUI
import SportsRewardsKit

/// 我的券夾：列出已兌換（可使用）的加碼券與任務完成待兌換的期別。
/// - 已兌換 → 點「檢視券碼」開 VoucherView（每次都要 OTP 驗證後才顯示條碼）。
/// - 待兌換 → 點「去兌換」開 RedeemView（先過 Face ID 敏感動作守門）。
/// 對齊 design/Wallet.dc.html。
struct WalletView: View {
    @Environment(\.appEnvironment) private var environment
    @EnvironmentObject private var sensitiveAuth: SensitiveAuthCoordinator
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
                    if !viewModel.redeemed.isEmpty {
                        sectionTitle("可使用的加碼券")
                        ForEach(viewModel.redeemed, id: \.index) { period in
                            voucherCard(period)
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
        .task {
            viewModel.configure(tasks: environment.tasks)
            if viewModel.redeemed.isEmpty && viewModel.redeemable.isEmpty {
                await viewModel.refresh()
            }
        }
        .sheet(item: $voucherPeriod) { period in
            NavigationStack { VoucherView(taskID: period.id) }
                .environment(\.appEnvironment, environment)
                .environmentObject(sensitiveAuth)
        }
        .sheet(item: $redeemPeriod) { period in
            NavigationStack { RedeemView(taskID: period.id, periodIndex: period.index) }
                .environment(\.appEnvironment, environment)
                .environmentObject(sensitiveAuth)
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
            Button {
                voucherPeriod = period
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                    Text("檢視券碼")
                }
            }
            .buttonStyle(.huihanPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 任務完成待兌換：去兌換（先過 Face ID 守門）。
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
                Task {
                    if await sensitiveAuth.authorize(reason: "驗證身份以兌換加碼券") {
                        redeemPeriod = period
                    }
                }
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let periods = try await tasks.fetchTasks()
            redeemed = periods.filter { $0.state == .redeemed }
            redeemable = periods.filter { $0.state == .redeemable }
        } catch {
            errorMessage = "無法載入券夾，請先回首頁登入，或稍後重試。"
        }
    }
}
