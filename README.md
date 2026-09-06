# Sports Rewards

協助參加台灣運動部「揮汗有禮・全民動起來」運動幣加碼活動的 iOS App：
一鍵登入官方「我的任務」、免重複輸入個資、在同一頁看完本週任務與手上的加碼券。

> **這是非官方工具，與運動部及任何政府機關沒有隸屬、合作、贊助或授權關係。**
> 活動規則與最終權益一律以官方公告為準。

App Store 上架名稱為 **Sports Rewards**。活動名「揮汗有禮」只作為說明文字出現，
不作為 App 名稱——刻意如此，避免被誤認為官方 App。

| | |
|---|---|
| 平台 | iOS 16.0+，僅 iPhone、僅直向、介面固定繁體中文 |
| 第三方相依 | 只有 firebase-ios-sdk（Analytics + Crashlytics），**初始化綁在免責聲明同意之後；同意後預設開啟、隨時可關** |
| 授權 | MIT（[`LICENSE`](LICENSE)） |
| 隱私權政策 | <https://megshao.github.io/sports_rewards_ios/privacy.html> |
| 支援與 FAQ | <https://megshao.github.io/sports_rewards_ios/support.html> |

---

## 這個 App 怎麼看待你的資料

一句話：**開發者沒有任何自建後端**，收不到也看不到你的個資。

- **個資只收三欄**（身分證號／出生日期／手機），只存 iOS Keychain（`WhenUnlockedThisDeviceOnly`、不同步 iCloud、不隨備份轉移），只在你按下登入時由裝置直送 `500.gov.tw`。姓名、Email、健保卡卡號一律不收。
- **完全不讀健康資料**：App 不申請 HealthKit 權限、不含 HealthKit entitlement，也沒有任何讀取健康資料的程式碼路徑。上傳的運動紀錄一律由使用者自己從相簿挑選。
- **上傳的圖一律重新編碼**，把 EXIF（含 GPS）整段丟掉；編碼失敗時報錯而不是退回原檔。
- **遙測綁在免責聲明的同意之後**：首次啟動先擋一張免責聲明，上面明寫「會把匿名操作紀錄與當機報告送給 Google Firebase」，按下同意才初始化 Firebase。同意之後**預設是開的**，可隨時到「我的資料 › 安全與隱私」關掉。這不是 opt-in，是「先告知 → 主動同意 → 預設開啟 → 隨時可關」。個資在任何情況下都不進遙測。

細節見下方[安全設計](#安全設計)，或直接讀[隱私權政策](https://megshao.github.io/sports_rewards_ios/privacy.html)。

## 開源到什麼程度可以被驗證

開源不等於「你手機上那個版本就是這份程式碼」。這中間有一段我們也消除不了的落差，與其宣稱「完全可驗證」，不如把邊界寫清楚。四層階梯完整版在[隱私權政策第 8 節](https://megshao.github.io/sports_rewards_ios/privacy.html#verify)：

1. **不用懂程式**：iOS 內建「App 隱私權報告」列出本 App 連過的網域。**在你按下免責聲明的「同意並開始使用」之前**，只該出現 `500.gov.tw`，以及看截圖時官方網站回傳的圖片儲存網域——那個時間點出現任何 Google 網域就是我們違約，歡迎打臉。同意之後出現 Google 網域是**預期中的**（統計在運作）；把開關關掉並完全重開 App，它們就該再次消失。
2. **懂一點技術**：用 mitmproxy 看每一筆請求的內容——本 App 與 Firebase 都刻意不做 certificate pinning，就是為了讓你看得到。操作步驟與異常判準在 [`docs/verify-network.md`](docs/verify-network.md)。
3. **工程師**：讀原始碼，用 `./Scripts/bootstrap.sh` 重現一模一樣的相依組合（13 個套件全部鎖到 git commit）。
4. **必須信任、我們消除不了的兩件事**：
   - **Apple** — 商店版經重新簽章與 FairPlay 加密，任何人（包括我們）都無法從商店版算出對應原始碼的雜湊。所以本專案**不公布 ipa 的 SHA-256**：對 iOS App 那是驗不到東西的做法。
   - **Google** — `GoogleAppMeasurement` 是閉源二進位，我們讀不到它內部做什麼。能保證的只有：你按下免責聲明的同意之前它不被啟動、連結的是不含 IDFA 能力的 Core 版、它連去的網域你看得到。

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

示範模式下**一個遙測事件都不會送**：`Telemetry.gate` 的第一道就是示範模式，也是唯一沒有 bypass 的閘門；SDK 層的兩個收集旗標同時被關掉。

但有一件事必須誠實講：**這不等於「審查員全程對 Google 零連線」。** 免責聲明擋在 Onboarding 之前，而示範模式是在 Onboarding 的登入表單輸入示範三碼才進入的，所以審查員的實際順序是：

1. 看到免責聲明（上面就寫著會送匿名使用統計）→ 按下同意 → `DisclaimerConsent.record()` 呼叫 `Telemetry.configure()`，**Firebase 在此初始化**，送出 `first_open`、Installations 連線一次；
2. **之後**才進 Onboarding，輸入示範三碼進入示範模式；
3. 從這裡開始，事件一律不送、收集旗標關閉。

這個時序改不掉——示範模式也走 `finish()`，無法用 `hasCompletedOnboarding` 事先區分；要避開就得把初始化延到真實登入成功，那會失去整個 onboarding 漏斗的資料。`configure()` 裡的示範模式守衛只在「冷啟動時已經處於示範模式」那條路上生效。這件事我們選擇主動講在前面，而不是等人自己發現一個沒被解釋過的 Google 連線。

## 安全設計

### 威脅模型摘要

| 面向 | 措施 |
|---|---|
| 個資外洩 | 三欄個資只存 Keychain；無自建後端；個資任何形式都不進遙測 |
| Log 洩漏 | 唯一入口 `SecureLog`，敏感值先過 `Redact`，`debug` 僅 DEBUG build；App 與 Kit 內無 `print`／`NSLog`（UI 截圖測試除外） |
| 網路面 | ATS 強制 https；白名單只允許 `500.gov.tw`，其餘 `blockedEgress`；response body 限 2 MB。詳見[網路出口](#網路出口) |
| 中間人／降級 | 官方站 302 的 `Location` 是 `http://`，client 一律正規化回 https 再送，避免掉 Secure cookie |
| 不受信任的 HTML | 四個 parser 一律把官網回應當不受信任輸入。詳見 [parser 的三條規則](#parser-的三條規則) |
| 上傳的圖片 | 一律 `UIImage.jpegData` 重新編碼去除 EXIF／GPS；編碼失敗報錯，不退回原檔 |
| 裝置遺失 | iOS 鎖屏 + Keychain `WhenUnlockedThisDeviceOnly`（裝置上鎖時連 App 自己都讀不到）+「立即清除本機資料」。**不做 App 內生物辨識鎖**——登入三碼本來就是使用者記得的資料，再擋一次只是重複擋自己人 |
| 健康資料 | **完全不接觸**。無 HealthKit entitlement、無權限提示、無讀取路徑 |
| 資料誠信 | 不繞過戶役政／健保卡／簡訊 OTP，也不提供任何可竄改運動數據的入口 |
| 供應鏈 | 唯一第三方相依 firebase-ios-sdk 12.18.0。詳見[相依關係](#相依關係) |
| 遙測 | 初始化綁在免責聲明同意之後（同意前 Firebase 一行程式碼都不執行），同意後預設開啟、隨時可關；單一出口 + 封閉列舉 + 六道閘門；個資零外傳。詳見[遙測](#遙測) |

### 網路出口

白名單（`isAllowedHost`）只允許 `500.gov.tw` 及其子網域，擋 suffix spoof，其餘 throw `blockedEgress`。三個組 URL 的地方都會檢查。

**唯一刻意的例外**是檢視自己上傳過的截圖——官方網站會回傳一個自帶簽章的圖片網址。這條路徑有兩道自己的關卡：

1. `TasksService.screenshotImageURL` 驗證 302 `Location`：必須是 `https`，host 必須通過 `isAllowedHost` 或是 `*.amazonaws.com`，否則 throw `blockedEgress`。
2. `ScreenshotView` 用**專用的 `URLSession`**（`ephemeral`、`httpCookieStorage = nil`、`urlCache = nil`）下載後以 `Image(uiImage:)` 顯示。

**為什麼不用 `AsyncImage`**：它走 `URLSession.shared`，而 `URLSession.shared` 的 cookie jar 就是 `HTTPCookieStorage.shared`——跟 App 那個 `.default` session 是**同一個 jar**。讓 cookie 不外洩的其實是 cookie 的 domain scope（`500.gov.tw`），不是「這條路徑沒有 cookie」；這個差別在 `Location` 指回官方站自己（同源）時就會現形。順帶解掉的還有 `URLCache.shared` 會把使用者的運動紀錄截圖以網址為 key 落盤到 `Library/Caches`。

**白名單的界線**：它是 `URLSessionHTTPClient` 內的檢查，只管**本 App 自己發出的請求**。Firebase SDK 用它自己的 `URLSession`，**不受這個白名單管轄**——遙測運作時它會連往 `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`（Release 二進位內實際出現的網域）。

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

其餘仍是純 Foundation / SwiftUI；不使用 HealthKit，不使用 `LocalAuthentication`，不使用 WebKit／`WKWebView`。

### 遙測

**`Telemetry.defaultEnabled == true`——同意之後預設開啟。** 不要包裝成「還是 opt-in」，它不是；它是**先告知、主動同意，之後預設開啟、隨時可關**。

**真正的保障是初始化的時機，不是預設值**：首次啟動會擋一張必須主動勾選的免責聲明（`App/Sources/Views/DisclaimerView.swift`），畫面上明寫「App 會把匿名的操作紀錄與當機報告送給 Google Firebase」，勾選文字也涵蓋「並同意傳送不含個資的匿名使用統計（可隨時關閉）」。使用者按下「同意並開始使用」時，`DisclaimerConsent.record()` 才呼叫 `Telemetry.configure()`——**那是整支 App 第一次執行 Firebase 程式碼的時機**。

**為什麼界線要放在「執行與否」而不是旗標**：`FirebaseApp.configure()` 一執行就會產生 app instance ID 並送出 `first_open`——而且即使兩個收集旗標都是 `false`，Firebase Installations 仍會連 `firebaseinstallations.googleapis.com` 要一組 installation ID。所以「同意前零連線」不能靠關旗標達成，只能靠不執行。

`configure()` 有三道前置條件，缺一不初始化：**尚未同意免責聲明**、**使用者關掉開關**、**示範模式**。

**`Info.plist` 的四個旗標仍然全為 `false`**（`FIREBASE_ANALYTICS_COLLECTION_ENABLED`、`FirebaseCrashlyticsCollectionEnabled`、`GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`、`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS`）。它們是**冷啟動的預設值**，由 `applyCollectionFlags` 在初始化之後依使用者當前偏好覆寫；留成 `false` 是為了守住「還沒 `configure` 就絕不收集」這條線，不是為了表達「預設關閉」。

**為什麼同意之後直接是開的**：當機報告要有足夠樣本才修得到 bug，而「預設關 + 藏在設定頁第三層」實際上等於沒人會打開。與其換一個「技術上是 opt-in」的說法，不如把揭露擺在使用者一定看得到的地方，再由他自己按下同意。

代價要講清楚：使用者按下同意的那一刻 Firebase 就已經初始化，`first_open` 與 Installations 連線是實際發生的。反向也一樣誠實：關掉開關只會關收集旗標、重置 instance ID、刪未送報告，SDK 在本次執行期間仍在記憶體裡，要回到「一行都不跑」得等下一次冷啟動。「立即清除本機資料」會一併重置同意紀錄與遙測偏好，下次啟動會重新看到免責聲明。

**型別擋到哪為止**：全 App 唯一的遙測出口是 `App/Sources/App/Telemetry.swift`（其他檔案禁止 import Firebase）。事件名與參數值都來自封閉列舉——`AnalyticsValue` 的底層儲存是 `private`，唯一能產生字串參數的建構子 `code(_:)` 只收封閉列舉的 rawValue，所以自由字串**值**在編譯期就構造不出來；使用者屬性是一個空列舉，根本無法建構。但參數的**鍵**與 Crashlytics 的 breadcrumb 仍然是字串，那兩處靠的是送出前的樣式掃描，不是編譯器。

送出前共**六道閘門**：示範模式 → 截圖模式 → 使用者關閉 → 未初始化 → 參數命中 `Redact` 敏感樣式 → 整數超出允許值域（最後兩道在 DEBUG build 直接 `assertionFailure`）。

**個資完全不進遙測**，也不設定任何 user property。App 不讀取任何健康資料，因此遙測裡也不存在健康相關的事件（原本的 `health_link_tap` 已隨功能一併移除）。

## 授權

MIT，見 [`LICENSE`](LICENSE)。變更紀錄見 [`CHANGELOG.md`](CHANGELOG.md)。

問題回報：<https://github.com/megshao/sports_rewards_ios/issues>
