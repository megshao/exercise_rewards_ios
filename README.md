# Sports Rewards（揮汗有禮活動・非官方輔助工具）

協助參加台灣運動部「揮汗有禮・全民動起來」運動幣加碼活動的 iOS App：
一鍵登入官方「我的任務」、免重複輸入個資、連結 Apple 健康看今日步數是否達標。

> **這是非官方工具，與運動部及任何政府機關沒有隸屬、合作、贊助或授權關係。**
> 活動規則與最終權益一律以官方公告為準。

App Store 上架名稱為 **Sports Rewards**。活動名「揮汗有禮」只作為說明文字出現，
**不作為 App 名稱**——刻意不使用活動名，避免被誤認為官方 App。

- 隱私權政策：<https://megshao.github.io/sports-rewards-ios/privacy.html>
- 支援與常見問題：<https://megshao.github.io/sports-rewards-ios/support.html>

## 架構

- `Sources/SportsRewardsKit/`（Swift Package）：核心邏輯，可 headless `swift build` / `swift test`
  - `Networking/` `URLSessionHTTPClient`（網域白名單、修正官方站 http→https 降級 redirect、`resetSession()` 清 cookie）、`CsrfParser`
  - `Services/` `AuthService`（access→login，無 OTP）、`TasksService`、`TaskParser`
  - `Security/` `KeychainStore`、`SecureLog`、`Redact`
  - `Health/` `HealthReading` 協定、`GoalEvaluator`
- `App/`（SwiftUI，XcodeGen 產生 `.xcodeproj`）：UI、HealthKit 實作、送審示範模式（`DemoMode`）
  - 介面固定繁體中文：開發語言鎖 `zh-Hant`（`App/project.yml`）＋注入 `Locale(zh_Hant_TW)`，不隨裝置語系變動
  - 個資最小化：只收集登入必需的**身分證號／出生日期／手機**三欄；姓名、Email、健保卡卡號**一律不收集**（App 不做註冊，未註冊者導向外部 Safari 到官網自行註冊）
  - **不含任何生物辨識**：不用 `LocalAuthentication`，`Info.plist` 也沒有 `NSFaceIDUsageDescription`
- `App/UITests/`：以示範模式走完全部畫面、產出 App Store 截圖的 UI 測試

### 建置

```sh
swift test                       # 核心 72 tests，不需 Xcode 專案
cd App && xcodegen generate
xcodebuild -project SportsRewards.xcodeproj -scheme SportsRewards \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

產生上架截圖（輸出到 `docs/screenshots/raw/`）：

```sh
cd App && xcodebuild test -project SportsRewards.xcodeproj \
  -scheme SportsRewardsScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

## 安全設計（威脅模型摘要）

| 面向 | 措施 |
|---|---|
| 個資外洩 | 身分證／出生日期／手機（只收這三欄）只存 iOS Keychain（`WhenUnlockedThisDeviceOnly`、不同步 iCloud、不備份轉移）；**無任何雲端後端**，開發者收不到也看不到任何資料 |
| Log 洩漏 | 全專案唯一 log 入口 `SecureLog`；敏感值一律先過 `Redact`；`debug` 僅 DEBUG build 輸出；禁 log cookie/CSRF/OTP/session。App 與 SportsRewardsKit 內無 `print` / `NSLog` / 直接 `os_log`（UI 截圖測試除外） |
| 網路面 | ATS 強制 https；`URLSessionHTTPClient` 白名單只允許 `500.gov.tw`（含子網域、擋 suffix spoof），其餘 throw `blockedEgress`。唯一刻意例外：檢視已上傳截圖時，`ScreenshotView` 以 `AsyncImage` 載入官方回傳的 S3 簽章圖片網址（cookie 的 domain scope 是 `500.gov.tw`，不會送到該 host）；cookie 存在 App 沙盒容器（受 iOS 檔案保護、不進 iCloud），登出與「立即清除本機資料」都會 `resetSession()` 清空 |
| 中間人／降級 | 官方站 302 Location 是 `http://`；client 一律正規化回 https 再送，避免掉 Secure cookie |
| 裝置遺失 | 防線是 **iOS 裝置本身的鎖屏**（密碼／Face ID／Touch ID）加上 Keychain 的 `WhenUnlockedThisDeviceOnly`：**裝置上鎖時連本 App 自己都讀不到**這些欄位，資料也不會同步 iCloud 或隨備份轉移。另在「我的資料 › 安全與隱私」提供「立即清除本機資料」可隨時永久刪除。<br>**不做 App 內生物辨識鎖**：登入所需三碼本來就是使用者本人記得、官方網站登入也只驗這三碼，App 內再擋一次不會改變裝置遺失時的實際暴露面（真正的界線是裝置鎖屏），只是重複擋自己人 |
| 健康資料 | HealthKit **唯讀**步數／距離／運動時間，**從不寫入、從不外傳**；只在畫面上顯示與本機判斷是否達標。上傳一律由使用者自己從相簿選圖，App **不以健康數據合成任何要上傳的圖片** |
| 資料誠信 | 不繞過戶役政／健保卡／簡訊 OTP 等真實驗證，也不提供任何可竄改運動數據的入口 |
| 供應鏈 | 零第三方相依，純 Foundation / SwiftUI / HealthKit；**不使用 LocalAuthentication、不使用 WebKit/WKWebView、無任何 analytics 或 crash SDK** |

## 示範模式

登入需要真實身分證號與手機號碼，App Store 審查員拿不到，因此內建**完全揭露**的示範模式：
在登入表單輸入示範三碼即進入全 mock 環境，**不發出任何網路請求**，個資只在記憶體、
不寫 Keychain，畫面頂端常駐「示範模式」橫幅。三碼寫在 `App/Sources/App/DemoMode.swift`，
並如實填寫於 App Store Connect 的示範帳號欄位。

## 授權

MIT，見 [`LICENSE`](LICENSE)。變更紀錄見 [`CHANGELOG.md`](CHANGELOG.md)。

問題回報：<https://github.com/megshao/sports-rewards-ios/issues>
