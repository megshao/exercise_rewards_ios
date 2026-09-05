# App 隱私問卷（App Privacy）逐項建議答案 — Sports Rewards 1.0

適用於 App Store Connect →「App 隱私」→ 資料類型問卷。
每一項都附「依據」，指向實際的檔案或行為，方便你自己覆核，也方便日後程式碼改動時回頭比對。

> **2026-09-06 大改**：本 App 加入了 **firebase-ios-sdk 12.18.0**（Analytics + Crashlytics），
> 這份文件原先「Identifiers/Usage Data/Diagnostics 全部 Not Collected」的結論**已經作廢**。
> 現行答案見 §1。**Health 與 Fitness 仍然是 Not Collected**，理由見 §2——那一格沒有變，而且不能變。

---

## 0. 先講兩個判斷前提（最關鍵的兩題）

### 前提 A — Apple 對「蒐集（Collect）」的定義

> Apple：「Collect」指把資料**傳出裝置**，且你或你的第三方夥伴能存取的時間**超過即時處理該請求所需**。

所以：**只存在裝置本機、從未離開裝置的資料，一律是 Not Collected。** 這一點仍然讓多數項目歸零——最重要的是健康資料（§2）。
（但它不再讓「絕大多數」項目歸零：2026-09-06 加入的遙測確實會把匿名資料傳出裝置，見前提 C。）

### 前提 B — 資料送到 `500.gov.tw` 算不算「與第三方分享」？

**結論：算，要如實揭露。**

理由與取捨：
- 嚴格照字面看，開發者**沒有自建伺服器、拿不到任何身分資料**（`docs/PRD.md §4.3`、`README.md` 威脅模型「個資外洩」列），而 `500.gov.tw` 是**使用者自己的帳號所在網站**、由使用者主動觸發登入才送出。照這個讀法，理論上可以主張連「蒐集」都不成立。
- 但 Apple 的問卷是**以使用者視角**描述「這支 App 會把我的什麼資料送出去」，不是只描述開發者拿到什麼。身分證號與手機號碼**確實離開了裝置**。
- 而且這條也不能走 Apple 的「選擇性揭露（Optional Disclosure）」豁免——豁免要求「蒐集只發生在非主要功能、且對使用者為選填」，但登入送出三碼**正是本 App 的主要功能**，不符合。
- 本專案的既定立場也是如此（`docs/app-review-risk.md` 降險清單第 8 條：「資料送 500.gov.tw 屬『與第三方分享』，隱私標籤如實勾」）。

**風險取捨**：多勾的代價只是商店頁面的隱私卡片多幾列，並要在隱私權政策把 `500.gov.tw` 寫清楚；少勾的代價是「隱私標籤不實」，可能導致下架與 metadata 違規。**選多勾。**

### 前提 C — 遙測「預設關閉」能不能因此不申報？

**結論：不能。要照樣申報。**

Apple 有一條「選擇性揭露（Optional Disclosure）」豁免，但四個條件要同時成立，其中兩條本 App 過不了：

- 「使用者**每次**都主動選擇提供該筆資料，且提供時有明顯的請求介面」——匿名事件是在背景自動送出的，使用者只按過一次總開關，不是每次主動提供。
- 「蒐集只發生在非主要功能的、不常見的情境」——遙測橫跨整個 App 生命週期。

所以：**「預設關閉」是很好的隱私設計，也值得寫進 Review Notes，但它不是不申報的理由。**
問卷問的是「這支 App 有沒有可能蒐集」，而不是「預設有沒有蒐集」。
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
| **Health & Fitness** | Health 健康 | **No** | — | — | — | 見下方 §2，唯讀且**從不離開裝置**——包含**不進遙測**，連由步數推導的達標布林都不送 |
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
| | Device ID | **Yes** | **No（Not Linked）** | No | **Analytics**、App Functionality | Firebase 的 app instance ID／Firebase Installations ID／Crashlytics installation UUID。三者都是隨機、可重置、不與帳號串接；**IDFV 已由 `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED=false` 關閉**，IDFA 則是連收集能力都沒連進二進位（用 `FirebaseAnalyticsCore`，未連結 `AdSupport`）。**只在使用者開啟「傳送匿名使用統計」後才產生** |
| **Purchases** | Purchase History | No | — | — | — | 無購買行為 |
| **Usage Data** | Product Interaction | **Yes** | **No（Not Linked）** | No | **Analytics** | `Telemetry.AnalyticsEvent` 的事件（`app_launched`、`screen_view`、`telemetry_preference_changed`）＋ Firebase 自動事件（`first_open`、`session_start`、`user_engagement`、`app_update` 等）。畫面名來自封閉列舉，不含畫面上的任何資料 |
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
2. **不設任何準識別碼的使用者屬性**：`UserProperty` 是封閉列舉，只有 `health_auth_granted`、`onboarding_completed` 兩個布林。
3. **IDFV 收集已關閉**（`GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED=false`），app instance ID 因此不與裝置層識別碼綁定。
4. **使用者可自行重置**：關掉開關即停止收集；「立即清除本機資料」會把偏好重設回關閉。

Google 官方的 App Store 資料揭露對照表對 Analytics／Crashlytics 的建議答案也是 Not Linked。

---

## 2. Health 為什麼是 Not Collected（重點題）

| 檢核 | 事實 | 依據 |
|---|---|---|
| 有沒有讀 HealthKit？ | 有，且**只讀** `stepCount`、`distanceWalkingRunning`、`appleExerciseTime` 三型 | `App/project.yml` entitlements、`docs/PRD.md §7.1`、`HealthKitReader.swift` |
| 有沒有寫入 HealthKit？ | **沒有**，無任何寫入路徑 | `NSHealthUpdateUsageDescription` 字串本身即寫明「本 App 不會寫入任何健康資料」 |
| 健康資料有沒有離開裝置？ | **沒有**。只在 `HomeView` 步數環與 `HealthView` 摘要卡上顯示 | `HealthView.swift`：「健康數據只在裝置本機顯示，不會被送出」 |
| 上傳的圖片是不是用健康資料產生的？ | **不是**。v1.0.0 **已移除**「以 HealthKit 數據產生上傳圖卡」的設計，上傳一律由使用者從相簿自選截圖 | `UploadView.swift` 只有 `PhotosPicker`，無 `ImageRenderer` 圖卡產生路徑；對應 `docs/app-review-risk.md` 降險第 4 條 |
| 網路層有沒有可能把它送出去？ | 沒有。App 自己的出口只有 `500.gov.tw`，且送出的是使用者自選的圖片檔，不含任何 HealthKit 欄位 | `URLSessionHTTPClient` 網域白名單 |
| **加了 Firebase 之後，健康資料有沒有可能進遙測？** | **沒有。** `AnalyticsEvent` 是封閉列舉，三個事件（`app_launched`、`screen_view`、`telemetry_preference_changed`）都不帶任何健康數值；`UserProperty` 也是封閉列舉，只有兩個布林。**連「今日是否達標」這種由步數推導的布林值都刻意不送**——`Telemetry.swift` 檔頭把它列為禁止項第 2 條，理由就是 Apple 禁止把 HealthKit 資料分享給第三方 | `App/Sources/App/Telemetry.swift`（封閉列舉 + 四道閘門 + DEBUG `assertionFailure`）|
| 那 `health_auth_granted` 呢？ | 它是**授權狀態**（使用者有沒有按同意），不是健康資料，Apple 的 Health & Fitness 類別指的是 HealthKit 讀到的量測值。這一筆歸在 Usage Data / Diagnostics 的範圍，不影響 Health 這一格。**若日後有人把它改成帶數值（步數、達標與否），Health 就立刻變成 Collected，並直接踩 5.1.3(i)** | `Telemetry.UserProperty` |

→ **依前提 A（未傳出裝置＝未蒐集），Health 與 Fitness 兩項都填 Not Collected。**

**加入 Firebase 之後，這個答案為什麼還站得住**：`500.gov.tw` 收到的只有使用者自選的截圖檔，Google 收到的只有封閉列舉出來的匿名事件。
兩條出口都沒有 HealthKit 欄位，所以健康資料**在任何情況下都沒有離開裝置**。
這句話是本 App 對 5.1.3(i) 最有力的辯護，也是整份標籤裡最不能出錯的一格——**任何要在遙測裡加健康相關數值的提案，都應該直接否決。**

**注意**：這一格與「App 有沒有申請 HealthKit 權限」是兩回事。App 仍會出現 HealthKit 權限提示，這不影響隱私標籤的答案——Apple 問的是「是否傳出裝置」，不是「是否讀取」。
**另外**：Apple 對 HealthKit 有獨立的硬性規定——健康資料不得用於廣告、行銷或資料探勘。本 App 完全不做這些，可在 Review Notes 一併說明（見 `review-notes.md` §4）。

---

## 3. 身分證號與出生日期該歸到哪一類（問卷沒有現成選項）

Apple 的資料類型清單沒有「國民身分證號」或「出生日期」的專屬項目，因此要選最貼近的：

| 資料 | 建議歸類 | 理由 | 被否決的選項 |
|---|---|---|---|
| 身分證號 | **Identifiers → User ID** | Apple 對 User ID 的定義是「screen name、handle、account ID、assigned user ID、customer number 或其他使用者／帳號層級的識別碼」。身分證號在 `500.gov.tw` 上**就是帳號本身**（`POST /access` 以 `idNo` 分流、登入以三碼比對），完全符合「帳號層級識別碼」 | **Sensitive Info**：Apple 該類的定義是種族／性向／宗教／政治／工會／基因／生物辨識，身分證號不屬其中，硬勾反而讓標籤失準 |
| 出生日期 | **Other Data** | Apple 明列「Other Data：未在上述類型中明確提到的任何其他資料」。出生日期不是聯絡資訊、不是識別碼、不是健康資料 | **Contact Info**：DOB 不是聯絡方式；**Health**：DOB 不是 HealthKit 資料 |

**在問卷的自由描述欄（Other Data 允許填說明）建議寫**：
`出生日期，僅用於登入使用者本人在 500.gov.tw 的既有帳號。`

---

## 4. 隱私權政策必須與這份標籤一致的段落

隱私權政策網頁（`app-store-metadata.md` §7 的 `TODO(待填)`）至少要涵蓋以下五點，句句對得上上表：

1. **開發者不營運任何伺服器**，不接收、不儲存、也無法存取使用者的身分資料與健康資料；本 App 無自建後端。
2. **本機儲存**：身分證號、出生日期、手機號碼加密保存在 iOS Keychain（`WhenUnlockedThisDeviceOnly`），不同步 iCloud、不隨備份轉移、不寫入紀錄檔。
3. **與第三方分享**：上述三個欄位以及使用者自選的上傳截圖，會在使用者主動操作時，**由裝置直接傳送到 `500.gov.tw`**（活動主辦單位營運的網站，使用者帳號所在地）。該網站對這些資料的處理適用其自身的隱私政策，並附上連結：`TODO(待填：500.gov.tw 的隱私政策網址)`。
4. **健康資料**：僅讀取步數、步行與跑步距離、運動時間；不寫入、不外傳、不用於產生上傳內容、不用於廣告或行銷。
5. **刪除方式**：App 內「我的資料 →『立即清除本機資料』」即永久刪除本機全部資料；刪除 App 亦同。官方網站上的帳號請至 `500.gov.tw` 自行管理。
6. **匿名使用統計與當機回報（新增，必須寫）**：使用 Google Firebase Analytics 與 Crashlytics；**預設關閉**，使用者於「我的資料 › 安全與隱私 › 傳送匿名使用統計」自行開啟後才會運作；
   送出的是匿名操作事件、當機報告與一組可重置的隨機安裝編號；**不含身分證號、出生日期、手機號碼、任何 HealthKit 數據或其推導結論、截圖與券碼**；
   資料傳往 Google 位於美國的伺服器；如何關閉。→ 已寫入 `site/privacy.html` §5「使用統計與當機回報（預設關閉）」。
7. **網域白名單的界線**：App 自己的 HTTP client 只連 `500.gov.tw`，但 Firebase SDK 走自己的連線、不受該白名單管轄；使用者開啟遙測後會連往
   `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`。
   → 已寫入 `site/privacy.html` §3。

---

## 5. 程式碼改動時要回頭重填問卷的觸發點

以下任何一項成立，這份標籤就過期了：

- 重新加入「以 HealthKit 數據產生上傳圖卡」→ Health/Fitness 立刻變成 **Collected**，且會直接踩到 Guideline 5.1.3(i)。
- 恢復收集姓名／Email／健保卡卡號 → Contact Info 需重填，健保卡號還會拉高 5.1.1(ix) 風險。
- ~~加入任何 analytics、crash 回報或廣告 SDK~~ → **已於 2026-09-06 發生**（firebase-ios-sdk 12.18.0）。Usage Data / Diagnostics / Identifiers 已依此重填，「零第三方相依」的說法已全面作廢。
- **把 `defaultEnabled` 改成 `true`，或改動 Info.plist 那四個 `false` 旗標** → 「預設關閉」這句話在 Review Notes、隱私政策、官網與 CHANGELOG 都要一起改；opt-in 是本次變更最主要的辯護點。
- **在 `AnalyticsEvent`／`UserProperty`／`CrashKey` 任一列舉裡加入含健康數值或達標結論的成員** → Health/Fitness 立刻變成 Collected，直接踩 5.1.3(i)。**這是全表最危險的改動。**
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
| 預設收集狀態 | **關閉**（四個 Info.plist 旗標皆 `false`） | 建置後的 `SportsRewards.app/Info.plist` |
| 使用者開關位置 | 「我的資料 › 安全與隱私 › 傳送匿名使用統計」 | `App/Sources/Views/ProfileView.swift` |
| 遙測出口 | 只有 `App/Sources/App/Telemetry.swift`；其他檔案禁止 `import FirebaseAnalytics` / `FirebaseCrashlytics` | 全專案 grep |
| 送得出去的事件 | 封閉列舉 `AnalyticsEvent`：`app_launched`、`screen_view`（畫面名亦為封閉列舉）、`telemetry_preference_changed` | `Telemetry.swift` |
| 使用者屬性 | 封閉列舉 `UserProperty`，只有兩個布林：`health_auth_granted`、`onboarding_completed` | 同上 |
| Crash custom keys | 封閉列舉 `CrashKey`：`is_demo_mode`、`last_screen` | 同上 |
| `setUserID` | **從不呼叫** | 全專案 grep 零命中 |
| 四道閘門 | 未初始化 → 示範模式（無 bypass）→ 使用者關閉 → 參數命中 `Redact` 敏感樣式（DEBUG 直接 `assertionFailure`） | `Telemetry.gate(...)` |
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
