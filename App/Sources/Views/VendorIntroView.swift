import SwiftUI
import SportsRewardsKit

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
            viewModel.configure(redeem: environment.redeem, introPath: introPath)
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
            loaded(intro)
        }
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
    private var introPath = ""

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

    func configure(redeem: RedeemServicing, introPath: String) {
        guard self.redeem == nil else { return }
        self.redeem = redeem
        self.introPath = introPath
    }

    func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    func load() async {
        guard let redeem else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            intro = try await redeem.vendorIntro(path: introPath)
        } catch {
            // 這一頁是純資訊，載不到不影響兌換本身，因此只提示、不擋流程。
            errorMessage = "無法載入可兌換商品清單，請稍後再試。"
            Telemetry.reportFailure(error, endpoint: .vendorIntro)
        }
    }
}
