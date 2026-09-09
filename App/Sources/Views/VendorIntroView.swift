import SwiftUI
import ExerciseRewardsKit

/// 廠商可兌換商品：從兌換頁每一列的「兌換品項」進來，列出該通路的商品分類與品項。
///
/// 官網那幾頁有兩種版型（見 `VendorIntroParser`），這裡照著資料自己有的東西畫：
/// - 有逐項清單（`items`）→ 可展開的分類卡，卡上顯示官網標的「N 項」。
/// - 只有舉例（`examples`）→ 分類名 + 一行舉例文字，**明講「舉例」**，
///   不假裝那是完整清單。
///
/// 搜尋會同時比對分類名與品項名；只有舉例的分類則比對舉例文字。
struct VendorIntroView: View {
    /// 已由 `RedeemParser` 驗證過、限定在 `/intro/*.html` 的 base-relative path。
    let introPath: String
    /// 兌換頁上那一列的商家名，只用來在載入完成前有個像樣的標題。
    let vendorName: String

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VendorIntroViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        .navigationTitle(viewModel.intro?.title ?? vendorName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("關閉") { dismiss() }
            }
        }
        // E1：不帶 introPath，也不帶商家名（官網文字一律不進遙測）。
        .onAppear { Telemetry.screenAppeared(.vendorIntro) }
        .task {
            viewModel.configure(redeem: environment.redeem, introPath: introPath,
                                catalog: environment.vendorCatalog)
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.intro == nil {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
        } else if let errorMessage = viewModel.errorMessage, viewModel.intro == nil {
            errorState(errorMessage)
        } else if let intro = viewModel.intro {
            if let capturedAt = viewModel.backupCapturedAt {
                backupBanner(capturedAt)
            }
            loaded(intro)
        }
    }

    /// 這份清單來自離線備份，不是官網即時頁面——**必須讓使用者看到**。
    ///
    /// 官網的品項頁自己就寫著「實際可兌換品項、供應狀況及門市庫存，依各門市現場公告為準」；
    /// 官網都不保證自己的清單，一份可能過期好幾週的快照更沒有資格裝成即時資料。
    /// 所以這裡把來源與擷取日期講明白，讓使用者自己判斷要不要相信。
    private func backupBanner(_ capturedAt: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Theme.Colors.warnText)
            Text("讀不到官網的品項頁，以下是 \(capturedAt) 擷取的離線備份，可能已經變動。實際可兌換品項以門市現場公告為準。")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.Colors.warnText)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.warnBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func loaded(_ intro: VendorIntro) -> some View {
        if let subtitle = intro.subtitle {
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }

        searchField

        let categories = viewModel.filteredCategories
        if categories.isEmpty {
            Text("找不到符合「\(viewModel.query)」的商品。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            ForEach(categories) { category in
                CategoryCard(
                    category: category,
                    // 搜尋中一律展開：使用者要看的就是命中的那幾項，
                    // 讓他再一張一張點開等於白搜。
                    isExpanded: viewModel.isSearching || viewModel.expanded.contains(category.id),
                    canCollapse: !viewModel.isSearching,
                    highlight: viewModel.trimmedQuery,
                    onToggle: { viewModel.toggle(category.id) }
                )
            }
        }

        if !intro.notices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("兌換注意事項")
                    .font(.system(size: 13, weight: .bold))
                ForEach(Array(intro.notices.enumerated()), id: \.offset) { _, notice in
                    Text(notice)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.Colors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.dim)
            TextField("搜尋商品名稱", text: $viewModel.query)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.dim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜尋")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Theme.Colors.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.Colors.line2, lineWidth: 1))
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

/// 一張分類卡。逐項版可展開／收合；只有舉例的版本沒有東西可展開，直接把舉例攤在卡上。
private struct CategoryCard: View {
    let category: VendorIntroCategory
    let isExpanded: Bool
    let canCollapse: Bool
    let highlight: String
    let onToggle: () -> Void

    private var hasItems: Bool { !category.items.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasItems {
                Button(action: onToggle) { header }
                    .buttonStyle(.plain)
                    .disabled(!canCollapse)
            } else {
                header
            }

            if hasItems && isExpanded {
                Divider().padding(.vertical, 10)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(category.items.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Colors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            if let examples = category.examples {
                Text(examples)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.Colors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 7)
                Text("以上為舉例，實際品項以門市現場為準。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.dim)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(category.isAllItems ? Theme.Colors.card2 : Theme.Colors.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .stroke(category.isAllItems ? Theme.Colors.amber : Theme.Colors.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(category.name)
                .font(Theme.displayFont(14.5, weight: .bold))
                .foregroundStyle(Theme.Colors.text)
                .multilineTextAlignment(.leading)

            if let count = countText {
                Text(count)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.warnText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.warnBackground)
                    .clipShape(Capsule())
            }

            Spacer(minLength: 4)

            if hasItems {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.Colors.primary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
        }
        .contentShape(Rectangle())
    }

    /// 搜尋時顯示的是**篩選後**的筆數，跟官網標的總數不是同一件事，
    /// 因此只在沒有搜尋（`highlight` 為空）時才拿官網的 `statedCount` 來顯示。
    private var countText: String? {
        guard hasItems else { return nil }
        if !highlight.isEmpty { return "\(category.items.count) 項符合" }
        if let stated = category.statedCount { return "\(stated) 項" }
        return "\(category.items.count) 項"
    }
}

// MARK: - ViewModel

@MainActor
final class VendorIntroViewModel: ObservableObject {
    @Published private(set) var intro: VendorIntro?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var query = ""
    /// 使用者手動展開的分類 id。預設全部收合，跟官網一樣。
    @Published private(set) var expanded: Set<String> = []

    private var redeem: RedeemServicing?
    private var catalog: VendorCatalogFetching?
    private var introPath = ""
    /// 這份內容是離線備份、快照日期是哪一天。nil＝來自官網即時頁面。
    /// **有值時畫面必須告知使用者**（見 `VendorCatalogService` 的說明）。
    @Published private(set) var backupCapturedAt: String?

    var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !trimmedQuery.isEmpty }

    /// 依搜尋字串篩選：命中分類名時整個分類留下，否則只留下命中的品項。
    /// 只有舉例的分類則比對舉例文字。
    var filteredCategories: [VendorIntroCategory] {
        guard let categories = intro?.categories else { return [] }
        let needle = trimmedQuery
        guard !needle.isEmpty else { return categories }

        return categories.compactMap { category in
            if category.name.localizedCaseInsensitiveContains(needle) { return category }

            let matchedItems = category.items.filter { $0.localizedCaseInsensitiveContains(needle) }
            if !matchedItems.isEmpty {
                return VendorIntroCategory(name: category.name, items: matchedItems,
                                           examples: category.examples,
                                           statedCount: category.statedCount,
                                           isAllItems: category.isAllItems)
            }
            if let examples = category.examples, examples.localizedCaseInsensitiveContains(needle) {
                return category
            }
            return nil
        }
    }

    func configure(redeem: RedeemServicing, introPath: String,
                   catalog: VendorCatalogFetching? = nil) {
        guard self.redeem == nil else { return }
        self.redeem = redeem
        self.catalog = catalog
        self.introPath = introPath
    }

    func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    /// 版型認不出來時的警報。
    ///
    /// **為什麼要在這裡發**：`VendorIntroParser` 兩種版型都對不上時不再丟例外，
    /// 而是退到純文字給出最小可用結果（讓使用者至少看得到東西）。那個決定的代價是
    /// **失敗不再自動變成例外**，所以「官網換版型了」這件事必須由呼叫端自己回報，
    /// 否則就變成一個沒人知道的降級。
    ///
    /// 只送 `layout` 這個封閉列舉，不送標題、分類名或任何官網文字。
    private func reportLayoutDrift(_ intro: VendorIntro) {
        guard intro.layout == .unrecognised else { return }
        Telemetry.recordNonFatal(.vendorIntroLayout, endpoint: .vendorIntro,
                                 extras: ["layout": .code(intro.layout)])
    }

    func load() async {
        guard let redeem else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await redeem.vendorIntro(path: introPath)
            intro = loaded
            reportLayoutDrift(loaded)
        } catch {
            Telemetry.reportFailure(error, endpoint: .vendorIntro)
            // 官網載不到就退到離線備份。**沒有備份才顯示錯誤**——
            // 這一頁是純資訊，載不到不影響兌換本身，所以只提示、不擋流程。
            if await loadBackup() { return }
            errorMessage = "無法載入可兌換商品清單，請稍後再試。"
        }
    }

    /// 用離線備份接手。成功回 true。
    ///
    /// 失敗一律安靜結束（連錯誤訊息都交回給呼叫端決定）：備份本身也是加值功能，
    /// 它抓不到時該顯示的是原本那句「無法載入」，而不是「備份也失敗了」這種
    /// 對使用者毫無意義的實作細節。
    private func loadBackup() async -> Bool {
        guard let catalog else { return false }
        do {
            let backup = try await catalog.fetch()
            guard let vendor = backup.vendor(introPath: introPath) else { return false }
            intro = vendor.intro
            backupCapturedAt = backup.capturedAt
            return true
        } catch {
            return false
        }
    }
}
