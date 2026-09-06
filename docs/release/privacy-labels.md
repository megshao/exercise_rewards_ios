# App 隱私問卷（App Privacy）逐項建議答案 — Sports Rewards 1.0

適用於 App Store Connect →「App 隱私」→ 資料類型問卷。
每一項都附「依據」，指向實際的檔案或行為，方便你自己覆核，也方便日後程式碼改動時回頭比對。

> **2026-09-06 大改**：本 App 加入了 **firebase-ios-sdk 12.18.0**（Analytics + Crashlytics），
> 這份文件原先「Identifiers/Usage Data/Diagnostics 全部 Not Collected」的結論**已經作廢**。
> 現行答案見 §1。**Health 與 Fitness 仍然是 Not Collected**，理由見 §2——那一格沒有變，而且不能變。
>
> **2026-09-06 再修訂（遙測預設值變更）**：`Telemetry.defaultEnabled` 由 `false` 改為 `true`，
> 並把初始化時機綁在**首次啟動的免責聲明同意**上（`DisclaimerConsent.record()` → `Telemetry.configure()`）。
> 對外的正確敘述從「預設關閉（opt-in）」改成「**先告知 → 使用者主動同意 → 之後預設開啟 → 隨時可關**」。
> **§1 的逐項答案（Collected / Linked / Tracking / Purpose）一格都沒有變**，理由見前提 C。變的只有前提 C 的論述、
> §4 第 6 點的政策文字、§5 的觸發點與 §6 的事實基準。

---

## 0. 先講兩個判斷前提（最關鍵的兩題）

### 前提 A — Apple 對「蒐集（Collect）」的定義

> Apple：「Collect」指把資料**傳出裝置**，且你或你的第三方夥伴能存取的時間**超過即時處理該請求所需**。

所以：**只存在裝置本機、從未離開裝置的資料，一律是 Not Collected。** 這一點仍然讓多數項目歸零。（健康資料則更單純——本版根本不讀取，見 §2。）
（但它不再讓「絕大多數」項目歸零：2026-09-06 加入的遙測確實會把匿名資料傳出裝置，而且在使用者同意免責聲明之後**預設就是開的**，見前提 C。）

### 前提 B — 資料送到 `500.gov.tw` 算不算「與第三方分享」？

**結論：算，要如實揭露。**

理由與取捨：
- 嚴格照字面看，開發者**沒有自建伺服器、拿不到任何身分資料**（`docs/PRD.md §4.3`、`README.md` 威脅模型「個資外洩」列），而 `500.gov.tw` 是**使用者自己的帳號所在網站**、由使用者主動觸發登入才送出。照這個讀法，理論上可以主張連「蒐集」都不成立。
- 但 Apple 的問卷是**以使用者視角**描述「這支 App 會把我的什麼資料送出去」，不是只描述開發者拿到什麼。身分證號與手機號碼**確實離開了裝置**。
- 而且這條也不能走 Apple 的「選擇性揭露（Optional Disclosure）」豁免——豁免要求「蒐集只發生在非主要功能、且對使用者為選填」，但登入送出三碼**正是本 App 的主要功能**，不符合。
- 本專案的既定立場也是如此（`docs/app-review-risk.md` 降險清單第 8 條：「資料送 500.gov.tw 屬『與第三方分享』，隱私標籤如實勾」）。

**風險取捨**：多勾的代價只是商店頁面的隱私卡片多幾列，並要在隱私權政策把 `500.gov.tw` 寫清楚；少勾的代價是「隱私標籤不實」，可能導致下架與 metadata 違規。**選多勾。**

### 前提 C — 遙測是「同意後預設開啟」，能不能因此不申報？

**結論：不能。要照樣申報。結論與 2026-09-06 第一版相同，但理由要更新。**

Apple 有一條「選擇性揭露（Optional Disclosure）」豁免，四個條件要同時成立。**在舊的「預設關閉（opt-in）」設計下就已經過不了兩條**：

- 「使用者**每次**都主動選擇提供該筆資料，且提供時有明顯的請求介面」——匿名事件是在背景自動送出的，使用者只表示過一次同意，不是每次主動提供。
- 「蒐集只發生在非主要功能的、不常見的情境」——遙測橫跨整個 App 生命週期。

**改成「同意後預設開啟」之後，這條路只會更走不通，不會更好走。** 舊版至少還能主張「使用者必須自己去撥開關」；
現在使用者按下的是一個涵蓋多件事的概括同意，之後就自動開始收集，離「每次主動提供」更遠。
所以豁免在改動前後都不成立——**結論不變是因為它本來就不成立，不是因為改動沒有影響。**

**「實際會蒐集到多少比例」的討論也要跟著改。** 舊版這裡寫的是「問卷問的是有沒有**可能**蒐集，不是**預設**有沒有蒐集」——
那句話在舊設計下是拿來擋「反正幾乎沒人會打開，可不可以不勾」這個念頭的。現在那個念頭連前提都沒有了：
**同意免責聲明是進入 App 的必經步驟，同意之後遙測預設就是開的，所以實務上「絕大多數使用者都會被蒐集」。**
換句話說，改動後標籤的申報義務只有更明確，沒有任何可以少勾的空間。

少勾的代價是隱私標籤不實（可能下架 + metadata 違規），多勾的代價只是商店頁多幾列 Not Linked。**選多勾。**

### 前提 D — 誰是「第三方夥伴」

**Google LLC**（Firebase Analytics / Crashlytics）現在是本 App 的第三方夥伴之一。
資料存放於 Google 位在美國的伺服器，適用 Firebase 的資料處理條款。
另一個是 `500.gov.tw`（前提 B）。**開發者自己仍然沒有任何伺服器。**

### 問卷第一題

> 「你或你的第三方夥伴會從這個 App 蒐集資料嗎？」→ **會（Yes）**

（在加入 Firebase 之前，這一題還有「極簡讀法選不會」的空間；現在沒有了——Google 確實會收到資料。）

---

## 1. 逐項答案總表

圖例：**Collected?** = 是否蒐集｜**Linked?** = 是否與使用者身分連結｜**Tracking?** = 是否用於追蹤（跨 App/網站的廣告或資料掮客用途）

| 資料類別 | 資料類型 | Collected? | Linked? | Tracking? | Purpose | 依據 |
|---|---|---|---|---|---|---|
| **Contact Info** | Name 姓名 | **No** | — | — | — | App 從不收集姓名。`OnboardingView.swift` 註解明寫「主表單只收 3 欄，`name`/`email`/`nhiCardNo` 維持空字串，App 從不收集」 |
| | Email Address | **No** | — | — | — | 同上，Email 欄位已從 UI 移除 |
| | Phone Number 手機號碼 | **Yes** | **Yes** | No | App Functionality | 登入三碼之一，登入時由裝置直送 `500.gov.tw`（`AuthService.login`，`docs/PRD.md §6.2`） |
| | Physical Address | No | — | — | — | 從不收集 |
| | Other User Contact Info | No | — | — | — | 從不收集 |
| **Health & Fitness** | Health 健康 | **No** | — | — | — | 見下方 §2。本版**完全不讀取健康資料**，無 entitlement、無權限提示、無讀取路徑 |
| | Fitness 健身 | **No** | — | — | — | 同 §2。步數／距離／運動時間只在 `HealthView`、`HomeView` 本機顯示，`Telemetry` 的封閉列舉裡沒有任何成員能帶這些值 |
| **Financial Info** | 全部（付款、信用、其他） | No | — | — | — | 完全免費、無 IAP、不處理任何金流 |
| **Location** | Precise 精確位置 | No | — | — | — | 不使用定位，Info.plist 無任何 `NSLocation*` 字串（`App/project.yml`） |
| | Coarse 粗略位置 | **`TODO(待確認)`** | 否 | 否 | Analytics | App 本身不使用定位；但 GA4 會在**伺服器端**由連線 IP 推導國家／城市層級位置。**送審前請查一次 Google 當時的「App Store data disclosure」官方對照表再決定**；查不到明確結論就保守勾 Yes / Not Linked / 不追蹤 / Analytics。詳見 §6 |
| **Sensitive Info** | Sensitive Info | **No** | — | — | — | Apple 對此類的定義限於種族、性向、宗教、政治立場、工會、基因、生物辨識等；**身分證號不在其列**（見 §3 說明放哪裡）。且 v1.0.0 已移除生物辨識功能，不處理任何 biometric data |
| **Contacts** | Contacts | No | — | — | — | 不讀取通訊錄 |
| **User Content** | Photos or Videos 相片 | **Yes** | **Yes** | No | App Functionality | 使用者以 `PhotosPicker` 自選一張截圖，multipart 上傳到自己的當期任務（`UploadView.swift`、`UploadService`） |
| | Emails or Text Messages | No | — | — | — | 不讀取簡訊；OTP 由使用者自行輸入 |
| | Audio / Gameplay / Customer Support / Other | No | — | — | — | 無此類功能 |
| **Browsing History** | Browsing History | No | — | — | — | App 內無瀏覽器；註冊以外部 Safari 開啟固定網址 |
| **Search History** | Search History | No | — | — | — | 無搜尋功能 |
| **Identifiers** | User ID | **Yes** | **Yes** | No | App Functionality | **身分證號**放這裡（見 §3）。它是使用者在官方網站的帳號識別，登入時送出 |
| | Device ID | **Yes** | **No（Not Linked）** | No | **Analytics**、App Functionality | Firebase 的 app instance ID／Firebase Installations ID／Crashlytics installation UUID。三者都是隨機、可重置、不與帳號串接；**IDFV 已由 `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED=false` 關閉**，IDFA 則是連收集能力都沒連進二進位（用 `FirebaseAnalyticsCore`，未連結 `AdSupport`）。**只在使用者同意首次啟動的免責聲明之後才產生**（同意後預設開啟；使用者關掉開關即停止收集並重置該編號） |
| **Purchases** | Purchase History | No | — | — | — | 無購買行為 |
| **Usage Data** | Product Interaction | **Yes** | **No（Not Linked）** | No | **Analytics** | `Telemetry.AnalyticsEvent` 的 26 個事件（`screen_view`、`login`／`login_failed`、`tasks_fetch`、`upload_*`／`redeem_*`／`voucher_*` 漏斗、`site_error`、`consent_granted` 等）＋ Firebase 自動事件（`first_open`、`session_start`、`user_engagement`、`app_update` 等）。畫面名與所有參數值都來自封閉列舉，不含畫面上的任何資料。（**注意**：`app_launched` 已移除——Firebase 自己的 `first_open`／`session_start` 已經涵蓋，自己再補一個只是把同一件事數兩次。） |
| | Advertising Data | No | — | — | — | 不投放廣告，`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS=false`，未連結 `AdSupport`／`AdServices` |
| | Other Usage Data | No | — | — | — | 目前實作的事件沒有「商家偏好」這類額外互動資料。**若日後加入帶 `vendor`／`item` 參數的兌換事件，這一格要改成 Yes**（見 §5 觸發點） |
| **Diagnostics** | Crash Data | **Yes** | **No（Not Linked）** | No | App Functionality | Crashlytics 當機報告：堆疊、執行緒、裝置型號、OS 版本、App 版本、記憶體／空間餘量、當機時間 |
| | Other Diagnostic Data | **Yes** | **No（Not Linked）** | No | App Functionality | 非致命錯誤（只取 `domain`／`code`，訊息先過 `Redact.scrub`）、custom keys（`is_demo_mode`、`last_screen`）、breadcrumbs |
| | Performance Data | **No** | — | — | — | **未加入 Firebase Performance SDK**——`SportsRewards.LinkFileList` 內沒有 `FirebasePerformance`，`PrivacyInfo.xcprivacy` 也沒有宣告這一類。Apple 對此類的定義是啟動時間／當掉率／耗電，Crashlytics 不提供這些。**要與 privacy manifest 一致，這格填 No**；若你想保守起見勾 Yes，就必須同步在 `App/Resources/PrivacyInfo.xcprivacy` 補上 `NSPrivacyCollectedDataTypePerformanceData`，兩邊不可以不一致 |
| **Other Data** | Other Data | **Yes** | **Yes** | No | App Functionality | **出生日期**放這裡（見 §3）。登入三碼之一。<br>備註：本機 `SecureLog` 的輸出**不算**任何一類——它從不離開裝置，`debug` 層級在 Release build 直接編譯掉，且從不橋接到 Crashlytics |

**跨全表結論**：
- 「用於追蹤你的資料（Data Used to Track You）」→ **無（全部 Tracking = No）**。
  依據：`PrivacyInfo.xcprivacy` 的 `NSPrivacyTracking = false`、`NSPrivacyTrackingDomains` 為空陣列；
  Release 二進位未連結 `AdSupport`／`AppTrackingTransparency`／`AdServices`（`otool -l` 可驗），因此**不會、也無法**出現 ATT 提示；
  不與資料掮客往來，事件不跨 App／網站串接，廣告個人化訊號已關閉。
- 「與你連結的資料（Data Linked to You）」→ 手機號碼、User ID（身分證號）、Other Data（出生日期）、Photos or Videos。
  **這四項全部只送到 `500.gov.tw`，一個都不會進 Firebase。**
- 「未與你連結的資料（Data Not Linked to You）」→ Device ID、Product Interaction、Crash Data、Other Diagnostic Data。
  **這四項全部只送到 Google，一個都不含個資。**
- Purpose：送往 `500.gov.tw` 的那一組**只勾 App Functionality**；送往 Google 的那一組勾 **Analytics**（Device ID 另加 App Functionality，因為 Crashlytics 的 installation UUID 是修 bug 用的）。
  **一律不勾** Product Personalization、Developer's Advertising、Third-Party Advertising。

### 「Not Linked」這個答案怎麼辯護

Apple 定義 linked 為「可與使用者身分連結」。本 App 的辯護是四層，每層都可驗證：

1. **App 沒有帳號系統**，`Telemetry` 也從不呼叫 `Analytics.setUserID(_:)`（全檔搜尋零命中）。
2. **完全不設任何使用者屬性**：`UserProperty` 是 `enum UserProperty: Sendable {}`——**不可建構的空列舉**，所以連一個準識別碼屬性都構造不出來。
3. **IDFV 收集已關閉**（`GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED=false`），app instance ID 因此不與裝置層識別碼綁定。
4. **使用者可自行重置**：關掉開關即停止收集並重置 app instance ID、刪掉未送出的當機報告；「立即清除本機資料」會把**免責聲明的同意紀錄與遙測偏好一起重置**，下次冷啟動要重新看到聲明並重新同意，`Telemetry.configure()` 在那之前不會執行。

Google 官方的 App Store 資料揭露對照表對 Analytics／Crashlytics 的建議答案也是 Not Linked。

---

## 2. Health 為什麼是 Not Collected（重點題）

**這一題在本版變簡單了：App 完全不讀取健康資料。**

| 檢核 | 事實 | 依據 |
|---|---|---|
| 有沒有讀 HealthKit？ | **沒有。** 原始碼裡沒有任何一處 `import HealthKit`，也沒有 `HealthReading` 之類的抽象層 | `grep -r HealthKit Sources App/Sources` 無結果 |
| 有沒有 HealthKit entitlement？ | **沒有。** `App/project.yml` 已不再宣告任何 entitlements 檔 | `App/project.yml`；產生出來的 `App/Generated/` 下沒有 `.entitlements` |
| 有沒有健康權限用途字串？ | **沒有。** `NSHealthShareUsageDescription` 與 `NSHealthUpdateUsageDescription` 都已移除，使用者不會看到健康權限提示 | `App/Generated/Info.plist` |
| 上傳的圖片是不是用健康資料產生的？ | **不是**，而且現在連來源都不存在。上傳一律由使用者從相簿自選截圖 | `UploadView.swift` 只有 `PhotosPicker`，無任何圖卡產生路徑 |
| 遙測裡有沒有健康相關事件？ | **沒有。** `AnalyticsEvent` 是封閉列舉（26 個事件），沒有任何一個帶健康數值；原本唯一沾邊的 `health_link_tap` 已隨功能一併刪除。`UserProperty` 是**不可建構的空列舉** | `App/Sources/App/Telemetry.swift` |

→ **Health 與 Fitness 兩項都填 Not Collected**——不是靠「讀了但沒送出」的論證，而是**根本沒有讀**。

**與舊版的差別（留著避免有人以為文件過期）**：v1.0.0 build 4 以前確實讀取步數／距離／運動時間（唯讀、不外傳），
那時這一格要靠「未傳出裝置＝未蒐集」的前提 A 才成立，也是整份標籤最不能出錯的一格。
功能移除後，`5.1.3(i)`（健康資料換取獎勵）與「HealthKit + Google SDK 的組合」這兩個風險一起消失。

**要守住的線**：只要有人把讀取健康資料的功能加回來，這一格、`review-notes.md` §4 與 §7 的 5.1.3(i) 段、
以及 `PrivacyInfo.xcprivacy` 都要同步重寫，**而且遙測裡不得出現任何健康數值或其推導結論**（包含「今日是否達標」這種布林）。

---

## 3. 身分證號與出生日期該歸到哪一類（問卷沒有現成選項）

Apple 的資料類型清單沒有「國民身分證號」或「出生日期」的專屬項目，因此要選最貼近的：

| 資料 | 建議歸類 | 理由 | 被否決的選項 |
|---|---|---|---|
| 身分證號 | **Identifiers → User ID** | Apple 對 User ID 的定義是「screen name、handle、account ID、assigned user ID、customer number 或其他使用者／帳號層級的識別碼」。身分證號在 `500.gov.tw` 上**就是帳號本身**（`POST /access` 以 `idNo` 分流、登入以三碼比對），完全符合「帳號層級識別碼」 | **Sensitive Info**：Apple 該類的定義是種族／性向／宗教／政治／工會／基因／生物辨識，身分證號不屬其中，硬勾反而讓標籤失準 |
| 出生日期 | **Other Data** | Apple 明列「Other Data：未在上述類型中明確提到的任何其他資料」。出生日期不是聯絡資訊、不是識別碼、不是健康資料 | **Contact Info**：DOB 不是聯絡方式；**Health**：DOB 與健康資料無關，本 App 也不讀取健康資料 |

**在問卷的自由描述欄（Other Data 允許填說明）建議寫**：
`出生日期，僅用於登入使用者本人在 500.gov.tw 的既有帳號。`

---

## 4. 隱私權政策必須與這份標籤一致的段落

隱私權政策網頁（`app-store-metadata.md` §7 的 `TODO(待填)`）至少要涵蓋以下五點，句句對得上上表：

1. **開發者不營運任何伺服器**，不接收、不儲存、也無法存取使用者的身分資料；本 App 無自建後端。
2. **本機儲存**：身分證號、出生日期、手機號碼加密保存在 iOS Keychain（`WhenUnlockedThisDeviceOnly`），不同步 iCloud、不隨備份轉移、不寫入紀錄檔。
3. **與第三方分享**：上述三個欄位以及使用者自選的上傳截圖，會在使用者主動操作時，**由裝置直接傳送到 `500.gov.tw`**（活動主辦單位營運的網站，使用者帳號所在地）。該網站對這些資料的處理適用其自身的隱私政策，並附上連結：`TODO(待填：500.gov.tw 的隱私政策網址)`。
4. **健康資料**：本 App 不讀取任何健康資料，亦未申請 HealthKit 權限。
5. **刪除方式**：App 內「我的資料 →『立即清除本機資料』」即永久刪除本機全部資料；刪除 App 亦同。官方網站上的帳號請至 `500.gov.tw` 自行管理。
6. **匿名使用統計與當機回報（新增，必須寫）**：使用 Google Firebase Analytics 與 Crashlytics；
   **首次啟動的免責聲明會明白揭露這件事，使用者按下「同意並開始使用」時才初始化 Firebase；同意之後預設開啟**，
   可隨時於「我的資料 › 安全與隱私 › 傳送匿名使用統計」關閉；
   送出的是匿名操作事件、當機報告與一組可重置的隨機安裝編號；**不含身分證號、出生日期、手機號碼、截圖與券碼**；
   資料傳往 Google 位於美國的伺服器；如何關閉。→ 已寫入 `site/privacy.html` §5「使用統計與當機回報（同意後預設開啟）」。
   **文字上不得再出現「預設關閉」或「opt-in」**——那已經是不實陳述。
7. **網域白名單的界線**：App 自己的 HTTP client 只連 `500.gov.tw`，但 Firebase SDK 走自己的連線、不受該白名單管轄；遙測運作時會連往
   `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`。
   → 已寫入 `site/privacy.html` §3。

---

## 5. 程式碼改動時要回頭重填問卷的觸發點

以下任何一項成立，這份標籤就過期了：

- 重新加入任何 HealthKit 讀取（尤其是「以 HealthKit 數據產生上傳圖卡」）→ §2 整段、`PrivacyInfo.xcprivacy` 與 Review Notes 都要重寫；產生上傳圖卡更會直接踩到 Guideline 5.1.3(i)。
- 恢復收集姓名／Email／健保卡卡號 → Contact Info 需重填，健保卡號還會拉高 5.1.1(ix) 風險。
- ~~加入任何 analytics、crash 回報或廣告 SDK~~ → **已於 2026-09-06 發生**（firebase-ios-sdk 12.18.0）。Usage Data / Diagnostics / Identifiers 已依此重填，「零第三方相依」的說法已全面作廢。
- ~~**把 `defaultEnabled` 改成 `true`**~~ → **已於 2026-09-06 發生**。`defaultEnabled` 現在是 `true`，「預設關閉」「opt-in」的說法已在 Review Notes、隱私政策、官網、商店描述與 CHANGELOG 全面改寫為「先告知 → 主動同意 → 預設開啟 → 隨時可關」。**§1 的逐項答案未因此變動**（前提 C）。
- **改動 Info.plist 那四個 `false` 旗標** → 它們現在的意義是「冷啟動預設值 / 還沒 `configure` 就絕不收集」，不是「預設關閉」。改成 `true` 會讓「同意前零收集」失去最後一層保險，Review Notes §5b 與隱私政策第 5 節都要重寫。
- **把 `Telemetry.configure()` 的三道前置條件（未同意免責聲明／使用者關閉／示範模式）拿掉任何一道**，或**把 `DisclaimerConsent.record()` 裡的 `Telemetry.configure()` 移到別的時機** → 「同意前 Firebase 一行程式碼都不執行」這句話會失效，那是本次設計唯一真正的保障，官網、README 與 Review Notes 都要一起改。
- **從 `DisclaimerView` 拿掉「匿名使用統計」那一條，或改動勾選文字** → 揭露點就消失了，變成「使用者沒讀到就開始送」。這是全案最不能動的一段文案。
- **在 `AnalyticsEvent`／`UserProperty`／`CrashKey` 任一列舉裡加入含健康數值或達標結論的成員** → Health/Fitness 立刻變成 Collected，直接踩 5.1.3(i)。**這是全表最危險的改動**（即使本版已無健康資料來源，這條規則仍然有效）。
- **加入帶 `vendor`／`item` 等參數的兌換事件** → Usage Data › Other Usage Data 改成 Yes。
- **加入 Firebase Performance、Remote Config、Messaging、In-App Messaging、App Check 或 Analytics（非 Core）版本** → Diagnostics › Performance Data、Identifiers 要重評；改用 `FirebaseAnalytics`（非 Core）會把 `AdSupport` 連進來，Tracking 與 ATT 的答案全部要重來。
- **呼叫 `Analytics.setUserID(_:)`，或把 IDFV 收集打開** → 所有 Firebase 項目從 Not Linked 變成 Linked。
- 網域白名單放寬到 `500.gov.tw` 以外 → 第三方分享的對象要重新盤點（Firebase 的網域不算「放寬」，因為它從一開始就不受該白名單管轄——但這件事本身必須在文件裡寫清楚，不能靠沉默）。
- 加入自建後端 → 整份表要重做，`README.md` 與所有文案的「無後端」聲明也一併失效。

---

## 6. Firebase 的事實基準（填問卷時的覆核清單）

這一節是給「填問卷的人」與「日後質疑這份標籤的人」用的，全部可以自己驗。

| 事實 | 值 | 怎麼驗 |
|---|---|---|
| SDK 與版本 | firebase-ios-sdk **12.18.0** | `App/project.yml` → `packages.Firebase.from: "12.18.0"` |
| 使用的 product | `FirebaseAnalyticsCore`、`FirebaseCrashlytics`、`FirebaseCore` | `App/project.yml` → `targets.SportsRewards.dependencies` |
| SPM **解析**的套件數 | **13** | `App/SportsRewards.xcodeproj/.../Package.resolved` 的 `pins` |
| **實際連進二進位**的套件數 | **6**：`firebase-ios-sdk`、`GoogleAppMeasurement`、`GoogleDataTransport`、`GoogleUtilities`、`nanopb`、`promises` | Release build 的 `SportsRewards.LinkFileList`；另可看 `.app` 內的 resource bundle 清單 |
| 沒被連結的 7 個 | `abseil-cpp-binary`、`app-check`、`google-ads-on-device-conversion-ios-sdk`、`grpc-binary`、`gtm-session-fetcher`、`interop-ios-for-google-sdks`、`leveldb` | 同上（只被解析、不在 LinkFileList 內） |
| IDFA 能力 | **沒有**。`FirebaseAnalyticsCore` 底層是 `GoogleAppMeasurementCore`，結構上不含 IDFA 收集 | `otool -l` Release 二進位：無 `AdSupport`、`AppTrackingTransparency`、`AdServices` 的 load command |
| `Telemetry.defaultEnabled` | **`true`**——同意免責聲明之後預設開啟 | `App/Sources/App/Telemetry.swift` |
| Firebase 初始化時機 | 使用者在首次啟動的免責聲明按下「同意並開始使用」時，由 `DisclaimerConsent.record()` 呼叫 `Telemetry.configure()`。**那是整支 App 第一次執行 Firebase 程式碼的時機** | `App/Sources/App/DisclaimerConsent.swift`、`App/Sources/Views/DisclaimerView.swift` |
| `configure()` 的前置條件 | 三道，缺一不初始化：尚未同意免責聲明 → 使用者關掉開關 → 示範模式 | `Telemetry.configure()` |
| Info.plist 四個旗標 | 仍全為 `false`。意義是**冷啟動預設值**（守住「還沒 `configure` 就絕不收集」），由 `applyCollectionFlags` 在初始化後依使用者偏好覆寫——**不再代表「預設關閉」** | 建置後的 `SportsRewards.app/Info.plist`、`Telemetry.applyCollectionFlags` |
| 使用者開關位置 | 「我的資料 › 安全與隱私 › 傳送匿名使用統計」 | `App/Sources/Views/ProfileView.swift` |
| 遙測出口 | 只有 `App/Sources/App/Telemetry.swift`；其他檔案禁止 `import FirebaseAnalytics` / `FirebaseCrashlytics` | 全專案 grep |
| 送得出去的事件 | 封閉列舉 `AnalyticsEvent` 的 26 個 case（`screen_view`、`login`／`login_failed`、`tasks_fetch`、上傳／兌換／券碼漏斗、`site_error`、`consent_granted` 等）。畫面名亦為封閉列舉；每個參數值都是列舉 rawValue 或小範圍整數 | `Telemetry.swift` |
| 使用者屬性 | **完全不設**。`enum UserProperty: Sendable {}` 是不可建構的空列舉，`Analytics.setUserProperty` 沒有任何呼叫點 | 同上 |
| Crash custom keys | 封閉列舉 `CrashKey` 的 13 個 case：`build_channel`、`demo_mode`、`screen`、`onboarding_step`、`session_state`、`tasks_cache`、`current_period`、`current_state`、`last_endpoint`、`last_status`、`upload_stage`、`voucher_stage`、`consent_source` | 同上 |
| `setUserID` | **從不呼叫** | 全專案 grep 零命中 |
| 六道閘門 | 示範模式 → 截圖模式 → 使用者關閉 → 未初始化 → 參數命中 `Redact` 敏感樣式 → 整數值域白名單（最後兩道在 DEBUG 直接 `assertionFailure`） | `Telemetry.gate(...)` |
| 設定檔 | `GoogleService-Info.plist` **不進版控**（repo 公開），只附 `.template`；真檔不存在時全程 no-op 且不 crash | `.gitignore`、`Telemetry.configure()` 的 `guard Bundle.main.path(...)` |
| SDK 連往的網域 | `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com` | `strings` Release 二進位 |

### 必須與 `PrivacyInfo.xcprivacy` 對得上

最終的隱私報告是 **App manifest ∪ 所有 SDK manifest** 的聯集，App Store Connect 的問卷答案不能比它少。
本 App 的 `App/Resources/PrivacyInfo.xcprivacy` 目前宣告：

- `NSPrivacyTracking = false`、`NSPrivacyTrackingDomains = []`
- 蒐集類型三筆，皆 **not linked、not tracking**：`CrashData`（App Functionality）、`OtherDiagnosticData`（App Functionality）、`ProductInteraction`（Analytics）
- Required-reason API：`UserDefaults`，理由 `CA92.1`

**注意兩個對不齊的地方，填問卷前要先決定**：

1. **Device ID**：問卷要勾 Yes（app instance ID），但 App 自己的 manifest 沒有列 `DeviceID`。
   Firebase 各 SDK 自帶的 manifest 已經宣告了它，聯集後不會漏；但若想讓「這支 App 送什麼」在自家 repo 就查得到，
   可考慮在 `PrivacyInfo.xcprivacy` 補一筆 `NSPrivacyCollectedDataTypeDeviceID`（not linked / not tracking / Analytics + AppFunctionality）。
   **這需要改 `App/Resources/`，不在本次文件變更的範圍內。**
2. **Performance Data**：問卷與 manifest 目前都是「沒有」。要改就兩邊一起改。

### TODO(待確認)

- **Location › Coarse Location**：GA4 會由連線 IP 在**伺服器端**推導國家／城市層級位置（App 本身不使用定位、無任何 `NSLocation*` 字串）。
  Google 官方的「App Store data disclosure」對照表歷來對此有明確建議，但版本會變動。
  **送審前請直接查一次 Google 當時的官方對照表再決定這一格**，不要照抄本文件。若查不到明確結論，保守勾 **Yes / Not Linked / No tracking / Analytics**。
- **Firebase 主控台端設定尚未確認是否已做**（這些會影響上面幾格的辯護力道）：GA4 資料保留期設為最短、關閉 Google Signals、關閉廣告個人化、
  關閉精細位置與裝置資料蒐集（只留國家層級）、不開啟 BigQuery 匯出。→ 見 `docs/analytics-plan.md` §6.6 結尾。
