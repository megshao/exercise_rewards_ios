# App 隱私問卷（App Privacy）逐項建議答案 — Sports Rewards 1.0

適用於 App Store Connect →「App 隱私」→ 資料類型問卷。
每一項都附「依據」，指向實際的檔案或行為，方便你自己覆核，也方便日後程式碼改動時回頭比對。

---

## 0. 先講兩個判斷前提（最關鍵的兩題）

### 前提 A — Apple 對「蒐集（Collect）」的定義

> Apple：「Collect」指把資料**傳出裝置**，且你或你的第三方夥伴能存取的時間**超過即時處理該請求所需**。

所以：**只存在裝置本機、從未離開裝置的資料，一律是 Not Collected。** 這一點讓本 App 的絕大多數項目直接歸零。

### 前提 B — 資料送到 `500.gov.tw` 算不算「與第三方分享」？

**結論：算，要如實揭露。**

理由與取捨：
- 嚴格照字面看，開發者**沒有伺服器、拿不到任何資料**（`docs/PRD.md §4.3`、`README.md`「無任何雲端後端」），而 `500.gov.tw` 是**使用者自己的帳號所在網站**、由使用者主動觸發登入才送出。照這個讀法，理論上可以主張連「蒐集」都不成立。
- 但 Apple 的問卷是**以使用者視角**描述「這支 App 會把我的什麼資料送出去」，不是只描述開發者拿到什麼。身分證號與手機號碼**確實離開了裝置**。
- 而且這條也不能走 Apple 的「選擇性揭露（Optional Disclosure）」豁免——豁免要求「蒐集只發生在非主要功能、且對使用者為選填」，但登入送出三碼**正是本 App 的主要功能**，不符合。
- 本專案的既定立場也是如此（`docs/app-review-risk.md` 降險清單第 8 條：「資料送 500.gov.tw 屬『與第三方分享』，隱私標籤如實勾」）。

**風險取捨**：多勾的代價只是商店頁面的隱私卡片多幾列，並要在隱私權政策把 `500.gov.tw` 寫清楚；少勾的代價是「隱私標籤不實」，可能導致下架與 metadata 違規。**選多勾。**

### 問卷第一題

> 「你或你的第三方夥伴會從這個 App 蒐集資料嗎？」→ **會（Yes）**

（若你採用上面括號中的極簡讀法而選「不會」，那下面整份表就不必填——但本文件不建議，理由同上。）

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
| **Health & Fitness** | Health 健康 | **No** | — | — | — | 見下方 §2，唯讀且**從不離開裝置** |
| | Fitness 健身 | **No** | — | — | — | 同 §2。步數／距離／運動時間只在 `HealthView`、`HomeView` 本機顯示 |
| **Financial Info** | 全部（付款、信用、其他） | No | — | — | — | 完全免費、無 IAP、不處理任何金流 |
| **Location** | Precise / Coarse | No | — | — | — | 不使用定位，Info.plist 無任何 `NSLocation*` 字串（`App/project.yml`） |
| **Sensitive Info** | Sensitive Info | **No** | — | — | — | Apple 對此類的定義限於種族、性向、宗教、政治立場、工會、基因、生物辨識等；**身分證號不在其列**（見 §3 說明放哪裡）。且 v1.0.0 已移除生物辨識功能，不處理任何 biometric data |
| **Contacts** | Contacts | No | — | — | — | 不讀取通訊錄 |
| **User Content** | Photos or Videos 相片 | **Yes** | **Yes** | No | App Functionality | 使用者以 `PhotosPicker` 自選一張截圖，multipart 上傳到自己的當期任務（`UploadView.swift`、`UploadService`） |
| | Emails or Text Messages | No | — | — | — | 不讀取簡訊；OTP 由使用者自行輸入 |
| | Audio / Gameplay / Customer Support / Other | No | — | — | — | 無此類功能 |
| **Browsing History** | Browsing History | No | — | — | — | App 內無瀏覽器；註冊以外部 Safari 開啟固定網址 |
| **Search History** | Search History | No | — | — | — | 無搜尋功能 |
| **Identifiers** | User ID | **Yes** | **Yes** | No | App Functionality | **身分證號**放這裡（見 §3）。它是使用者在官方網站的帳號識別，登入時送出 |
| | Device ID | No | — | — | — | 不讀取 IDFA/IDFV，零第三方 SDK（`README.md`「供應鏈：零第三方相依」） |
| **Purchases** | Purchase History | No | — | — | — | 無購買行為 |
| **Usage Data** | Product Interaction / Advertising Data / Other | No | — | — | — | 無任何 analytics SDK；`docs/PRD.md §8.2` 明訂禁用會外傳個資的 analytics/crash SDK |
| **Diagnostics** | Crash Data / Performance Data / Other | No | — | — | — | 無 crash 回報 SDK；所有 log 走本機 `SecureLog`，且敏感值先過 `Redact`，不外傳 |
| **Other Data** | Other Data | **Yes** | **Yes** | No | App Functionality | **出生日期**放這裡（見 §3）。登入三碼之一 |

**跨全表結論**：
- 「用於追蹤你的資料（Data Used to Track You）」→ **無**。App 不含任何廣告或分析 SDK，不與資料掮客往來，不做跨 App/網站的關聯。
- 「與你連結的資料（Data Linked to You）」→ 手機號碼、User ID（身分證號）、Other Data（出生日期）、Photos or Videos。
- 「未與你連結的資料（Data Not Linked to You）」→ **無**。
- 所有項目的 Purpose **只勾 App Functionality**，不勾 Analytics、Product Personalization、任何 Advertising。

---

## 2. Health 為什麼是 Not Collected（重點題）

| 檢核 | 事實 | 依據 |
|---|---|---|
| 有沒有讀 HealthKit？ | 有，且**只讀** `stepCount`、`distanceWalkingRunning`、`appleExerciseTime` 三型 | `App/project.yml` entitlements、`docs/PRD.md §7.1`、`HealthKitReader.swift` |
| 有沒有寫入 HealthKit？ | **沒有**，無任何寫入路徑 | `NSHealthUpdateUsageDescription` 字串本身即寫明「本 App 不會寫入任何健康資料」 |
| 健康資料有沒有離開裝置？ | **沒有**。只在 `HomeView` 步數環與 `HealthView` 摘要卡上顯示 | `HealthView.swift`：「健康數據只在裝置本機顯示，不會被送出」 |
| 上傳的圖片是不是用健康資料產生的？ | **不是**。v1.0.0 **已移除**「以 HealthKit 數據產生上傳圖卡」的設計，上傳一律由使用者從相簿自選截圖 | `UploadView.swift` 只有 `PhotosPicker`，無 `ImageRenderer` 圖卡產生路徑；對應 `docs/app-review-risk.md` 降險第 4 條 |
| 網路層有沒有可能把它送出去？ | 沒有。唯一的出口是 `500.gov.tw`，且送出的是使用者自選的圖片檔，不含任何 HealthKit 欄位 | `URLSessionHTTPClient` 網域白名單 |

→ **依前提 A（未傳出裝置＝未蒐集），Health 與 Fitness 兩項都填 Not Collected。**

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

1. **開發者不營運任何伺服器**，不接收、不儲存、也無法存取任何使用者資料；本 App 無後端、無 analytics、無 crash 回報、零第三方 SDK。
2. **本機儲存**：身分證號、出生日期、手機號碼加密保存在 iOS Keychain（`WhenUnlockedThisDeviceOnly`），不同步 iCloud、不隨備份轉移、不寫入紀錄檔。
3. **與第三方分享**：上述三個欄位以及使用者自選的上傳截圖，會在使用者主動操作時，**由裝置直接傳送到 `500.gov.tw`**（活動主辦單位營運的網站，使用者帳號所在地）。該網站對這些資料的處理適用其自身的隱私政策，並附上連結：`TODO(待填：500.gov.tw 的隱私政策網址)`。
4. **健康資料**：僅讀取步數、步行與跑步距離、運動時間；不寫入、不外傳、不用於產生上傳內容、不用於廣告或行銷。
5. **刪除方式**：App 內「我的資料 →『立即清除本機資料』」即永久刪除本機全部資料；刪除 App 亦同。官方網站上的帳號請至 `500.gov.tw` 自行管理。

---

## 5. 程式碼改動時要回頭重填問卷的觸發點

以下任何一項成立，這份標籤就過期了：

- 重新加入「以 HealthKit 數據產生上傳圖卡」→ Health/Fitness 立刻變成 **Collected**，且會直接踩到 Guideline 5.1.3(i)。
- 恢復收集姓名／Email／健保卡卡號 → Contact Info 需重填，健保卡號還會拉高 5.1.1(ix) 風險。
- 加入任何 analytics、crash 回報或廣告 SDK → Usage Data / Diagnostics / Identifiers 全部要重填，且「零第三方相依」的說法作廢。
- 網域白名單放寬到 `500.gov.tw` 以外 → 第三方分享的對象要重新盤點。
- 加入自建後端 → 整份表要重做，`README.md` 與所有文案的「無後端」聲明也一併失效。
