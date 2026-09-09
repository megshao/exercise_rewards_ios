import SwiftUI
import ExerciseRewardsKit

/// 兌換好禮：列出可兌換的商家品項，點「兌換」需先二次確認
/// 警語（兌換後不可更換、需簡訊驗證出示券碼）才會真的送出表單。
///
/// 每一列另有「兌換品項」，開 `VendorIntroView` 看該通路的加碼券能換哪些商品——
/// 對應官網同一列的那顆按鈕（官網是另開瀏覽器視窗，這裡改成 App 內的 sheet，
/// 使用者不會被帶離兌換流程）。
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
    @State private var introOption: RedeemOption?

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
                    // **這裡只能收掉狀態，不能判定「使用者取消了」**：按 alert 任一顆鈕，
                    // SwiftUI 都是先把 isPresented 設成 false，**再**執行那顆鈕的 action。
                    // 先前這裡呼叫 `cancelPending()`，於是「確認兌換」的 action 還沒跑，
                    // `pendingOption` 就已經是 nil——`confirmRedeem()` 的 guard 直接 return，
                    // 整顆確認鈕變成空操作（而且每次確認都被記成一次 `redeem_cancel`）。
                    if !isPresented { viewModel.clearPending() }
                }
            ),
            presenting: viewModel.pendingOption
        ) { option in
            Button("取消", role: .cancel) {
                // E17：iOS 的 alert 關不掉也滑不掉，所以「使用者取消」只有這一條路。
                viewModel.reportCancel(option)
            }
            Button("確認兌換", role: .destructive) {
                // 帶著 `presenting` 捕捉到的 option 走，不回頭讀已被清空的 `pendingOption`。
                Task { await viewModel.confirmRedeem(option) }
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
        // 只有 introPath 不是 nil 的品項才點得出這個 sheet（見 VendorRow）。
        .sheet(item: $introOption) { option in
            NavigationStack {
                VendorIntroView(introPath: option.introPath ?? "", vendorName: option.vendorName)
            }
            .environment(\.appEnvironment, environment)
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
        if viewModel.isSiteHandoff {
            // 5a：兌換頁解析不到品項、或送出兌換時頁面連 `_csrf` 都沒有——都是官網結構對不上。
            // 排在 `result` 前面：送出失敗那條路不產生 `result`，直接交接到官網那一期的兌換頁。
            SiteHandoffState(destination: .redeem(taskID: taskID)) {
                await viewModel.load()
            }
        } else if let result = viewModel.result {
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
                        onRedeem: { viewModel.selectOption(option) },
                        onIntro: { introOption = option }
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

/// 單一商家品項列：logo 色塊、品項名、「兌換品項」與「兌換」兩顆鈕。
///
/// 「兌換品項」只在該商家真的有介紹頁時出現（`option.introPath != nil`）——
/// 這與官網的規則一致：靜態頁存在與否就是唯一的開關，不自己拼網址。
private struct VendorRow: View {
    let option: RedeemOption
    let isSubmitting: Bool
    let onRedeem: () -> Void
    let onIntro: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VendorLogo(vendorName: option.vendorName)

            VStack(alignment: .leading, spacing: 2) {
                Text(option.vendorName)
                    .font(Theme.displayFont(15, weight: .bold))
                Text(option.itemName)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if option.introPath != nil {
                Button(action: onIntro) {
                    Text("兌換品項")
                        .font(Theme.displayFont(13, weight: .bold))
                        .foregroundStyle(Theme.Colors.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Theme.Colors.primary.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(option.vendorName)可兌換商品")
            }

            // padding 與背景一律畫在 label **裡面**（寫法比照上面的「兌換品項」）。
            // 加在 Button 外側的話版面會撐大、色塊也照樣畫得出來，但 Button 的可點區
            // 仍然只有 `Text` 本身——實機量到可點區 26×15.7pt、色塊 58×35.7pt，
            // 有八成是死區，點在藥丸上卻沒反應。
            Button(action: onRedeem) {
                Text("兌換")
                    .font(Theme.displayFont(13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isSubmitting ? Theme.Colors.dim : Theme.Colors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
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
///
/// **名稱比對走 `Vendor(vendorName:)`，這裡不再自己判斷一次**。先前這支與遙測各有一份
/// `contains` 判斷，結果漂掉了：logo 認得萬家福／樂家康，遙測卻把它們算成 `other`。
/// 現在只有一份比對表（見 `Vendor`），要新增商家就只改那裡。
///
/// 認不出來的商家（`.other`）不是壞事——那正是「官網新增合作店家」的正常樣子：
/// 灰底加名稱前兩字，功能完全不受影響。
private struct VendorLogo: View {
    let vendorName: String

    private var vendor: Vendor { Vendor(vendorName: vendorName) }

    var body: some View {
        Text(shortLabel)
            .font(Theme.displayFont(13, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var color: Color {
        switch vendor {
        case .familyMart: return Color(hex: 0x0A8F4E)
        case .sevenEleven: return Color(hex: 0xE8501F)
        case .hilife: return Color(hex: 0xC1121F)
        case .pxmart: return Color(hex: 0xE4002B)
        case .wanjiafu: return Theme.Colors.primary
        case .other: return Theme.Colors.dim
        }
    }

    /// 認得的商家用固定縮寫（設計稿指定）；認不出來的退成名稱前兩字。
    private var shortLabel: String {
        switch vendor {
        case .familyMart: return "全家"
        case .sevenEleven: return "7-11"
        case .hilife: return "萊爾富"
        case .pxmart: return "全聯"
        case .wanjiafu, .other: return String(vendorName.prefix(2))
        }
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
    /// 最近一次載入或送出是否撞上「官網結構對不上」（`SiteHandoff.shouldHandoff(_:)`）。
    /// 為真時整頁改走接手畫面（見 `RedeemView.content`）；`load()` 開頭歸零。
    @Published private(set) var isSiteHandoff = false

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

    /// alert 收起來時歸零狀態，**不送遙測**。
    ///
    /// SwiftUI 會先關 alert 再跑按鈕的 action，所以在這個時間點還不知道使用者按的是哪一顆；
    /// 「取消」的遙測由 `reportCancel(_:)` 負責，確認那條路則走 `confirmRedeem(_:)`。
    func clearPending() {
        pendingOption = nil
    }

    /// E17：使用者在確認 alert 按了取消。
    func reportCancel(_ option: RedeemOption) {
        Telemetry.logEvent(.redeemCancel(vendor: Vendor(vendorName: option.vendorName)))
    }

    func load() async {
        guard let redeem else { return }
        isLoading = true
        errorMessage = nil
        isSiteHandoff = false
        defer { isLoading = false }
        do {
            let loaded = try await redeem.options(taskID: taskID)
            options = loaded
            // E15：`option_count` 是官網目錄大小（全體使用者一樣），不是個人資料。
            Telemetry.logEvent(.redeemOptions(outcome: loaded.isEmpty ? .empty : .ok,
                                              reason: nil, optionCount: loaded.count))
            reportIntroLinkDrift(loaded)
        } catch {
            // 官網結構對不上走接手畫面；其他錯誤（網路、狀態碼）才是「請確認網路連線」。
            if SiteHandoff.shouldHandoff(error) {
                isSiteHandoff = true
            } else {
                errorMessage = "無法載入兌換清單，請確認網路連線後重新整理"
            }
            let reason = Telemetry.reportFailure(error, endpoint: .redeem)
            Telemetry.logEvent(.redeemOptions(outcome: .error, reason: reason, optionCount: 0))
        }
    }

    /// 「解析成功但一個介紹頁連結都沒有」的警報。
    ///
    /// **為什麼需要它**：這是這條路徑上唯一**不會丟出錯誤**的失敗。官網目前每一家都有
    /// 「兌換品項」連結；如果切列邊界對不上官網的 class 寫法，`RedeemParser` 會退回
    /// 切表單的路徑——品項照樣解析成功、兌換照樣可用、`redeem_options` 照樣回報 `ok`，
    /// 只是每一列的 `introPath` 都變成 nil，按鈕靜默消失。沒有這個警報，
    /// 只有使用者回報才會發現。
    ///
    /// 只送一個整數（品項數），不送商家名、品項名或任何路徑——官網文字一律不進遙測。
    /// 官網日後若真的把連結全部撤掉，這裡會開始固定作響；那時要做的是更新這個判斷，
    /// 而不是把它拿掉。
    private func reportIntroLinkDrift(_ loaded: [RedeemOption]) {
        guard !loaded.isEmpty, loaded.allSatisfy({ $0.introPath == nil }) else { return }
        Telemetry.recordNonFatal(.redeemIntroMissing, endpoint: .redeem,
                                 extras: ["options": .int(loaded.count)])
    }

    /// 送出兌換。`option` 由 alert 的 `presenting:` 傳進來——**不要**改回讀 `pendingOption`，
    /// 那個值在這支被呼叫前就已經被 alert 的 isPresented binding 清成 nil 了。
    func confirmRedeem(_ option: RedeemOption) async {
        guard let redeem else { return }
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
            // 送出前要先 GET 兌換頁抓 `_csrf`；頁面改版時這一步會丟 `csrfNotFound`。
            // 那不是「稍後再試」能解決的，直接交接到官網這一期的兌換頁（不產生 `result`）。
            if SiteHandoff.shouldHandoff(error) {
                isSiteHandoff = true
            } else {
                result = RedeemResult(submitted: false, message: "兌換失敗，請稍後再試，或改用官網確認任務狀態")
            }
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
