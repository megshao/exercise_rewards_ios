import SwiftUI

/// 首次啟動的免責聲明同意畫面。擋在 Onboarding 之前，是使用者看到的第一個畫面。
///
/// **為什麼要主動同意而不是被動告知**：Onboarding 歡迎頁本來就有一張非官方聲明卡，
/// 但那是「使用者可能沒看就滑過去」的資訊。這支 App 會把身分證號送到官方網站、
/// 顯示的任務與券況也全部來自官方網站，使用者必須在填第一個欄位之前就知道
/// 「出了事該找誰」——所以改成必須主動勾選才能繼續。
///
/// **這個畫面同時是遙測的揭露點**：`DisclaimerConsent.record()` 會在使用者按下同意時
/// 呼叫 `Telemetry.configure()`——那是整支 App 第一次執行 Firebase 程式碼的時機。
/// 所以「匿名使用統計」那一條**不能從這裡拿掉**，拿掉就變成「使用者沒讀到就開始送」。
///
/// **文案用語的界線**（改文案前務必讀）：
/// - 不可寫「不儲存個資」。三欄個資確實存在 iOS Keychain，寫「不儲存」與實作不符，
///   而且會和隱私權政策、App 內其他文案互相矛盾。準確的說法是
///   「只存在你的手機，開發者收不到」。
/// - 不可寫「串接官方 API」。官方網站沒有公開 API，本 App 是以一般瀏覽器的身分
///   提交同一份網頁表單。寫成 API 會暗示某種官方授權或合作關係。
struct DisclaimerView: View {
    /// 同意的版本號。日後若修改聲明內容且變動涉及使用者權益，把這個數字加一，
    /// 已同意過舊版的使用者就會再看到一次。
    static let currentVersion = 1

    let onAgree: () -> Void

    @State private var hasAgreed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    unofficialSection
                    dataSection
                    supportSection
                }
                .padding(20)
                // 底部的同意列是固定的，會蓋住捲動內容。留出它的高度，
                // 捲到底時最後一條才不會被切一半（看起來像 bug）。
                .padding(.bottom, 24)
            }

            agreeBar
        }
        .background(Theme.Colors.background)
    }

    // MARK: - 標題

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("使用前請先確認")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.Colors.text)
            Text("這是個人開發的非官方工具。開始使用前，有三件事想先跟你說清楚。")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - 一、非官方身分

    private var unofficialSection: some View {
        section(
            icon: "info.circle.fill",
            iconTint: Theme.Colors.warnText,
            iconBackground: Theme.Colors.warnBackground,
            title: "這不是官方 App"
        ) {
            bullet("本 App 由個人開發，與運動部及任何政府機關**沒有隸屬、合作、贊助或授權關係**，也不代表活動主辦單位。")
            bullet("活動規則、資格認定、審核結果與獎品權益，**一律以官方公告為準**。")
        }
    }

    // MARK: - 二、資料怎麼處理

    private var dataSection: some View {
        section(
            icon: "lock.shield.fill",
            iconTint: Theme.Colors.success,
            iconBackground: Theme.Colors.successBackground,
            title: "你的資料只在你手機裡"
        ) {
            bullet("開發者**沒有任何伺服器**，收不到也看不到你的身分證號、生日、手機號碼與健康數據。")
            bullet("這三個欄位加密保存在**這支手機**（iOS Keychain），不同步 iCloud、不隨備份轉移，可隨時在「我的資料」一鍵永久刪除。")
            bullet("你按下登入時，資料由**這支手機直接送到官方網站**，中間不經過開發者或任何其他服務。")
            bullet("為了修 bug，App 會把**匿名的操作紀錄與當機報告**送給 Google Firebase：看了哪個畫面、哪一步失敗、當機在哪。**裡面沒有你的個資，也沒有任何健康數據**——連「今天有沒有達標」都不會送。不想送可以到「我的資料 › 安全與隱私」關掉。")
        }
    }

    // MARK: - 三、資料來源與客服

    private var supportSection: some View {
        section(
            icon: "arrow.triangle.2.circlepath",
            iconTint: Theme.Colors.primary,
            iconBackground: Theme.Colors.card2,
            title: "畫面上的內容來自官方網站"
        ) {
            bullet("本 App 只是幫你把官方網站的資料整理得比較好看。**任務狀態、審核結果、券的效期與可否使用，全部由官方網站決定**，本 App 不做任何判定，也無法代為修改。")
            bullet("官方網站改版或維護時，本 App 可能會顯示不正確或暫時無法使用。")
            bullet("**活動或帳號有問題，請直接聯繫官方客服**——本 App 無法代為處理，也查不到你的帳號狀態。")
            bullet("App 本身的問題（畫面錯誤、當機）才需要找開發者，聯絡方式在「我的資料」頁。")
        }
    }

    // MARK: - 同意列

    private var agreeBar: some View {
        VStack(spacing: 12) {
            Button {
                hasAgreed.toggle()
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: hasAgreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20))
                        .foregroundStyle(hasAgreed ? Theme.Colors.primary : Theme.Colors.dim)
                    Text("我已閱讀並理解上述說明，了解這是非官方工具、活動權益以官方公告為準，並同意傳送不含個資的匿名使用統計（可隨時關閉）。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Colors.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("disclaimer.agreeCheckbox")

            Button("同意並開始使用") {
                onAgree()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!hasAgreed)
            .opacity(hasAgreed ? 1 : 0.45)
            .accessibilityIdentifier("disclaimer.continue")
        }
        .padding(20)
        .background(
            Theme.Colors.card
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.05), radius: 12, y: -4)
        )
    }

    // MARK: - 元件

    private func section<Content: View>(
        icon: String,
        iconTint: Color,
        iconBackground: Color,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(iconTint)
                    .frame(width: 32, height: 32)
                    .background(iconBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(Theme.Colors.text)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// 支援 `**粗體**` 的條列。用 markdown 讓重點在長句裡看得出來。
    private func bullet(_ markdown: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("・")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.dim)
            Text(.init(markdown))
                .font(.system(size: 13))
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    DisclaimerView(onAgree: {})
}
