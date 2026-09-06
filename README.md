# Sports Rewards

協助參加台灣運動部「揮汗有禮・全民動起來」運動幣加碼活動的 iOS App：
一鍵登入官方「我的任務」、免重複輸入個資、連結 Apple 健康看今日步數是否達標。

> **這是非官方工具，與運動部及任何政府機關沒有隸屬、合作、贊助或授權關係。**
> 活動規則與最終權益一律以官方公告為準。

App Store 上架名稱為 **Sports Rewards**。活動名「揮汗有禮」只作為說明文字出現，
不作為 App 名稱——刻意如此，避免被誤認為官方 App。

| | |
|---|---|
| 平台 | iOS 16.0+，僅 iPhone、僅直向、介面固定繁體中文 |
| 第三方相依 | 只有 firebase-ios-sdk（Analytics + Crashlytics），**預設關閉、使用者 opt-in** |
| 授權 | MIT（[`LICENSE`](LICENSE)） |
| 隱私權政策 | <https://megshao.github.io/sports-rewards-ios/privacy.html> |
| 支援與 FAQ | <https://megshao.github.io/sports-rewards-ios/support.html> |

---

## 這個 App 怎麼看待你的資料

一句話：**開發者沒有任何自建後端**，收不到也看不到你的個資與健康數據。

- **個資只收三欄**（身分證號／出生日期／手機），只存 iOS Keychain（`WhenUnlockedThisDeviceOnly`、不同步 iCloud、不隨備份轉移），只在你按下登入時由裝置直送 `500.gov.tw`。姓名、Email、健保卡卡號一律不收。
- **HealthKit 唯讀且不外傳**：步數／距離／運動時間只在畫面上顯示與本機判斷達標，不上傳、不用於合成任何要上傳的圖片。
- **上傳的圖一律重新編碼**，把 EXIF（含 GPS）整段丟掉；編碼失敗時報錯而不是退回原檔。
- **遙測預設關閉**，且個資與 HealthKit 衍生值（連「今日是否達標」的布林都算）在任何情況下都不進遙測。

細節見下方[安全設計](#安全設計)，或直接讀[隱私權政策](https://megshao.github.io/sports-rewards-ios/privacy.html)。

## 開源到什麼程度可以被驗證

開源不等於「你手機上那個版本就是這份程式碼」。這中間有一段我們也消除不了的落差，與其宣稱「完全可驗證」，不如把邊界寫清楚。四層階梯完整版在[隱私權政策第 8 節](https://megshao.github.io/sports-rewards-ios/privacy.html#verify)：

1. **不用懂程式**：iOS 內建「App 隱私權報告」列出本 App 連過的網域。開關關著時只該出現 `500.gov.tw`，以及看截圖時官方網站回傳的圖片儲存網域。**出現任何 Google 網域就是我們違約，歡迎打臉。**
2. **懂一點技術**：用 mitmproxy 看每一筆請求的內容——本 App 與 Firebase 都刻意不做 certificate pinning，就是為了讓你看得到。操作步驟與異常判準在 [`docs/verify-network.md`](docs/verify-network.md)。
3. **工程師**：讀原始碼，用 `./Scripts/bootstrap.sh` 重現一模一樣的相依組合（13 個套件全部鎖到 git commit）。
4. **必須信任、我們消除不了的兩件事**：
   - **Apple** — 商店版經重新簽章與 FairPlay 加密，任何人（包括我們）都無法從商店版算出對應原始碼的雜湊。所以本專案**不公布 ipa 的 SHA-256**：對 iOS App 那是驗不到東西的做法。
   - **Google** — `GoogleAppMeasurement` 是閉源二進位，我們讀不到它內部做什麼。能保證的只有：你沒 opt-in 前它不被啟動、連結的是不含 IDFA 能力的 Core 版、它連去的網域你看得到。

## 架構

```
Sources/SportsRewardsKit/   核心邏輯，可 headless swift build / swift test
  Networking/               URLSessionHTTPClient（網域白名單、http→https 修正、2 MB body 上限）、CsrfParser
  Services/                 AuthService、TasksService、RedeemService、VoucherService 與各自的 parser
  Security/                 KeychainStore、SecureLog、Redact
  Health/                   HealthReading 協定、GoalEvaluator
App/                        SwiftUI，XcodeGen 產生 .xcodeproj
  Sources/App/Telemetry.swift        全 App 唯一的 Firebase 出口（封閉列舉 + 六道閘門）
  Sources/App/DemoMode.swift         送審示範模式
  Resources/PrivacyInfo.xcprivacy    隱私資訊清單
  UITests/                           以示範模式產出 App Store 截圖
```

幾個刻意的設計：介面語言鎖 `zh-Hant` 並注入 `Locale(zh_Hant_TW)`，不隨裝置語系變動；App 不做註冊，未註冊者導向外部 Safari 到官網；不含任何生物辨識（不用 `LocalAuthentication`，`Info.plist` 也沒有 `NSFaceIDUsageDescription`）。

## 建置

```sh
swift test                       # 核心單元測試，不需 Xcode 專案
./Scripts/bootstrap.sh           # 產生 Xcode 專案並套用相依鎖定
xcodebuild -project App/SportsRewards.xcodeproj -scheme SportsRewards \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -disableAutomaticPackageResolution build
```

**為什麼要多一支 `bootstrap.sh`**：`.xcodeproj` 由 XcodeGen 產生、不進版控，而 Xcode 把 SPM 鎖定檔放在 `.xcodeproj` 裡面，於是鎖定檔也跟著進不了版控。腳本把版控中的真本 `App/Package.resolved` 複製回 Xcode 期望的位置；建置時加 `-disableAutomaticPackageResolution`，Xcode 才不會偷偷重新解析改寫它。兩步都做到，任何人建出來的相依組合才會跟我們一樣。升級相依版本跑 `./Scripts/bootstrap.sh --resolve`，步驟寫在腳本檔頭。

Firebase 需要 `App/Resources/GoogleService-Info.plist`（不進版控，範本見同目錄的 `.template`）。**沒有它也能正常 build 與執行**——`Telemetry.configure()` 找不到就跳過初始化，全程 no-op 且不 crash。

產生上架截圖（輸出到 `docs/screenshots/raw/`）：

```sh
cd App && xcodebuild test -project SportsRewards.xcodeproj \
  -scheme SportsRewardsScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

## 示範模式

登入需要真實身分證號與手機號碼，App Store 審查員拿不到，所以內建**完全揭露**的示範模式：在登入表單輸入示範三碼即進入全 mock 環境，不發出任何網路請求，個資只在記憶體、不寫 Keychain，畫面頂端常駐「示範模式」橫幅。

三碼寫在 `App/Sources/App/DemoMode.swift`，並如實填在 App Store Connect 的示範帳號欄位——它是公開揭露的功能，不是隱藏手勢。

遙測在示範模式下**一律不初始化**，即使開關是打開的。這是 `Telemetry` 唯一沒有 bypass 的閘門。

## 安全設計

### 威脅模型摘要

| 面向 | 措施 |
|---|---|
| 個資外洩 | 三欄個資只存 Keychain；無自建後端；個資與 HealthKit 資料任何形式都不進遙測 |
| Log 洩漏 | 唯一入口 `SecureLog`，敏感值先過 `Redact`，`debug` 僅 DEBUG build；App 與 Kit 內無 `print`／`NSLog`（UI 截圖測試除外） |
| 網路面 | ATS 強制 https；白名單只允許 `500.gov.tw`，其餘 `blockedEgress`；response body 限 2 MB。詳見[網路出口](#網路出口) |
| 中間人／降級 | 官方站 302 的 `Location` 是 `http://`，client 一律正規化回 https 再送，避免掉 Secure cookie |
| 不受信任的 HTML | 四個 parser 一律把官網回應當不受信任輸入。詳見 [parser 的三條規則](#parser-的三條規則) |
| 上傳的圖片 | 一律 `UIImage.jpegData` 重新編碼去除 EXIF／GPS；編碼失敗報錯，不退回原檔 |
| 裝置遺失 | iOS 鎖屏 + Keychain `WhenUnlockedThisDeviceOnly`（裝置上鎖時連 App 自己都讀不到）+「立即清除本機資料」。**不做 App 內生物辨識鎖**——登入三碼本來就是使用者記得的資料，再擋一次只是重複擋自己人 |
| 健康資料 | HealthKit 唯讀，從不寫入、從不外傳、不用於合成上傳內容 |
| 資料誠信 | 不繞過戶役政／健保卡／簡訊 OTP，也不提供任何可竄改運動數據的入口 |
| 供應鏈 | 唯一第三方相依 firebase-ios-sdk 12.18.0。詳見[相依關係](#相依關係) |
| 遙測 | 預設關閉、opt-in、封閉列舉 + 六道閘門。詳見[遙測](#遙測) |

### 網路出口

白名單（`isAllowedHost`）只允許 `500.gov.tw` 及其子網域，擋 suffix spoof，其餘 throw `blockedEgress`。三個組 URL 的地方都會檢查。

**唯一刻意的例外**是檢視自己上傳過的截圖——官方網站會回傳一個自帶簽章的圖片網址。這條路徑有兩道自己的關卡：

1. `TasksService.screenshotImageURL` 驗證 302 `Location`：必須是 `https`，host 必須通過 `isAllowedHost` 或是 `*.amazonaws.com`，否則 throw `blockedEgress`。
2. `ScreenshotView` 用**專用的 `URLSession`**（`ephemeral`、`httpCookieStorage = nil`、`urlCache = nil`）下載後以 `Image(uiImage:)` 顯示。

**為什麼不用 `AsyncImage`**：它走 `URLSession.shared`，而 `URLSession.shared` 的 cookie jar 就是 `HTTPCookieStorage.shared`——跟 App 那個 `.default` session 是**同一個 jar**。讓 cookie 不外洩的其實是 cookie 的 domain scope（`500.gov.tw`），不是「這條路徑沒有 cookie」；這個差別在 `Location` 指回官方站自己（同源）時就會現形。順帶解掉的還有 `URLCache.shared` 會把使用者的運動紀錄截圖以網址為 key 落盤到 `Library/Caches`。

**白名單的界線**：它是 `URLSessionHTTPClient` 內的檢查，只管**本 App 自己發出的請求**。Firebase SDK 用它自己的 `URLSession`，**不受這個白名單管轄**——使用者開啟遙測後它會連往 `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`（Release 二進位內實際出現的網域）。

**刻意不做 certificate pinning**：pinning 擋掉的是想自己檢查請求內容的使用者，跟「你可以自己查」的立場相反；而在 ATS 已強制 TLS 1.2+／forward secrecy 的前提下，它多擋的只剩「使用者自己在裝置上安裝並信任的憑證」這一種情境。

Cookie 存在 App 沙盒容器（受 iOS 檔案保護、不進 iCloud），**重新登入前**與「立即清除本機資料」時都會 `resetSession()` 清空。

### parser 的三條規則

`TaskParser`／`VoucherParser`／`CsrfParser`／`RedeemParser` 吃的是官方網站回傳的 HTML——不受信任的輸入。

1. **相鄰量詞的字元集合不得重疊**。`\s*([^<]+?)\s*<` 這種形狀是災難性回溯：實測 1600 個空白要 34 秒（O(n³)）。改寫成 `([^<]*)<` 再 trim。
2. **每個量詞都有長度上限** `{0,N}`。
3. **標籤屬性用 `[^<>]` 而非 `[^>]`**——屬性內不可能有裸 `<`，排除它讓「大量未閉合標籤」在下一個 `<` 就停住。這比單純加上限有效得多。

共用的止血點是 `URLSessionHTTPClient.send` 的 2 MB body 上限：超過就丟 `AppError.responseTooLarge`，body 不解碼、不交給任何 parser。回歸測試在 [`Tests/SportsRewardsKitTests/HTMLParserReDoSTests.swift`](Tests/SportsRewardsKitTests/HTMLParserReDoSTests.swift)——每個樣式餵 4 KB 對抗輸入，斷言 100 ms 內完成。

### 相依關係

唯一的第三方相依是 **firebase-ios-sdk 12.18.0**（Analytics + Crashlytics）。

SPM 為了解析相依關係會 checkout **13 個套件**，但**實際連進 App 二進位的只有 6 個**：`firebase-ios-sdk`、`GoogleAppMeasurement`、`GoogleDataTransport`、`GoogleUtilities`、`nanopb`、`promises`。其餘 7 個（`abseil-cpp-binary`、`app-check`、`google-ads-on-device-conversion-ios-sdk`、`grpc-binary`、`gtm-session-fetcher`、`interop-ios-for-google-sdks`、`leveldb`）只被解析、沒有被連結，可用 `SportsRewards.LinkFileList` 覆核。

選的是 **`FirebaseAnalyticsCore`** 而不是 `FirebaseAnalytics`：底層是 `GoogleAppMeasurementCore`，**結構上不含 IDFA 收集能力**——這是連結期的保證，不是 Info.plist 旗標的保證。Release 二進位已用 `otool -l` 驗證沒有連結 `AdSupport`、`AppTrackingTransparency`、`AdServices`，因此不會、也無法出現 ATT 提示。

其餘仍是純 Foundation / SwiftUI / HealthKit；不使用 `LocalAuthentication`，不使用 WebKit／`WKWebView`。

### 遙測

**預設關閉，使用者 opt-in。** `Info.plist` 的四個旗標全為 `false`；使用者要自己到「我的資料 › 安全與隱私 › 傳送匿名使用統計」打開才會開始送。

**為什麼預設關**：`FirebaseApp.configure()` 一執行就會產生 app instance ID 並送出 `first_open`——而且即使兩個收集旗標都是 `false`，Firebase Installations 仍會連 `firebaseinstallations.googleapis.com` 要一組 installation ID。預設開的話，使用者在看到那個開關之前資料就已經送出去了。

**所以界線放在「執行與否」而不是旗標**：`Telemetry.configure()` 在使用者尚未同意時直接 return，`FirebaseApp.configure()` 根本不會被呼叫。使用者打開開關那一刻，才是整支 App 第一次執行 Firebase 的程式碼。

代價要講清楚：Crashlytics 抓不到 opt-in 之前的當機——這就是 opt-in 的語意。反向也一樣誠實：關掉開關只會關收集旗標、重置 instance ID、刪未送報告，SDK 在本次執行期間仍在記憶體裡，要回到「一行都不跑」得等下一次冷啟動。

**型別擋到哪為止**：全 App 唯一的遙測出口是 `App/Sources/App/Telemetry.swift`（其他檔案禁止 import Firebase）。事件名與參數值都來自封閉列舉——`AnalyticsValue` 的底層儲存是 `private`，唯一能產生字串參數的建構子 `code(_:)` 只收封閉列舉的 rawValue，所以自由字串**值**在編譯期就構造不出來；使用者屬性是一個空列舉，根本無法建構。但參數的**鍵**與 Crashlytics 的 breadcrumb 仍然是字串，那兩處靠的是送出前的樣式掃描，不是編譯器。

送出前共**六道閘門**：示範模式 → 截圖模式 → 使用者關閉 → 未初始化 → 參數命中 `Redact` 敏感樣式 → 整數超出允許值域（最後兩道在 DEBUG build 直接 `assertionFailure`）。

**個資與 HealthKit 資料完全不進遙測**：連「今日是否達標」這種由步數推導的布林值都不送，因為 Apple 禁止把健康資料分享給第三方。唯一沾到健康的是 `health_link_tap`——「按了連結 Apple 健康的按鈕」這個 UI 動作，按下當下 HealthKit 尚未被呼叫。授權結果不送，也不設定任何 user property。

## 授權

MIT，見 [`LICENSE`](LICENSE)。變更紀錄見 [`CHANGELOG.md`](CHANGELOG.md)。

問題回報：<https://github.com/megshao/sports-rewards-ios/issues>
