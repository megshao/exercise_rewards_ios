# Firebase Analytics 與 Crashlytics 量測計畫

> **狀態**：設計提案（尚未實作、未改任何程式碼）。撰寫日期 2026-09-06。
> 對應程式碼：`develop` 工作樹（`d94ae6e` 之後，含未提交的 `DemoMode.swift` 與 View 改動）。
> 本文件是「若要加 Firebase，只能這樣加」的邊界規格；它**不是**「應該加 Firebase」的結論——見 §0。
>
> ⚠️ **2026-09-06 更新（v1.1）**：健康連結功能已整個移除。本文件裡所有關於 HealthKit 的段落
> ——G4、§1.1 的不可量測宣告、E9／E10、以及「為什麼健康衍生值不可外傳」的論證——**前提都已不存在**。
> 個別條目已就地標註；那些「刻意不送」的規則**仍然有效**（作為日後若有人加回健康功能的既定判準），
> 但目前 App 根本沒有健康資料可送。

---

## 0. 先講前提：這份計畫與現有承諾衝突，動工前必須先做決定

專案目前在**六個地方**對使用者做出「零第三方」的承諾，任何一個 Firebase SDK 進來都會讓它們變成不實陳述：

| 位置 | 原文 | 衝突點 |
|---|---|---|
| `README.md:56` | 「零第三方相依 … **無任何 analytics 或 crash SDK**」 | 直接相反 |
| `docs/PRD.md §8.2` | 「**禁用**會外傳個資的第三方 analytics / crash SDK；若需 crash 收集，須本機化且不含個資」 | 直接相反 |
| `docs/TASKS.md:5` | 硬約束「不上雲、不寫 log、**只連 500.gov.tw**」 | Firebase 會連 `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com` 等（網域以 Release 二進位內實際出現者為準） |
| `App/Sources/Views/ProfileView.swift:80` | 「不會上傳雲端、不會同步 iCloud、不會寫入紀錄檔，也**不會提供給任何第三方**」 | Crashlytics／Analytics 就是第三方 |
| `App/Sources/Views/ProfileView.swift:267` | 頁尾「個資不上雲 · 不寫紀錄檔 · **只連 500.gov.tw**」 | 同上 |
| `App/Sources/Views/HomeView.swift:227`、`OnboardingView.swift:113` | 「個資只存這支手機 · 不會上傳雲端」「不會寫入紀錄檔」 | 個資確實不會，但「不寫紀錄檔」在 Crashlytics 存在時語意變模糊 |

另外 `URLSessionHTTPClient` 的網域白名單只管 App 自己發的請求，**管不到 Firebase SDK 內部的 URLSession**——PRD §2.3 的反指標「對非 `500.gov.tw` 網域的非預期連線必須為 0」需要改寫成「非預期」的定義含 Firebase 例外，而且只在使用者同意後。

因此本計畫的**前置決定**只有兩個選項：

- **選項 A：加 Firebase，但預設關閉（opt-in），並同步改寫上表六處文案與 PRD/README/隱私政策**（§6.5 有完整清單）。本文件其餘章節都是在這個前提下寫的。
  > **⚠️ 決策後續（2026-09-06）**：選項 A 被採用，但**「預設關閉（opt-in）」這一半在同日被推翻**。
  > 實際出貨的是「**先告知 → 使用者主動同意 → 之後預設開啟 → 隨時可關**」：`Telemetry.defaultEnabled == true`，
  > 初始化綁在首次啟動免責聲明的同意上。**本文件 §6 以下所有「預設關」的論證都是當時的建議，刻意原文保留**——
  > 決策變更的理由與逐點回應見 §6.0。
- **選項 B：不加任何第三方 SDK**，用 Apple 第一方管道（MetricKit + App Store Connect 分析 + Xcode Organizer 當機報告）加上 CI 端的 parser 冒煙測試來達成大部分目標。詳見 §8。

**我的建議**（撰寫當時，2026-09-06 上午）：先做 §8 的零 SDK 方案（成本最低、不動任何承諾），只有在確認「非要事件漏斗不可」時才走選項 A，而且一定是 opt-in 預設關（理由見 §6.1）。

**實際決策**（2026-09-06）：直接走選項 A，且**沒有採納「預設關」這個建議**。理由見 §6.0。

---

## 1. 量測目標（先有問題，才有事件）

事件是為了回答下面這些問題；回答不了任何一題的事件不埋。

| # | 想回答的問題 | 對應事件 | 為什麼需要 |
|---|---|---|---|
| G1 | 首次啟動有多少人走到填表、多少人送出、送出後結果分布（成功／三碼不符／未註冊／網路／官網異常）？卡在哪一步？ | `tutorial_begin`、`onboarding_validation_failed`、`login`、`login_failed`、`register_redirect`、`tutorial_complete` | 決定要不要做 Phase 2 註冊、Onboarding 文案是否需要改 |
| G2 | 一鍵登入（自動／手動）的成功率與耗時？失敗原因是使用者端（三碼錯）、網路、還是官網？ | `login`、`login_failed`（含 `trigger`、`duration_ms`） | PRD §10「一鍵登入 < 5 秒」的唯一可量測方式 |
| G3 | 任務清單抓取成功率？使用者大多停在哪一個狀態（未上傳／審核中／可兌換／已兌換）？ | `tasks_fetch` | 知道審核卡多久、活動期別推進到哪 |
| ~~G4~~ | ~~多少人走完 Apple 健康連結流程？連了健康卻從未上傳的比例？~~ | ~~`health_link_tap`、`health_link_result`~~ | **v1.1 起作廢**：健康連結功能已移除，這個問題不再存在 |
| G5 | 上傳漏斗：開啟上傳頁 → 選到圖 → 按確認 → 官網接受／拒絕？拒絕原因分布？ | `screen_view(upload)`、`upload_pick`、`upload_submit`、`upload_result` | 這是 App 的核心價值；官網拒絕率高代表要改說明文案 |
| G6 | 兌換漏斗：看到品項 → 點兌換 → 確認／取消 → 送出成功？各商家被選的比例？ | `redeem_options`、`redeem_select`、`redeem_cancel`、`redeem_submit`、`redeem_result` | 二次確認 alert 是否嚇跑人；商家熱門度 |
| G7 | OTP 驗證流程：簡訊發送失敗率、輸錯率、用罄率、券碼頁解析成功率、條碼畫不出來的比例？ | `voucher_open`、`voucher_otp_send`、`voucher_otp_verify`、`voucher_reveal`、`barcode_render_failed` | 這段官網最容易改版；也是使用者站在櫃檯最緊張的一段 |
| G8 | 「看截圖」有人用嗎？S3 圖片載入失敗率？ | `screenshot_view` | 決定要不要保留這個功能 |
| G9 | **官網改版了嗎？哪個頁面？從哪個 App 版本開始？**（最重要） | `site_error` ＋ Crashlytics 非致命錯誤 | 純刮頁 App 的存亡問題（審查風險文件的 4.0 條）；比任何漏斗都重要 |
| G10 | 多少人清除本機資料／存回個資？活躍度、版本分布、iOS 版本分布？ | `local_data_clear`、`profile_save` ＋ Firebase 自動事件 | 決定最低支援版本、判斷「清除」是不是被當登出用 |
| G11 | 多少人願意開啟匿名統計？ | `consent_granted` 對比 App Store Connect 安裝數 | 驗證同意 UX；注意分母只能用 ASC 的安裝數（§6.1） |

### 1.1 明確宣告「無法量測」的目標

- **（v1.1 起連資料來源都沒有了）PRD §2.3 North Star「每週達標上傳的連續週數」與輔助指標「從達標到上傳完成的中位時間 < 30 秒」不可量測。** 兩者都需要「達標」的時間戳，而達標是 HealthKit 步數／距離／分鐘推導出來的布林值——硬規則 2 直接擋掉。能量測的只有「上傳完成率」與「上傳耗時」，不能與達標綁在一起。
- **「多少人達標卻沒上傳」不可量測**，同上。只能退一步量「連結了健康卻沒上傳」（G4），而且 G4 量的是「走完授權流程」不是「授權成功」——HealthKit 依隱私設計不揭露讀取授權結果（`HealthKitReader.swift:30-33` 的註解），App 自己也不知道。

---

## 2. 全域設計原則（適用每一個事件與每一個 Crashlytics 鍵）

### 2.1 單一入口、型別即防線

- 所有 View／ViewModel 只呼叫一個 `Telemetry` facade，**禁止**直接 `import FirebaseAnalytics` / `FirebaseCrashlytics`（未來可用 CI grep 強制）。
- `Telemetry` 的參數型別只接受三種：`Int`、`Bool`、以及由 **`CaseIterable` enum 的 `rawValue`** 產生的字串。**沒有接受 `String` 的 overload。** 這是硬規則 1／3／4 的編譯期保證——不是靠開發者記得要遮罩。
- 既有 `Redact`（`Sources/SportsRewardsKit/Security/Redaction.swift`）保留頭尾字元（`A12●●●●●89`），那是 os_log 在裝置上可以接受的粒度；對第三方輸出來說**違反硬規則 1「遮罩片段也不行」**。因此 `Redact` 在遙測路徑上**完全不使用**——不是「用 `Redact.fully`」，而是根本沒有字串可以進來。

### 2.2 四道抑制條件（任一成立即 no-op，且每次呼叫時動態檢查）

| 條件 | 來源 | 說明 |
|---|---|---|
| 未同意 | 實作為 `DisclaimerConsent.hasAgreedToCurrentVersion == false`（原計畫寫的是 `UserDefaults["telemetryConsent"] != granted`） | **原計畫：預設關（§6.1）。實際：預設開，但初始化綁在免責聲明同意之後**（§6.0）。Info.plist 四個旗標仍為 `false`，作為冷啟動預設值，確保同意前連 `first_open` 與 app instance ID 都不會產生 |
| 示範模式 | `AppEnvironmentStore.isDemo` | 硬規則 5。**必須在每次 `log` 時讀取**，不能在 init 時快取——`HomeViewModel` 等 ViewModel 的 `configure()` 有 `guard self.auth == nil` 守衛，切進示範模式後 ViewModel 仍握著舊環境（`HomeView.swift:542` 的註解已指出這個坑） |
| 截圖模式 | `ScreenshotMode.isEnabled` | fastlane／XCUITest 跑出來的事件不該進正式資料 |
| Debug build | `#if DEBUG` | 開發機事件不進正式專案；若要看 DebugView，用另一個 Firebase 專案（`GoogleService-Info-Dev.plist`）＋ `-FIRDebugEnabled` |

示範模式除了 facade 層 no-op，`AppEnvironmentStore.enterDemo()` 應再呼叫 `Analytics.setAnalyticsCollectionEnabled(false)` 與 `Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)`，把 SDK 自動事件（`session_start`、`user_engagement`）也停掉；`exitDemo()` 依同意狀態恢復。雙保險的理由：facade 只能擋自訂事件，擋不住 SDK 自動事件。

> 另一個做法是把 `Telemetry` 當成 `AppEnvironment` 的一個服務注入，`DemoMode.makeEnvironment()` 給 `NoopTelemetry`，與 `Mock*Service` 同一套模式。概念上更乾淨，但會撞到上面說的「ViewModel 握著舊環境」問題，所以本文件建議 **shared facade ＋ 動態讀 `isDemo`**。

### 2.3 命名與限制（硬規則 6）

- 事件名、參數名：`snake_case`，字母開頭，≤ 40 字元；本文件所有名稱最長 28 字元（`onboarding_validation_failed`）。
- 不使用 `firebase_`／`google_`／`ga_` 前綴。
- 字串參數值全部是 enum rawValue，最長 20 字元左右，遠低於 100。
- 每事件參數最多 7 個，低於 25。
- 不設定任何 user property、不呼叫 `setUserID`。
- 沿用 Firebase 建議事件：`screen_view`、`login`、`tutorial_begin`、`tutorial_complete`。
- 關閉自動 `screen_view`（`FirebaseAutomaticScreenReportingEnabled = NO`）：SwiftUI 的 hosting controller 類名沒有意義，且 sheet 會亂觸發；改為手動在每個畫面 `.onAppear` 送。

### 2.4 「官網改版」與「session 過期」要分開

`URLSessionHTTPClient.getHTML` 會跟隨 redirect。session 過期時 `GET /member/tasks` → 302 `/login` → 200 登入頁 HTML → `TaskParser.parse` 丟 `parsing("no period-card…")`。**這不是官網改版，但錯誤型別一模一樣。** `/member/redeem/{uuid}`、`/member/voucher/{uuid}`、`/member/upload` 都有同樣的歧義。

設計上：
- `HomeViewModel.bootstrap()` 的第一次 `fetchTasks()` 失敗 → `tasks_fetch.reason = session_probable`，**不**送 Crashlytics 非致命錯誤。
- 只有在同一個 session 內剛完成 `login` 成功之後（`loadWeeklySummary(force: true)`，`source = post_login`）發生的 parse 失敗，才算官網改版訊號。
- 實作時建議在 Kit 加一個純函式 `SessionProbe.isLoginPage(html)`（例如偵測 `name="birthDate"` 欄位）讓分類更準；這只影響訊號品質，不影響資料安全，故不在本文件強制。

---

## 3. 事件清單

> 隱私檢核欄位以 R1–R6 代表六條硬規則。**R5（示範模式）與 R6（命名限制）由 §2.2／§2.3 的全域機制統一滿足**，每列只在有特殊之處時另註。

### 3.1 共用 enum 值域

| enum | 值 | 說明 |
|---|---|---|
| `Screen` | `onboarding_welcome` `onboarding_form` `home` `tasks` `wallet` `profile` `upload` `screenshot` `redeem` `vendor_intro` `voucher` | 對應 11 個 View（v1.1：`health` 移除、`vendor_intro` 新增） |
| `LoginTrigger` | `onboarding` `auto` `manual` | `OnboardingViewModel.submitTapped` ／ `HomeViewModel.bootstrap→performLogin(silent:true)` ／ `HomeViewModel.loginTapped` |
| `FailReason` | `invalid_credentials` `not_registered` `network` `site_status` `site_parse` `csrf_missing` `blocked_egress` `redirect_loop` `response_too_large` `session_probable` `unknown` | 由 `Telemetry.classify(error)` 從 `AppError` 映射；**只取 case，不取 associated value** |
| `Endpoint` | `access` `login` `logout` `tasks` `upload` `screenshot` `redeem` `voucher` `voucher_resend` `voucher_view` | 路徑**樣板**，永遠不含 UUID |
| `TaskStateClass` | `not_started` `open` `pending_review` `redeemable` `redeemed` `unknown` | 直接對應 `TaskState` |
| `Vendor` | `family_mart` `seven_eleven` `hilife` `pxmart` `other` | 沿用 `RedeemView.VendorLogo` 的名稱比對邏輯抽成共用；**不是** `vendorId` |
| `HostClass` | `gov_tw` `amazonaws` `other` | 給 `blocked_egress` 用；不送 host 本身 |
| `BarcodeFormat` | `code128` `qr` `mixed` `other` | 對應 `VoucherFigure.format`，只認已知兩種，其餘歸 `other` |

### 3.2 事件表

| # | 事件名 | 觸發時機（檔案 → 動作） | 參數（名稱：型別＝值域） | 目標 | 隱私檢核 |
|---|---|---|---|---|---|
| E1 | `screen_view` | 每個 View 的 `.onAppear`（11 個畫面） | `screen_name: Screen`、`screen_class: String`（固定為 Swift 型別名，如 `TasksView`，常數非變數） | G1–G8 通用 | R1 無欄位；R3 `upload/redeem/voucher/screenshot/vendor_intro` 畫面**不帶 taskID**、也不帶介紹頁路徑或商家名；R4 n/a<br>**v1.1**：`health` 畫面已移除，新增 `vendor_intro`（可兌換商品頁） |
| E2 | `tutorial_begin` | `OnboardingViewModel.startTapped()` | 無 | G1 | 無資料 |
| E3 | `onboarding_validation_failed` | `OnboardingViewModel.submitTapped()` 內 `validate()` 回非 nil | `field: enum = empty \| id_no \| birth_date \| phone` | G1 | R1：只說「哪個欄位格式不對」，**不送長度、不送第一碼、不送使用者輸入**；四種值都無法反推任何字元 |
| E4 | `login` | `AuthService.login` 回 `.success`（三個觸發點） | `method = "gov_500_form"`（常數）、`trigger: LoginTrigger`、`duration_ms: Int` | G1 G2 | R1：憑證完全不經過 facade；R3：不帶 cookie／JSESSIONID／CSRF |
| E5 | `login_failed` | 同上，回 `.invalidCredentials`／`.notRegistered` 或 throw | `trigger: LoginTrigger`、`reason: FailReason`、`net_code: Int`（僅 `reason = network`，值為 `URLError.code.rawValue`）、`duration_ms: Int` | G1 G2 G9 | R1：`invalid_credentials` 只是官網回 302→/login 的分類，不知道哪一碼錯；R3：`AppError.network(String)` 的字串是 `"code -1009"`，但仍**只取 enum case + 整數碼**，不取字串 |
| E6 | `register_redirect` | `OnboardingView.notRegisteredCard` 的「前往官網註冊」按下（`openURL`） | 無 | G1 | 無資料；開啟的是固定 URL |
| E7 | `tutorial_complete` | `OnboardingViewModel.finish()`（真實登入成功路徑） | 無 | G1 | R5：示範帳號進入的 `finish()` 會被 `isDemo` 閘門擋掉——注意 `enterDemoIfSentinel` 在 `finish()` **之前**已把 `isDemo` 設為 true，順序正確 |
| E8 | `tasks_fetch` | `TasksServicing.fetchTasks()` 的五個呼叫點回來時 | `source: enum = home_bootstrap \| home_refresh \| post_login \| tasks_tab \| wallet`、`outcome: enum = ok \| error`、`reason: FailReason`（error 時）、`period_count: Int`（0–14）、`current_period: Int`（1–14，`HomeViewModel.highlightedPeriod` 的 `index`）、`current_state: TaskStateClass`、`had_cache: Bool`、`duration_ms: Int` | G3 G9 | R1 無個資；R3：**不帶 `TaskPeriod.id`（UUID）**、不帶 `remainingText`／`uploadedAt`（官網文字）；`current_period` 是活動週次（全體使用者同一週）不是個人識別；`current_state` 是官網狀態機的 enum，屬 Usage Data。§2.4：`home_bootstrap` 的 parse 失敗歸 `session_probable` |
| ~~E9~~ | ~~`health_link_tap`~~ | **v1.1 已刪除**（健康連結功能整個移除，沒有這個按鈕了） | — | ~~G4~~ | — |
| E29 | `voucher_mark_used` | 使用者在券碼頁或券夾按下「標記為已使用」／「還原成未使用」 | `used: Bool`（標記或還原） | — | **這是 UI 動作，不是官網資料**：官網沒有「已使用」狀態，這個旗標完全由使用者自己在 App 內按出來，存在本機。R1 **不帶期別 UUID／期數／`voucherSummary`**（後者是官網原文＋通路品項） |
| ~~E10~~ | ~~`health_link_result`~~ | **從未實作，v1.1 起連前提都不存在**。當初的判斷是「授權結果仍是從 HealthKit API 取得的資訊」，屬 5.1.3(i) 要保護的範圍，因此刻意不做 | — | ~~G4~~ | — |
| E11 | `upload_pick` | `UploadViewModel.loadPickedImage()` 結束 | `outcome: enum = picked \| unreadable` | G5 | R4：**只送二元結果**。不送 `data.count`、`UIImage.size`、原格式（HEIC/JPEG）、`jpegDataUnder5MB` 迭代次數（迭代次數可反推檔案大小，屬衍生資訊）、`PhotosPickerItem.itemIdentifier`、EXIF |
| E12 | `upload_submit` | `UploadViewModel.confirmUpload()` 進入時 | `period_index: Int` | G5 | R3：`taskID` 不送（UploadView 有 `periodIndex` 可用）；R4：無檔案資訊 |
| E13 | `upload_result` | `confirmUpload()` 得到 `UploadResult` 或 throw | `outcome: enum = submitted \| window_closed \| csrf_missing \| site_rejected \| http_error \| network \| unknown`、`period_index: Int`、`duration_ms: Int` | G5 G9 | R1／R3：`UploadService.errorNotice(in:)` 抓到的官網 `.notice--error` **原文不送**（官網文字可能含日期、檔名回顯等），只分類成 `site_rejected`；`window_closed` 對應「頁面沒有 file 欄位」；R4：無檔案資訊 |
| E14 | `screenshot_view` | `ScreenshotView` 得到最終結果（`load()` 失敗、或 `AsyncImage` phase 定案） | `outcome: enum = ok \| no_id \| url_failed \| image_failed` | G8 G9 | R3：**S3 presigned URL、host、查詢字串一律不送**；`url_failed` = `screenshotImageURL` throw（含 `unexpectedResponse(0)` 沒 302 的情況） |
| E15 | `redeem_options` | `RedeemViewModel.load()` 結束 | `outcome: enum = ok \| empty \| error`、`reason: FailReason`（error 時）、`option_count: Int` | G6 G9 | R3：不送 `vendorId`／`itemId`／`taskID`；`option_count` 是官網目錄大小，非個人資料 |
| E16 | `redeem_select` | `VendorRow.onRedeem` → `pendingOption` 設值（確認 alert 出現） | `vendor: Vendor` | G6 | R3：`Vendor` 是由**公開商家名稱**分類出的 enum，不是官網識別碼；`itemName` 不送 |
| E17 | `redeem_cancel` | 確認 alert 按「取消」 | `vendor: Vendor` | G6 | 同上 |
| E18 | `redeem_submit` | `RedeemViewModel.confirmRedeem()` 進入 | `vendor: Vendor`、`period_index: Int` | G6 | 同上；`period_index` 由 `RedeemView.periodIndex` 取得（可為 nil → 省略參數） |
| E19 | `redeem_result` | `confirmRedeem()` 得到 `RedeemResult` 或 throw | `outcome: enum = submitted \| stayed_on_page \| http_error \| network \| unknown`、`vendor: Vendor`、`duration_ms: Int` | G6 G9 | R1／R3：`RedeemResult.message` 是 App 自己的靜態文案，仍不送（維持「無字串」原則） |
| E20 | `voucher_open` | `VoucherView` 出現 | `source: enum = wallet \| tasks \| redeem_result` | G7 | R3：不帶 taskID。來源由呼叫端傳入（`WalletView`／`TasksView`／`RedeemView.showVoucher`） |
| E21 | `voucher_otp_send` | `VoucherViewModel.sendOtp()` 結束 | `outcome: enum = ok \| error`、`reason: FailReason`（error 時）、`is_resend: Bool` | G7 G9 | R1：發送對象手機號在官網 session 裡，App 沒碰；不送官網回頁 |
| E22 | `voucher_otp_verify` | `VoucherViewModel.verify()` 得到 `VoucherOtpResult` 或 throw | `outcome: enum = success \| wrong_code \| exhausted \| failed \| error`、`remaining: Int`（0–3，僅 `wrong_code`） | G7 | R1：**OTP 值絕不進 facade**（型別上也進不來）；`VoucherOtpResult.failed(message)` 的 message 不送；`parseVerifyError` 回的官網文字不送（官網 OTP 頁文字可能含遮罩手機號「已發送至 09xx***」） |
| E23 | `voucher_reveal` | `VoucherViewModel.loadVoucher()` 結束 | `outcome: enum = ok \| parse_error \| error`、`figure_count: Int`（1–2）、`format: BarcodeFormat` | G7 G9 | R3：**`VoucherFigure.value`（券碼）、`Voucher.expiry`、`vendorName`、`notices` 一律不送**；`figure_count` 與 `format` 是券種結構（萊爾富兩段式）不是券碼 |
| E24 | `barcode_render_failed` | `VoucherFigureView` 拿到 `BarcodeGenerator.barcodeImage` 回 nil | `format: BarcodeFormat` | G7 G9 | R3：只送 format 分類。新的未知 format 出現 = 官網改版訊號，同時進 Crashlytics（§5.4） |
| E25 | `profile_save` | `ProfileViewModel.save()` 結束 | `outcome: enum = ok \| error` | G10 | R1：`draft` 不進 facade；Keychain OSStatus 走 Crashlytics 非致命（§5.4），不進 Analytics |
| E26 | `local_data_clear` | `ProfileView.clearLocalData()` **第一行**（在 `exitDemo`／清 Keychain 之前） | 無 | G10 | 事件送出後立刻執行 §6.4 的 `resetAnalyticsData()`；順序：先記錄、再重置 app instance ID、再把同意狀態設回未決 |
| E27 | `site_error` | `Telemetry.classify` 判定為 `site_parse`／`csrf_missing`／`site_status`／`blocked_egress`／`redirect_loop`／`response_too_large` 時（與各 `*_result` 事件並存） | `endpoint: Endpoint`、`kind: enum = parse \| csrf_missing \| unexpected_status \| blocked_egress \| redirect_loop \| response_too_large`、`status: Int`（HTTP 狀態碼；不明時 -1）、`host_class: HostClass`（僅 `blocked_egress`） | G9 | R3：endpoint 是樣板；`AppError.blockedEgress(host)` 的 host **不送**，只送 `HostClass`；`AppError.parsing(String)` 的字串（目前皆為靜態訊息）也不送，改用 endpoint＋kind；`AppError.responseTooLarge(Int)` 的位元組數**不送**（那是關於回應內容的測量值），只送 kind |
| E28 | `consent_granted` | 使用者在同意卡或設定頁開啟匿名統計，`setAnalyticsCollectionEnabled(true)` 之後立刻送 | `source: enum = prompt \| settings` | G11 | 唯一一個「同意後的第一個事件」；沒有對應的 `consent_revoked`（§4） |

### 3.3 Firebase 自動事件（不需埋，但要知道會有）

`first_open`、`session_start`、`user_engagement`、`app_update`、`os_update`、`app_exception`（Crashlytics 存在時 Analytics 會標記當機 session）。全部受 §2.2 的 SDK 層開關控制：同意前不會產生，示範模式中會被 `setAnalyticsCollectionEnabled(false)` 停掉。
另外 SDK 會自動附帶：app instance ID（隨機、可 reset）、裝置型號、iOS 版本、App 版本、語系、時區、由 IP 推導的國家／城市（Google 端不存 IP）。**不會有 IDFV**（§6.6 關閉）、**不會有 IDFA**（不連結 AdSupport）。

---

## 4. 刻意不埋的事件（不是漏掉，是故意的）

| 想埋的東西 | 為什麼會想埋 | 踩到 | 替代方案 |
|---|---|---|---|
| 今日步數、距離、運動分鐘、本週平均步數（`HealthSummary`、`weeklyAverageSteps`） | 「使用者平均走多少」很像產品洞察 | **R2** | 無。這是 Apple 明文禁止分享給第三方的資料 |
| `hasReachedGoal`、`GoalEvaluation.met`、「達標橫幅曝光」、達標百分比 `stepsPercentText` | 「達標率」是 PRD 的 North Star | **R2**（由 HealthKit 推導的布林值同樣是 HealthKit 衍生資料） | 無；§1.1 已宣告不可量測 |
| 達標 → 上傳的時間差、「達標當天是否上傳」 | PRD 輔助指標「< 30 秒」 | **R2**（需要達標時間戳） | 只量 `upload_submit → upload_result` 的耗時 |
| ~~`screen_view(health)` 帶 `state = unauthorized \| ready`~~ | 想知道健康頁多少人是已連結狀態 | **R2 邊界**：`ready` 意味著 `summary()` 成功回傳，是「查得到 HealthKit 資料」的間接訊號 | **v1.1 起不適用**：健康頁與整個功能都已移除 |
| HealthKit 查詢錯誤（`HKError`、`HealthKitReaderError`）送 Crashlytics 非致命 | 想知道健康讀取為何失敗 | **R2 邊界**：錯誤碼是「從 HealthKit API 取得的資訊」；`errorAuthorizationDenied` 等於揭露授權結果 | 不送。`HealthKitReader` 已把良性錯誤吞成 0，其餘 throw 只在本機顯示「讀取健康資料失敗」 |
| 身分證字號的任何片段：第一碼（縣市）、性別碼、長度、`Redact.idNo` 遮罩結果、雜湊 | 想做地區分布 | **R1**（明文列出連雜湊與遮罩片段都不行） | 無 |
| 出生年份／年齡區間 | 年齡分布 | **R1**（出生日期的衍生值） | 無 |
| 手機前三碼（電信商） | 電信商分布、簡訊到達率 | **R1** | 無 |
| `Profile` 任何欄位（含恆為空字串的 `name`／`email`／`nhiCardNo`）、`setUserID`、任何 user property | 跨裝置串接使用者 | **R1** | 本 App 沒有帳號概念，app instance ID 已足夠做匿名去重 |
| 期別 UUID（`TaskPeriod.id`）、`vendorId`／`itemId`、券碼 `VoucherFigure.value`、S3 presigned URL 或其 host、`JSESSIONID`／`LBSCookie`／`_csrf` | 除錯時想對照官網 | **R3** | endpoint 樣板 ＋ `period_index`（活動週次）＋ `Vendor` 分類 |
| `AppError.blockedEgress(host)` 的 host 字串 | 想知道官網把我們導去哪 | **R3**（可能是 presigned S3 host，內含 bucket 名） | `HostClass` 三分類 |
| `URLError` 原物件 `record(error:)` | 最省事 | **R3**：`URLError.userInfo[NSURLErrorFailingURLStringErrorKey]` 是**完整 URL，含期別 UUID** 與 `?_cookie_check=1` | §5.5：只取 `code.rawValue`，包進自訂 `TelemetryError` |
| `SecureLog` 橋接到 `Crashlytics.log()` 當 breadcrumb | 當機時想看前幾步 | **R3**：`URLSessionHTTPClient.send()` 的 debug 行印 `request.url?.path`（`/member/redeem/<uuid>`） | breadcrumb 只由 `Telemetry` facade 寫，內容 = 事件名＋enum 參數 |
| 官網回傳的任何文字：`.notice--error`、`parseVerifyError.message`、`Voucher.notices`、`remainingText`、`uploadedAt`／`reviewedAt`、`expiry`、原始 `vendorName`／`itemName` | 官網訊息最能說明失敗原因 | **R1／R3**：官網文字可能回顯遮罩手機號、日期、檔名；也超過 100 字元上限的風險 | 全部分類成 enum |
| 截圖檔名、位元組數、寬高、原格式、JPEG 壓縮迭代次數、EXIF、`PhotosPickerItem` 識別碼 | 想知道為什麼被官網拒 | **R4**（連衍生資訊都不行；迭代次數可反推檔案大小） | `upload_result.outcome = site_rejected` 計數 |
| 示範模式內的任何事件、`demo_mode_enter`／`demo_mode_exit` | 想知道審查員走了多遠 | **R5**；且示範模式使用者從未同意，閘門本來就會擋 | 無。審查進度看 App Store Connect 的審查狀態 |
| `consent_revoked`（關閉統計時送最後一個事件） | 想量 opt-out 率 | 違反同意的精神：使用者剛說「不要」，再送一筆等於沒聽到。對「隱私是核心賣點」的 App 尤其不該 | 從 DAU 曲線推估，或不量 |
| 錯誤的 `localizedDescription`／`String(describing: error)` | 通用錯誤字串 | **R1／R3**：`AppError.blockedEgress` 印 host，`URLError` 印 URL | `FailReason` enum |
| IDFA、AdSupport、ATT 提示、廣告個人化訊號 | Firebase 預設會拉 | 隱私標籤會變成「用於追蹤」；與 App 定位相反 | 只連結 `FirebaseAnalyticsWithoutAdIdSupport`（§6.6） |
| 精確位置、城市層級 | GA4 預設由 IP 推 | 非硬規則，但沒有任何目標需要 | GA4 property 關閉「精細位置與裝置資料蒐集」，只留國家 |

---

## 5. Crashlytics 設計

### 5.1 啟用與抑制

- Info.plist `FirebaseCrashlyticsCollectionEnabled = NO`；使用者同意後 `Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)`。
- 與 Analytics 共用同一個同意開關（不拆成兩個開關的理由見 §6.1）。
- 示範模式：`enterDemo()` 關閉、`exitDemo()` 依同意狀態恢復。**審查員在示範模式中當機不會被回報**——這是硬規則 5 與「審查員從未同意」的必然結果；補救方式是送審前自己在示範模式跑完整流程。
- 同意撤回時：`setCrashlyticsCollectionEnabled(false)` → `deleteUnsentReports()`。
- Debug build：不啟用（或指到 dev 專案）。

### 5.2 Custom keys（全部非個資；值為 enum rawValue、Int 或 Bool）

| key | 型別／值域 | 何時設定 | 為何安全 |
|---|---|---|---|
| `build_channel` | `debug \| testflight \| appstore` | 啟動時（由 `#if DEBUG` 與 receipt 路徑判斷） | 建置屬性 |
| `demo_mode` | Bool | `enterDemo`／`exitDemo` | 理論上回報時恆為 false（示範模式已關閉收集）；保留作為不變量檢查——若看到 true 代表閘門失效 |
| `screen` | `Screen` | 每次 `screen_view` | 與 E1 同一來源 |
| `onboarding_step` | `welcome \| form` | `OnboardingViewModel.step` 變更 | UI 狀態 |
| `session_state` | `profile_missing \| cached_only \| logged_in \| login_failed` | `HomeViewModel` 的 `isProfileComplete`／`hasLoggedIn`／`loginResultIsError` 變更 | 只說「有沒有登入」，不說是誰 |
| `tasks_cache` | `none \| fresh \| stale`（`TasksCache.canRefresh()` 反向） | `TasksCache.save/clear` 與讀取時 | 快取存在與否 |
| `current_period` | Int 1–14 | `tasks_fetch` 成功時 | 活動週次 |
| `current_state` | `TaskStateClass` | 同上 | 官網狀態機 enum |
| `last_endpoint` | `Endpoint` | 每次 HTTP 呼叫前（由 service 層透過 facade 設定） | 樣板，無 UUID |
| `last_status` | Int | 每次 HTTP 回應後 | 狀態碼 |
| `upload_stage` | `idle \| picked \| uploading \| done` | `UploadViewModel` 狀態變更 | UI 狀態；**不含檔案資訊** |
| `voucher_stage` | `needs_otp \| enter_code \| showing` | `VoucherViewModel.stage` 變更 | UI 狀態；**不含 OTP 與券碼** |
| `consent_source` | `prompt \| settings` | 同意時 | 同意來源 |

**禁止成為 custom key 的東西**（列出來讓後人不用再想一次）：`Profile` 任何欄位、`taskID`／UUID、`vendorId`／`itemId`、OTP、`VoucherFigure.value`、S3 URL、cookie／CSRF、`HealthSummary` 任何數值、`healthLink` 狀態（R2 邊界，Crashlytics 不需要它）、圖片資訊、`remainingText`、官網任何文字、`Analytics` 的 app instance ID（Crashlytics 自己有 installation UUID，不要手動串）。

### 5.3 Breadcrumbs（`Crashlytics.log()`）

- **只**由 `Telemetry` facade 在每次 `logEvent` 時同步寫一行 `"<event_name> k1=v1 k2=v2"`，內容與 Analytics 參數完全相同（同一套型別限制）。
- **不**橋接 `SecureLog`（§4 已說明 debug 行含 UUID 路徑）。`SecureLog.error` 目前的訊息雖然都是靜態字串，但橋接會成為未來貢獻者的陷阱，一律不做。
- 不 log 任何 HTTP body、HTML 片段、表單欄位。

### 5.4 非致命錯誤（`record(error:)`）

所有非致命錯誤都先包成自訂的 `TelemetryError`（`NSError` 子型別），domain 固定為下表四個之一，`code` 為 enum rawValue，`userInfo` **只放**下表列出的鍵（全部 enum／Int）。**絕不直接傳 `AppError`、`URLError`、`KeychainError`、`DecodingError` 原物件**。（`HKError` 已不存在——v1.1 移除了 HealthKit。）

每個 (domain, code, endpoint) 組合**每個 App session 只回報一次**，避免下拉刷新把同一個改版訊號洗成幾千筆。

| # | 來源（檔案 → 條件） | domain.code | userInfo | 不可附帶 | 為什麼最該知道 |
|---|---|---|---|---|---|
| N1 | `TaskParser.parse` throw（`/member/tasks` 回 200 但零張 `period-card`），**且** `source = post_login` 或 `SessionProbe` 判定不是登入頁 | `SiteDrift.tasks_no_cards` | `endpoint=tasks`、`status=200` | HTML 片段、HTML 長度 | 任務頁改版 = App 主功能全掛 |
| N2 | `TaskParser.mapState` 回 `.unknown`，或非 `notStarted` 的卡片抓不到 UUID | `SiteDrift.tasks_partial` | `endpoint=tasks`、`raw_state: String`（**例外允許**：值由 regex `[A-Z_]+` 擷取，只可能是官網狀態常數如 `NOT_UPLOADED`，結構上不可能夾帶個資；上限 40 字元）、`missing_id: Bool` | 卡片其他內容 | 官網新增狀態時最早的警報；`raw_state` 是本計畫唯一放行的非 enum 字串，理由是它本身就受 regex 約束 |
| N3 | `RedeemParser.parse` throw，或 `parseBlock` 對部分表單回 nil | `SiteDrift.redeem` | `endpoint=redeem`、`status`、`dropped_blocks: Int` | `vendorId`／`itemId`／`data-*` 屬性 | 兌換頁改版 |
| N4 | `CsrfParser.extract` throw（任何頁） | `SiteDrift.csrf_missing` | `endpoint`、`status` | HTML | 所有 POST 的前提；`/access` 是公開頁，這裡失敗一定是改版不是 session |
| N5 | `VoucherParser.parseView` throw；或 `verifyOtp` 回 200 但 `parseVerifyError` 找不到 `.notice--error`（regex 落空） | `SiteDrift.voucher_view` / `SiteDrift.voucher_notice` | `endpoint=voucher_view` 或 `voucher`、`status` | 券碼、通路、期限、notices | 使用者站在櫃檯時壞掉的那段 |
| N6 | `AuthService.login`：`/access` 或 `/login` 回非預期狀態或非預期 Location | `SiteDrift.auth` | `endpoint=access \| login`、`status`、`step: enum = access \| login` | Location 字串（可能含 query）、憑證 | 登入流程改版 |
| N7 | `URLSessionHTTPClient.getHTML` redirect 超過 5 跳（`unexpectedResponse(-1)`）、任何 endpoint 回 4xx／5xx | `SiteDrift.http` | `endpoint`、`status`、`kind: redirect_loop \| status` | URL、Location | 官網當機 vs 我們的問題，用 status 分 |
| N8 | `AppError.blockedEgress(host)` | `SiteDrift.egress` | `endpoint`、`host_class: HostClass` | host 字串 | 官網把流量導去新網域 = 改版 |
| N9 | `UploadService`：multipart POST 回非 200／302 | `SiteDrift.upload` | `endpoint=upload`、`status` | 檔案資訊、`.notice--error` 文字 | 上傳端點改版。**「頁面沒有 file 欄位」不是錯誤**（當期不可上傳是常態），只進 E13 `window_closed` |
| N10 | `KeychainStore` 丟 `KeychainError.unhandled(OSStatus)`；`Profile` JSON decode 失敗 | `Storage.keychain` / `Storage.profile_decode` | `op: save \| load \| clear`、`os_status: Int` | Profile 內容、`data` | `errSecInteractionNotAllowed(-25308)` 高頻代表有背景讀取時機問題 |
| N11 | `TasksCache.load` 的 `JSONDecoder` 失敗（目前被 `try?` 吞掉，需加 hook） | `Storage.cache_decode` | 無 | 快取內容（雖不含個資，但沒必要） | App 更新後 `TaskPeriod` 結構變動的回歸訊號 |
| N12 | `BarcodeGenerator.barcodeImage` 回 nil | `Render.barcode` | `format: BarcodeFormat` | `value` | 新券種 |
| — | HealthKit 任何錯誤 | **不記錄** | — | — | R2 邊界，§4 |
| — | `UploadViewModel.loadPickedImage` 失敗 | **不記錄** | — | — | R4：它是關於使用者檔案的錯誤；只進 E11 |
| — | `AppError.network` | **不進 Crashlytics**（太吵） | — | — | 只進 Analytics `login_failed`／`*_result` 的 `reason=network` + `net_code` |

### 5.5 錯誤訊息衛生（對照既有 `Redact`／`SecureLog`）

1. **型別限制優先於遮罩**：`Telemetry` 與 `TelemetryError` 的 API 不接受 `String`（唯一例外 N2 的 `raw_state`，由 regex 保證字元集）。`Redact` 不參與遙測——它的頭尾保留設計適合裝置端 os_log，不符合 R1 對第三方的要求。
2. **不傳原始 Error**：`URLError.userInfo` 含完整失敗 URL；`AppError.blockedEgress` 的 associated value 是 host；`DecodingError` 的 `debugDescription` 含欄位名與 coding path（Profile 的欄位名本身不是個資，但沒必要）。一律 `switch` 成 enum 再包。
3. **不傳 `localizedDescription`**、不 `String(describing:)`、不 `"\(error)"`。
4. **官網文字一律視為不可信輸入**：`UploadService.errorNotice`、`VoucherParser.parseVerifyError().message`、`Voucher.notices`、`TaskPeriod.remainingText/uploadedAt/reviewedAt`、`RedeemOption.vendorName/itemName`、`Voucher.vendorName/itemName/expiry`——只能經分類器變成 enum。
5. **Crashlytics 自動蒐集的東西**（無法關閉、需寫進隱私政策）：堆疊、執行緒名、裝置型號、OS、記憶體／磁碟餘量、方向、App 版本、installation UUID、當機時間。堆疊不含 Swift 字串常值內容；App 內沒有把個資放進型別名或函式名的地方。
6. **`SecureLog` 維持現狀**，不做任何橋接；`Crashlytics.log()` 只由 facade 呼叫。

---

## 6. 使用者控制

### 6.0 決策變更公告（2026-09-06）：**「預設關（opt-in）」這個建議沒有被採納**

**本節以下的 §6.1 是撰寫當時的建議，論證原文保留，不做刪改。** 但實際出貨的決策不同，這裡先講清楚，避免有人照 §6.1 去改程式碼或文案。

**實際出貨的設計**：

- `Telemetry.defaultEnabled == true`——**同意之後預設開啟**。
- 真正的保障不是預設值，而是**初始化時機**：首次啟動先擋一張必須主動勾選的免責聲明（`App/Sources/Views/DisclaimerView.swift`），
  畫面上明寫「App 會把匿名的操作紀錄與當機報告送給 Google Firebase」，勾選文字涵蓋「並同意傳送不含個資的匿名使用統計（可隨時關閉）」。
  使用者按下「同意並開始使用」時，`DisclaimerConsent.record()` 才呼叫 `Telemetry.configure()`——**那是整支 App 第一次執行 Firebase 程式碼的時機**。
- `configure()` 三道前置條件，缺一不初始化：尚未同意免責聲明／使用者關掉開關／示範模式。
- 使用者可隨時到「我的資料 › 安全與隱私 › 傳送匿名使用統計」關閉；「立即清除本機資料」會重置同意紀錄與遙測偏好。
- **正確的敘述是「先告知 → 主動同意 → 預設開啟 → 隨時可關」，不是 opt-in。** 對使用者而言這確實是「預設會送」，
  只是送之前一定先告知並取得同意。不要用「仍然是 opt-in」這種文字遊戲。

**為什麼改**：§6.1 第 5 點自己就寫了代價——「樣本會偏向願意分享的人」。實務上更嚴重：**預設關 + 開關藏在設定頁第三層，等於幾乎沒有人會打開**，
當機報告與非致命錯誤都拿不到有意義的樣本，而那正是 §1 加遙測的唯一理由（官網改版時最早的警報）。
與其保住一個「技術上是 opt-in」的說法卻拿不到資料，選擇把揭露拉到 App 的必經入口、由使用者在看得到說明的情況下主動同意，再預設開啟。

**§6.1 五點理由，逐點回應**：

| §6.1 的理由 | 現在還成立嗎 | 說明 |
|---|---|---|
| 1. 承諾的絕對性——預設開的話，「不會提供給任何第三方」在使用者看到開關之前就已經是假的 | **論證成立，但被「移動揭露點」解掉了** | 這一點的真正內容是「**使用者不該在讀到說明之前就開始被收集**」——它反對的是「無揭露就收集」，不是「預設開啟」本身。實作把揭露點從設定頁移到**進 App 必經的阻斷式畫面**，並把初始化綁在那個畫面的同意上，所以「使用者看到之前資料已經送出去」這件事仍然不會發生。§0 那幾處文案已全部改寫。 |
| 2. 審查曝險——預設關讓 Review Notes 可以寫「任何第三方 SDK 在使用者明示同意前零連線」 | **這句話仍然為真，而且是現在唯一的辯護點** | 「明示同意前零連線」照樣成立，只是「明示同意」的位置從設定頁的 Toggle 換成免責聲明的勾選。**但有一句舊承諾被推翻**：「示範模式下對 Google 零連線」不再成立——免責聲明擋在 Onboarding 之前，示範模式在 Onboarding 之後，所以審查員是「先同意（Firebase 於此初始化）→ 才進示範模式」。已在 `docs/release/review-notes.md` §2／§5b 主動告知審查員。 |
| 3. Crashlytics 不比 Analytics 無害，所以不拆兩個開關 | **完全成立，已照做** | 仍然只有一個總開關同時管 Analytics 與 Crashlytics。這一點沒有因為預設值改變而動搖。 |
| 4. 開源可稽核——「預設有沒有送」要能用一行設定證明 | **成立，但證明的對象換了** | 現在要能用程式碼證明的不是「`defaultEnabled == false`」，而是「`DisclaimerConsent.record()` 裡有 `Telemetry.configure()`，而且那是唯一的初始化入口」。這一樣是 grep 得到的一行。Info.plist 四個旗標仍為 `false`，意義改成「冷啟動預設值／還沒 `configure()` 就絕不收集」。 |
| 5. 代價：安裝數分母得從 App Store Connect 拿、樣本偏向願意分享的人、審查員的當機不會回報 | **第 1、3 項不變；第 2 項正是改動的原因** | 分母仍建議從 App Store Connect 拿（`first_open` 發生在同意當下，不是安裝當下）。審查員的當機仍然收不到（示範模式擋住）。而「樣本偏向願意分享的人」這個代價在舊設計下大到讓整個方案失去意義——這就是改成預設開啟的動機。 |

**新增的代價（誠實記錄）**：對使用者而言這是「預設會送」，比舊設計更侵入。可主張的補償只有一個，而且必須真的做到：
**揭露被移到使用者一定看得到的位置，並且在同意之前 Firebase 一行程式碼都不執行。** 這兩件事只要有一件被改壞，這個設計就沒有任何辯護空間。

---

### 6.1 預設值建議：**預設關（opt-in）**，一個總開關同時管 Analytics 與 Crashlytics

> **⚠️ 這一小節是 2026-09-06 撰寫當時的建議，**後來沒有被採納**（見 §6.0）。原文保留以維持決策軌跡，
> **不要照這裡的內容改程式碼或對外文案。**

理由：

1. **承諾的絕對性**。§0 那六處文案是「不會提供給任何第三方」這種沒有例外的句子，也是 Onboarding 第一屏就講的價值主張。預設開的話，這些句子在使用者第一次啟動、還沒看到任何開關之前就已經是假的——Firebase 在 `configure()` 當下就產生 app instance ID 並送 `first_open`。
2. **審查曝險**。`docs/app-review-risk.md` 已把 5.1.1(ix)（政府敏感個資）與 5.1.3(i)（HealthKit 不得分享第三方）列為最高風險；一個帶 HealthKit entitlement 的 App 裡出現 Google SDK，審查員會直接問「健康資料有沒有進 Firebase」。預設關讓 Review Notes 可以寫「任何第三方 SDK 在使用者明示同意前零連線」，這句話比「我們有過濾」有說服力得多。
3. **Crashlytics 不比 Analytics 無害**。當機報告帶 installation UUID、裝置指紋、以及 custom keys／breadcrumbs 描述的 App 狀態；「當機報告預設開、統計預設關」的常見做法，在「不會提供給任何第三方」的承諾下一樣站不住。所以不拆兩個開關——拆了只會讓設定頁多一個要解釋的東西。
4. **開源可稽核是賣點**。任何人 grep 到 `FirebaseApp.configure()` 都會問「預設有沒有送」；預設關 + Info.plist 硬關（§6.6）讓答案可以用一行設定證明。
5. **代價要講清楚**：opt-in 表示 `first_open` 只在同意當下才發生，**安裝數的分母得從 App Store Connect 拿**；樣本會偏向願意分享的人；示範模式與審查員的當機不會回報。這些都是本 App 定位下可以接受的代價。

### 6.2 同意流程

> **⚠️ 實作與本節不同（2026-09-06）**：實際做的是**擋在 Onboarding 之前的阻斷式免責聲明**（`DisclaimerView`），
> 必須主動勾選才能繼續，而且使用統計只是它三件事之中的一項（另兩項是「這是非官方工具」「活動權益以官方公告為準」）。
> 沒有「不用了」這個分支——不同意就進不了 App，同意即代表同意傳送匿名統計（可隨時關閉）。
> 本節原文保留以維持決策軌跡。實作上被推翻的關鍵判斷是下面第一點的「不阻擋操作」與「不放在身分證表單之前」：
> 最後的結論相反——**正是因為要在使用者輸入政府個資之前把話講完**，這個畫面才必須擋在最前面。

- **時機**：`tutorial_complete` 之後、第一次進 Home 時，以**不阻擋操作的卡片**（非 alert、非全螢幕）顯示在 `loginCTA` 下方。**不放在身分證表單之前**——在使用者輸入政府個資的當下疊一個「要不要分享統計」是最糟的時機。
- **只問一次**。不選視同拒絕；之後只能從設定頁改。
- **建議文案**（繁中、對齊既有語氣）：
  - 標題：「幫這支 App 變得更好？」
  - 內文：「你可以選擇分享**匿名**的使用統計與當機回報（透過 Google Firebase）。只會送出「按了哪個按鈕、哪一步失敗、App 有沒有當機」這類資訊；**絕不包含**你的身分證號、生日、手機、Apple 健康的任何數據、你上傳的截圖或券碼。預設是關閉的，隨時可在「我的資料 › 安全與隱私」改變。」<br>（**已作廢**：最後一句與實作不符。實際文案見 `DisclaimerView`，並以「同意後預設開啟、可隨時關閉」表述。）
  - 按鈕：「好，分享匿名統計」／「不用了」
  - 連結：「看看會送出什麼」→ 開啟本文件（或隱私政策頁對應段落）。
- 選「好」→ `consent = granted` → `setAnalyticsCollectionEnabled(true)`、`setConsent(analyticsStorage: granted, adStorage/adUserData/adPersonalization: denied)`、`setCrashlyticsCollectionEnabled(true)` → 送 E28。
- 選「不用了」→ `consent = denied`，什麼都不做（沒有事件）。

### 6.3 設定頁

- 位置：`ProfileView.securitySection`，插在「本機資料」列與「原始碼」列之間，沿用 `iconBox` 列樣式。
- 列標題：「匿名使用統計與當機回報」；右側 `Toggle`。
- 副標（關閉時）：「已關閉 · 不會有任何資料送到 Google」；（開啟時）：「只送匿名操作事件與當機報告 · 絕不含個資、健康數據、截圖、券碼」。<br>（**注意**：關閉時的副標要能對得上「Firebase 沒有反初始化」這個事實——本次執行期間 SDK 仍在記憶體裡，只是收集旗標已關、安裝編號已重置、未送報告已刪。實際 App 內文案由 `ProfileView.swift` 決定。）
- 列下方一行小字連結「查看完整清單」→ 本文件。
- 「本機資料」列的副標「無伺服器 · 未同步 iCloud · 不寫入紀錄檔」維持為真（Firebase 不是 App 的伺服器，也不碰個資），但頁首 `privacyBanner` 第一點需改寫（§6.5）。

### 6.4 關閉／清除時的動作

| 動作 | 要做的事 |
|---|---|
| Toggle 關閉 | `consent = denied` → `setAnalyticsCollectionEnabled(false)` → `Analytics.resetAnalyticsData()`（app instance ID 重生） → `setCrashlyticsCollectionEnabled(false)` → `deleteUnsentReports()` |
| 「立即清除本機資料」 | 先送 E26 → 執行上一列全部 → `consent = undecided`（回到 Onboarding 後會再問一次，因為這等同重新安裝） |
| 進入示範模式 | 收集暫停（§2.2），`consent` 不動 |
| 離開示範模式 | 依 `consent` 恢復 |

### 6.5 必須同步修改的文案與文件（選項 A 的前置工作，缺一不可）

| 檔案 | 要改什麼 |
|---|---|
| `App/Sources/Views/ProfileView.swift:80` | 「也不會提供給任何第三方」→「除非你主動開啟下方的匿名統計，否則不會有任何資料送到第三方；即使開啟，也絕不包含個資、健康數據、截圖與券碼」 |
| `App/Sources/Views/ProfileView.swift:267` | 頁尾「只連 500.gov.tw」→「只連 500.gov.tw（匿名統計開啟時另連 Firebase）」或拿掉這句 |
| `App/Sources/Views/HomeView.swift:227`、`OnboardingView.swift:113` | 「不會上傳雲端」仍為真（指個資），可保留；「不會寫入紀錄檔」建議改為「不會把個資寫入任何紀錄」 |
| `README.md:56` | 「零第三方相依 … 無任何 analytics 或 crash SDK」→ 如實描述 Firebase 存在、**初始化綁在免責聲明同意之後（同意後預設開啟）**、白名單例外網域清單 |
| `docs/PRD.md §8.2、§8.3、§2.3` | 第三方 SDK 禁令改為「僅限**已取得免責聲明同意**且不含個資／健康資料」；白名單加註例外；反指標定義更新 |
| `docs/TASKS.md:5` | 硬約束「只連 500.gov.tw」加註 |
| `docs/copy-candidates.md §5` | 信任文案同步 |
| `docs/app-review-risk.md` Review Notes 段 | 新增第五點：「第三方 SDK：Firebase Analytics／Crashlytics，**首次啟動的免責聲明先揭露，使用者按下同意才初始化，同意後預設開啟、可隨時關閉**；絕不含 HealthKit 資料與個資（附本文件連結）」。**另須主動說明審查員的實際時序**（先同意 → Firebase 初始化 → 才進示範模式）。 |
| 隱私政策 `privacy.html` | 新增 Firebase 段：蒐集項目、用途、Google 為處理者、資料傳到美國、保存期限、如何關閉 |
| App Store Connect「App 隱私」 | §7 |

### 6.6 Info.plist／建置設定

| 鍵 | 值 | 目的 |
|---|---|---|
| `FirebaseDataCollectionDefaultEnabled` | `NO` | 所有 Firebase 產品預設不收集 |
| `FIREBASE_ANALYTICS_COLLECTION_ENABLED` | `NO` | 可在執行期打開（**不要用** `_DEACTIVATED`，那是永久關閉） |
| `FirebaseCrashlyticsCollectionEnabled` | `NO` | 同上 |
| `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED` | `NO` | app instance ID 不與 IDFV 綁定 |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE`／`_AD_USER_DATA`／`_AD_PERSONALIZATION_SIGNALS` | `NO` | 關閉所有廣告相關訊號 |
| `FirebaseAutomaticScreenReportingEnabled` | `NO` | 手動 `screen_view` |
| `FirebaseAppDelegateProxyEnabled` | `NO` | 本 App 無推播，不需要 swizzling |
| SPM 產品 | 只加 `FirebaseAnalyticsWithoutAdIdSupport` ＋ `FirebaseCrashlytics` | 不連結 AdSupport；不加 Performance／Messaging／InAppMessaging／RemoteConfig |
| `PrivacyInfo.xcprivacy`（App 層） | `NSPrivacyTracking = false`；`NSPrivacyCollectedDataTypes` 依 §7 | Firebase SDK ≥ 10.22 自帶各自的 manifest 與 required-reason API 宣告 |
| Crashlytics dSYM 上傳 | Run Script phase；`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` | 否則堆疊無法符號化 |
| `GoogleService-Info.plist` | 進 repo 沒問題（本來就是公開設定），但在 GCP 主控台**限制 API key 的 bundle ID**；開源專案要有人灌假事件的心理準備 | |

Firebase 主控台端：GA4 資料保留設最短（2 個月）、關閉 Google Signals、關閉廣告個人化、關閉「精細位置與裝置資料蒐集」（只留國家層級）、不開 BigQuery 連結（避免原始事件外流到另一個系統）。

---

## 7. 對 App Store「App 隱私」問卷的影響

前提：§6.6 全部做到（無 IDFV、無 IDFA、無 userID、無 user property）。

| 資料類型 | 是否蒐集 | 連結到使用者身分？ | 用於追蹤？ | 用途 | 來源 |
|---|---|---|---|---|---|
| Identifiers › **Device ID** | **是** | 否（app instance ID／installation UUID 為隨機、可重置、不與 IDFV 綁定、不與任何帳號串接） | 否 | Analytics、App Functionality | Firebase Analytics app instance ID、Firebase Installations ID、Crashlytics installation UUID |
| Usage Data › **Product Interaction** | **是** | 否 | 否 | Analytics | §3 全部事件、自動事件 |
| Diagnostics › **Crash Data** | **是** | 否 | 否 | App Functionality | Crashlytics 當機報告 |
| Diagnostics › **Other Diagnostic Data** | **是** | 否 | 否 | App Functionality | 非致命錯誤、custom keys、breadcrumbs |
| Diagnostics › Performance Data | 否 | — | — | — | 不加 Performance SDK |
| Usage Data › Other Usage Data | 建議勾「是」以保守 | 否 | 否 | Analytics | `redeem_select.vendor`（商家偏好）可被視為此類 |
| Location › Coarse Location | **依 Google 官方對照表填寫**（實作時再核對最新版）：GA4 由 IP 推導國家／城市，不存 IP；Google 的 App Store 資料揭露表歷來將此列為「不需宣告」，但關閉精細位置後只剩國家層級，更好辯護 | — | — | — | GA4 伺服器端 |
| Health & Fitness | **否（維持 Not Collected）** | — | — | — | 硬規則 2 的成果；這一格不能變 |
| Contact Info、Sensitive Info、User Content（照片）、Financial | 維持現有立場（`app-review-risk.md` 第 8 點：身分資料屬「與 500.gov.tw 分享」如何填由該文件決定） | — | — | — | Firebase **不**取得任何這些資料，本計畫不改變這幾格 |

- **Tracking**：一律「否」。不連結 AdSupport／ATT、`NSPrivacyTracking = false`、不與資料仲介分享、事件不跨 App／網站串接。不需要 ATT 提示。
- **「連結到使用者」的辯護**：Apple 定義「linked」為可與使用者身分連結；本 App 無帳號、不設 userID、Device ID 可由使用者重置（關閉開關或清除資料；「立即清除本機資料」還會一併重置免責聲明的同意紀錄）、IDFV 關閉。Firebase 官方對照表對 Analytics／Crashlytics 也是以「Not linked」為預設建議。
- **Review Notes** 要主動寫：「**在使用者同意首次啟動的免責聲明之前，Firebase 一行程式碼都不執行**；同意之後也不含 HealthKit 資料（見 5.1.3）」——這是把 5.1.3(i) 風險從「解釋」變成「可驗證」的關鍵一句。（原句寫的是「Firebase 預設停用」，那已經不正確。）

---

## 8. 零 SDK 替代方案（選項 B）

若最終目標排序是 G9（官網改版）> 當機 > 漏斗，其實可以不加任何第三方：

| 目標 | 零 SDK 做法 | 缺點 |
|---|---|---|
| 當機 | **MetricKit**（`MXCrashDiagnostic`，iOS 14+；第一方、不需同意、不改隱私標籤）＋ **Xcode Organizer** 的當機報告（來自在 iOS 設定「與 App 開發者分享」勾選的使用者） | 延遲最多 24 小時；沒有 custom keys／breadcrumbs；非致命錯誤沒地方放 |
| 活躍度、版本、留存 | **App Store Connect › 分析**（同樣來自 iOS 層級選擇分享的使用者） | 無自訂事件、無漏斗 |
| **官網改版** | **CI 每日冒煙測試**：`GET https://500.gov.tw/registrant/access` 與 `/login` 是公開頁，可直接跑 `CsrfParser` 與登入頁結構檢查；會員頁（`/member/*`）需登入，只能靠 `Tests/Fixtures` 回歸 ＋ 使用者回報 | 抓不到會員頁改版；但會員頁改版通常伴隨公開頁改版 |
| 漏斗 | 無 | 這是唯一真的需要 SDK 的目標 |
| 非致命錯誤 | 本機累計計數，在「我的資料」提供「匯出診斷資訊」讓使用者**主動**貼到 GitHub issue（PRD §8.2 說的「本機化」） | 依賴使用者主動 |

這條路完全不動 §0 的六處承諾、不加同意 UI、不改隱私標籤、示範模式不用特別處理。**建議先走這條**，累積一個活動週期（14 週）的使用者回報後，再評估漏斗資料是否值得付出 §6.5 那整張表的代價。

---

## 9. 若採選項 A：實作待辦（不在本任務範圍，僅供排程）

1. `Telemetry` facade（App target）：`logEvent(_:params:)`、`setKey`、`recordNonFatal`、四道抑制條件、`classify(error, endpoint:)`。
2. `TelemetryParam` 型別（`.int`／`.bool`／`.enumCase`），**無 `String` case**；單元測試驗證 `AppError.blockedEgress("x")`、`URLError` 經 `classify` 後 userInfo 不含任何非 enum 字串。
3. `Vendor`、`Endpoint`、`HostClass`、`BarcodeFormat`、`FailReason` enum（可放 Kit）。
4. `SessionProbe.isLoginPage(html)`（Kit，純函式，加 fixture 測試）。
5. `TasksCache.load` 解碼失敗的 hook（N11）。
6. `AppEnvironmentStore.enterDemo/exitDemo` 加 SDK 開關切換；單元測試：示範環境下 `Telemetry` 為 no-op。
7. 同意卡（Home）＋ 設定列（Profile）＋ `clearLocalData` 順序調整。
8. §6.5 文案與文件全部更新；`privacy.html` 新段；App Store Connect 隱私問卷；Review Notes。
9. Info.plist／`project.yml` 鍵、SPM 相依、dSYM 上傳、`PrivacyInfo.xcprivacy`。
10. CI：grep 禁止 `import FirebaseAnalytics`／`FirebaseCrashlytics` 出現在 `Telemetry` 以外；grep 禁止 `Analytics.logEvent(` 直接呼叫；grep 禁止 `localizedDescription` 出現在 `Telemetry` 路徑。
11. 送審前在示範模式手動跑完整流程（因為示範模式的當機不會回報）。
