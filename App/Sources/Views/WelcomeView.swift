import SwiftUI

/// App 的第一個畫面：App icon ＋ 大標題 ＋「開始使用」。
///
/// ## 為什麼它排在免責聲明**之前**
///
/// 免責聲明是一整頁的條款，第一次開 App 就直接撞上它，使用者連「這是什麼 App」都還不知道
/// 就要決定同不同意。先給一頁「這是什麼、誰做的」，按下「開始使用」表示願意繼續，
/// 再請他讀條款——這個順序讓同意是有前提的，而不是被迫點掉一個障礙。
///
/// ## 這一頁不會送出任何遙測
///
/// 它在同意之前，`Telemetry` 的閘門會擋掉所有事件（那正是「同意前 Firebase 一行程式碼
/// 都不執行」這句話的來源）。因此**不要在這裡埋任何事件**——埋了也送不出去，
/// 只會讓人誤以為有資料。導覽漏斗的第一步 `tutorial_begin` 改在表單出現時才送
/// （見 `OnboardingView`）。
struct WelcomeView: View {
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 14) {
                appIcon

                // 主標一律用上架名稱 Sports Rewards：刻意不拿活動名「揮汗有禮」自稱，
                // 避免被誤認為官方 App；活動名只出現在說明用途的副標裡。
                Text("Sports Rewards")
                    .font(Theme.displayFont(28, weight: .heavy))

                Text("協助你參加運動部「揮汗有禮」活動的非官方小工具\n每週達標，就能換一張超商加碼券")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Colors.muted)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // 非官方聲明（App 內三處揭露之一：啟動頁／我的資料／App Store 商店描述）。
            disclaimerCard

            Text("下一步會先請你看一次使用說明與免責聲明。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onStart) {
                Text("開始使用")
            }
            .accessibilityIdentifier("welcome.start")
            .buttonStyle(.huihanPrimary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }

    /// 用 App icon 本體，而不是 SF Symbol——第一個畫面上的圖案與桌面上那顆圖示一致，
    /// 使用者才對得起來「我點的就是這個 App」。
    ///
    /// **為什麼是 `AppIconMark` 而不是 `AppIcon`**：asset catalog 裡的 app icon
    /// （`.appiconset`）在執行期不保證能用 `Image("AppIcon")` 取到——它會被編譯成
    /// 給 SpringBoard 用的檔案，不是普通 imageset。所以另外放了一份一般的 imageset
    /// （`AppIconMark.imageset`，同一張 `icon_1024.png`）專供畫面使用。
    /// 換 App icon 時記得**兩份都換**。
    private var appIcon: some View {
        Image("AppIconMark")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 96, height: 96)
            // 對齊 iOS 的圖示圓角比例（1024 的 continuous 圓角約 22.37%）。
            .clipShape(RoundedRectangle(cornerRadius: 96 * 0.2237, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 96 * 0.2237, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            .accessibilityHidden(true)
    }

    /// 首次啟動就把話講清楚：這是個人做的非官方工具，跟主辦單位沒有任何關係。
    private var disclaimerCard: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
            Text("本 App 由個人開發，是非官方工具，與運動部沒有任何隸屬或授權關係。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.card2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

#Preview {
    WelcomeView(onStart: {})
}
