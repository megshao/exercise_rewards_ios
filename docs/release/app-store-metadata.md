# App Store Connect 送審欄位（Exercise Rewards v1.0.0）

- **對應版本**：`CFBundleShortVersionString` = 1.0.0、`CFBundleVersion` = **6**（送審版）
  - build 4 於 2026-09-06 上傳並掛上版本記錄，但**移除 HealthKit 等變更都在那之後**，因此 1.0.0 不使用 build 4。
  - build 5 曾在本機封存過，未上傳；隨後又修掉「本週任務不會換期」與「過期期別仍可點上傳」兩個 bug，因此送審用 build 6。build 1–5 皆作廢。
  - build 6 對應 git tag `v1.0.0`。
- **Bundle ID**：`com.megshao.exerciserewards`
- **語系**：只提供「繁體中文（台灣）」一種 App Store 語系（App 本身鎖 zh-Hant，不提供英文介面）
- **平台**：iOS 16.0 以上、僅 iPhone、僅直向
- **字數計算方式**：以字元數計（中文一字算一字元，標點、換行也各算一字元）。下列「實際」為本文件所附文案的實測值。

> 文案原則（沿用 `docs/copy-candidates.md`）：短、口語、動詞開頭、不用公文腔。
> 硬規則：**任何欄位都不得暗示與運動部或政府有關聯**，且第一段就要講清楚這是非官方工具。

---

## 1. App 名稱 / App Name

- **上限**：30 字元　**實際**：16 字元

```
Exercise Rewards
```

**說明**：對應 `App/project.yml` 的 `CFBundleDisplayName: Exercise Rewards`，兩者必須一致。

**為什麼是 `Exercise Rewards`，不是 `Sports Rewards`（2026-09-07 改名）**：運動部的英文名是
**Ministry of Sports**（本專案文件自己的譯法，見 `docs/release/review-notes.md`）。一個非官方 App
用 **Sports** Rewards 去做 Ministry of **Sports** 的獎勵活動，等於在英文名上與主辦機關共用關鍵字，
這是 Guideline 4.1（Copycats／Impersonation）與 5.2.1 的**裁量面**——審查員會不會往那個方向讀，
不在我們手上。`Exercise Rewards` 把那個字拿掉，語意（運動／獎勵）一點沒少，可裁量的空間卻小了一塊。
中文曝光不受影響：搜尋命中靠副標「揮汗有禮非官方串接」與 §5 的關鍵字，兩者都不含 Sports 或 Exercise。

**不可以用**「揮汗有禮」當 App 名稱——那是官方活動名稱，會踩 Guideline 4.1（Copycats／Impersonation）與 5.2.1；官方已在做「運動幣 App 需求調查」，官方 App 一出現風險會再升高（見 `docs/app-review-risk.md` 風險 #5）。名稱與圖示也不得含「運動部／政府／官方／500／國徽」等元素。

---

## 2. 副標題 / Subtitle

- **上限**：30 字元　**實際**：9 字元

```
揮汗有禮非官方串接
```

**說明**：定案文案（使用者指定）。這正是 `docs/app-review-risk.md` 降險清單第 1 條的做法——
**App 名稱用中性工具名（Exercise Rewards）、活動名只出現在副標並緊接「非官方」**，讓商店頁面
第一屏就同時交代「這是什麼活動的工具」與「它不是官方的」。

注意事項：
- 「非官方」三個字**必須**與活動名相鄰，不可拆開或省略，否則就變成用官方活動名為 App 命名，
  直接踩 Guideline 4.1（Copycats／Impersonation）與 5.2.1。
- 副標與名稱、圖示都不得出現「運動部／政府／官方／500／國徽」等元素。
- 日後若官方推出自己的 App，此副標的 impersonation 風險會升高，屆時需重新評估
  （見 `docs/app-review-risk.md` 風險 #5）。

先前草擬、未採用的候選（保留備查）：
- `看步數、管好券，非官方輔助工具`（15 字元）
- `記錄步數、管理加碼券的非官方工具`（16 字元）

---

## 3. 宣傳文字 / Promotional Text

- **上限**：170 字元　**實際**：76 字元（移除健康功能後重算）

```
這是協助你參加「揮汗有禮」活動的非官方個人工具——登入、看任務、挑品項、管理加碼券都在同一頁。開發者沒有伺服器，個資只留在你的手機，程式碼全部開源可查。
```

**說明**：Promotional Text 可不送審直接更新，適合放活動期程提醒。活動 14 期進行中時可換成「第 N 期上傳期到 M/D，別讓汗水白流」之類的短句，但**每次都要保留「非官方」三個字**。

---

## 4. 描述 / Description

- **上限**：4000 字元　**實際**：1165 字元（沿革：947 → 1133 → 1201（遙測改為同意後預設開啟）→ 1163（移除健康功能、新增「先看能換什麼」）→ **1165**（改名 Exercise Rewards，+2 字元）。仍遠低於上限）

```
Exercise Rewards 是一款非官方的個人輔助工具，協助你更省事地參加「揮汗有禮・全民動起來」運動幣加碼活動。本 App 由獨立開發者製作，與運動部及任何政府機關沒有隸屬、合作、贊助或授權關係，也不代表活動主辦單位。活動規則與最終權益一律以官方公告為準。

【它幫你做什麼】
・免重複打字：身分證號、出生日期、手機號碼填一次，之後一鍵登入官方「我的任務」。
・一眼看進度：14 期任務的狀態、開放時間與倒數，整理成看得懂的卡片。
・先看能換什麼：兌換前可以逐一查看每個超商／賣場的可兌換商品分類與品項，挑定了再送出。
・上傳不迷路：從相簿挑一張運動紀錄截圖，直接送到當期任務。
・券夾收好：兌換到的加碼券集中一頁，要用的時候直接出示條碼。

【你的資料在哪裡】
・開發者沒有伺服器。沒有自建後端，收不到也看不到你的身分資料。
・只連官方網站。App 自己發出的請求只會到 500.gov.tw，其他網域一律阻擋。
・只存這支手機。身分證號、出生日期、手機號碼加密保存在 iOS Keychain，不同步 iCloud、不寫入紀錄檔、不會提供給任何第三方。
・使用統計：先告知，同意後預設開啟。App 內建 Google Firebase 的匿名使用統計與當機回報。第一次打開 App 會先看到一頁簡介，按「開始使用」後緊接著就是一張免責聲明，上面就明寫這件事，你按下同意它才啟動——在那之前（含那頁簡介）Firebase 一行程式碼都不會執行。同意之後預設是開的，隨時可以到「我的資料」關掉。送出的只有「開了哪個畫面、哪一步失敗、有沒有當機」，不含身分證號、生日、手機號碼、你上傳的截圖與券碼。
・不看廣告、不被追蹤。沒有廣告、沒有廣告識別碼、不做跨 App 追蹤。
・隨時刪光。「我的資料」頁按下「立即清除本機資料」，就永久刪除。
・不做多餘蒐集。姓名、Email、健保卡卡號通通不收，只留登入必要的三個欄位。

【健康資料怎麼處理】
・完全不讀取。本 App 不讀取 Apple 健康的任何資料，也不會出現健康權限提示。
・不替你造資料。要上傳的截圖由你自己從相簿挑選，App 不會合成或修改任何運動數據。

【開源可稽核】
程式碼以 MIT 授權公開，處理個資與網路連線的每一行都可以自己看、自己查。

【使用前請先知道】
・你必須先在官方網站完成註冊，本 App 不提供註冊功能，也不會替你通過任何身分驗證。
・審核結果、兌換次數與券的使用權益，全部由官方網站決定，本 App 只是幫你少打幾次字。
・官方網站改版時，本 App 可能暫時無法運作。
・需要 iOS 16 以上，僅支援 iPhone 直向使用，介面為繁體中文。

【回報問題】
歡迎來信或到開源專案回報：megshao0918@gmail.com
```

**已填**：支援信箱 `megshao0918@gmail.com`（與 App Store Connect 開發者帳號一致）；另有 GitHub Issues：https://github.com/megshao/exercise_rewards_ios/issues

---

## 5. 關鍵字 / Keywords

- **上限**：100 字元（逗號分隔、**不含空白**）　**實際**：69 字元

```
運動幣,加碼券,超商券,兌換,券夾,達標,運動獎勵,運動紀錄,運動打卡,健走,走路,健身,任務,非官方,全民運動,兌換品項,超商,便利商店
```

**說明**：
- App 名稱裡的字（Exercise、Rewards）不必再寫進 keywords，Apple 已一併索引。
- 關鍵字已隨功能調整：移除「步數／計步／每日步數」等與步數讀取有關的字（App 不再顯示步數，留著會造成期待落差），改補活動與兌換相關字。送審前請重新確認總長度未超過 100 字元。
- **刻意沒放的字**：`揮汗有禮`、`運動部`、`500`。這些是主辦單位的活動名／機關名，放進關鍵字等於用他人名義導流，會加大 4.1／5.2.1 的裁量風險。

> 2026-09-07 定案：曾一度把 `揮汗有禮` 放進關鍵字，已移除。理由是**副標「揮汗有禮非官方串接」已經含這個詞，而 Apple 的搜尋同時索引名稱、副標與關鍵字**——在這個幾乎沒有競品的冷門活動詞上，靠副標本來就會排在前面，關鍵字再放一次的邊際收益接近零，卻多擔一份裁量風險。ASC 上的實際值與本節區塊一致，都不含活動名。

---

## 6. 更新說明 / What's New in This Version

- **上限**：4000 字元　**實際**：258 字元（沿革：239 → 284 → 308 → **258**（移除健康功能相關條目後重寫））

```
1.0 首次上架。

・一鍵登入官方「我的任務」：身分證號、出生日期、手機號碼只要填一次。
・14 期任務儀表板：狀態、開放時間與倒數一次看完，本週的排最上面。
・從相簿挑一張截圖，直接上傳到當期任務。
・兌換加碼券並收進券夾，要用時出示條碼。
・個資只加密存在本機 Keychain，可一鍵永久清除；開發者沒有自建伺服器。
・匿名使用統計與當機回報（Google Firebase）：首次啟動的免責聲明會先告知，你按下同意才會啟動，之後預設開啟、可隨時在「我的資料」關掉，不含個資。
・程式碼以 MIT 授權開源。
```

**說明**：首次上架時 What's New 欄位在部分情況下不會顯示，但 App Store Connect 仍要求填寫，照填即可。

---

## 7. URL 欄位

| 欄位 | 必填？ | 內容 | 狀態 |
|---|---|---|---|
| 支援 URL（Support URL） | **必填** | 需要一個能公開開啟、且有聯絡方式的網頁 | `https://megshao.github.io/exercise_rewards_ios/support.html` |
| 行銷 URL（Marketing URL） | 選填 | 產品介紹頁；沒有可留空 | `https://megshao.github.io/exercise_rewards_ios/`（首頁，可填可不填） |
| 隱私權政策 URL（Privacy Policy URL） | **必填** | 需要一個公開網址，內容須與 App 隱私標籤一致 | `https://megshao.github.io/exercise_rewards_ios/privacy.html` |

### 需要你補的內容

1. **支援 URL**：最省事的做法是用開源 repo 的 README 或 GitHub Pages。需要包含：App 名稱、聯絡信箱、「這是非官方工具」聲明、常見問題（登入失敗怎麼辦、官網改版怎麼辦）。
   - https://github.com/megshao/exercise_rewards_ios　/　https://megshao.github.io/exercise_rewards_ios/
   - megshao0918@gmail.com
2. **隱私權政策 URL**：必須是**獨立可直接開啟**的網址（不能只是 App 內頁面）。內容至少要寫清楚：
   - 開發者不營運任何伺服器，不接收、不儲存使用者的身分資料。
   - 使用者輸入的身分證號、出生日期、手機號碼只存在裝置本機 Keychain，登入時由裝置直送 `500.gov.tw`。
   - **資料送往 `500.gov.tw` 屬「與第三方分享」**，要明寫；並附上該網站自身的隱私政策連結。
   - 本 App 不使用 HealthKit，不讀取任何健康資料，亦未申請健康權限。
   - **匿名使用統計與當機回報**：使用 Google Firebase Analytics／Crashlytics；**首次啟動的免責聲明會先揭露，使用者按下同意才初始化 Firebase，同意後預設開啟、可隨時關閉**；送出什麼、送給誰（Google LLC，伺服器在美國）、怎麼關掉。**不得再寫「預設關閉」或「opt-in」。**
   - **網域白名單的界線**：App 自己只連 `500.gov.tw`，但 Firebase SDK 走自己的連線、不受該白名單管轄。
   - 使用者可隨時以「立即清除本機資料」永久刪除；刪除 App 亦同。
   - 聯絡方式與更新日期。
   - https://megshao.github.io/exercise_rewards_ios/privacy.html　（責任主體：megshao，個人開發者）
3. **行銷 URL**：可留空。若填，指向同一個 repo 頁面即可。

---

## 8. 分級問卷建議答案（Age Rating）

建議結果：**4+**。以下為 App Store Connect 分級問卷各題的建議勾選。

| 問卷項目 | 建議答案 | 依據 |
|---|---|---|
| 卡通或幻想暴力 | 無 | App 內無任何暴力內容 |
| 寫實暴力 / 血腥 | 無 | 同上 |
| 色情或裸露 | 無 | 同上 |
| 褻瀆或粗俗幽默 | 無 | 全部文案為中性說明文字 |
| 恐怖 / 驚悚題材 | 無 | 同上 |
| 酒精、菸草或毒品使用或提及 | 無 | 同上 |
| 成熟 / 煽情主題 | 無 | 同上 |
| 醫療 / 治療資訊 | 無 | App 只顯示活動任務進度與加碼券，**不顯示任何健康數值，也不提供任何醫療建議或健康診斷** |
| 模擬賭博 / 競賽 | 無 | 兌換是官方活動的既有機制，非賭博、無隨機獎項 |
| 不受限制的網頁存取 | **否** | App 不含瀏覽器；「前往官網註冊」是以外部 Safari 開啟固定網址，App 內沒有可任意瀏覽的 WebView |
| 使用者產生的內容 / 社群功能 | **否** | 無使用者互相可見的內容、無留言、無分享 |
| 內建購買 / App 內購買 | **否** | 完全免費，無 IAP |
| 抽獎 / 競賽（Contests） | **否** | App 本身不舉辦任何抽獎；兌換由官方網站處理 |
| 位置資訊分享 | **否** | App 不使用定位 |

**補充**：Apple 另會詢問是否為「Kids Category」——選**否**。

---

## 9. 類別建議（Category）

| 欄位 | 值（**已定案**） | 理由 |
|---|---|---|
| 主要類別 | **生活風格（Lifestyle）** | App 做的是「參加一個政府活動、管理手上的加碼券」，不量測也不追蹤任何運動表現。 |
| 次要類別 | **工具程式（Utilities）** | 另一半價值是「免重複輸入、代管券夾」的工具性質。 |

**為什麼從「健康與健身」改掉（2026-09-07，v1.0.0 送審前）**：
原本填健康與健身，理由是「核心畫面是今日步數、距離與達標判定，且使用 HealthKit」。
v1.0.0 把 HealthKit 整個移除之後，那個理由一條都不剩——App 不讀任何健康資料、
畫面上也不再出現任何運動數值。留在健康與健身會有兩個實際問題：

1. **與 App 內容不符**，審查員點開只看到任務清單與券夾，找不到任何健康功能。
2. **在該類別排行榜上與真正的健身 App 並列**，使用者下載後會有期待落差。

「工具程式」與「生活風格」都說得通，選後者是因為使用情境（參加活動、領獎勵）
比「工具」更貼近使用者為什麼裝它；工具性質留在次要類別。

**不建議**選「財務」「購物」——會讓審查員把兌換券誤解為金流／電商功能，徒增審查問題。

> ⚠️ 這一格改的是**文件**。App Store Connect 上的類別要另外到
> 「App 資訊 → 類別」手動改，改文件不會同步過去。

---

## 10. 其他送審欄位速查

| 欄位 | 值 | 依據 |
|---|---|---|
| 價格 | 免費 | 無 IAP、無訂閱 |
| 是否使用加密 | 已在 Info.plist 宣告 `ITSAppUsesNonExemptEncryption = false`，App Store Connect 不會再問 | `App/project.yml` |
| 廣告識別碼（IDFA） | **否** | 使用 `FirebaseAnalyticsCore`（底層 `GoogleAppMeasurementCore`），**結構上不含 IDFA 收集能力**；Release 二進位未連結 `AdSupport`／`AppTrackingTransparency`／`AdServices`（`otool -l` 可驗），因此不會出現 ATT 提示 |
| 是否含第三方內容 | 否 | App 內不顯示任何第三方內容。**但相依上有一個第三方 SDK**：firebase-ios-sdk 12.18.0（Analytics + Crashlytics），SPM 解析 13 個套件、實際連結 6 個——這一格問的是內容不是相依，答否，相依的部分寫在隱私標籤與 Review Notes |
| 版權（Copyright） | `2026 megshao` | 需與開發者帳號名稱相符 |
| 帳號刪除（Guideline 5.1.1(v)） | App 內提供「立即清除本機資料」；官方帳號本身需到 `500.gov.tw` 處理——需在支援頁面提供官網帳號管理的深連結 | `docs/app-review-risk.md`；`App/Sources/Views/ProfileView.swift` |

---

## 11. 送審前檢查清單

- [x] 描述最後一行已換成真實聯絡方式（megshao0918@gmail.com）
- [x] 支援 URL 與隱私權政策 URL 都已填且可公開開啟（另已填行銷 URL、分類、版權、分級問卷、第三方內容宣告）
- [ ] 隱私權政策內容與 `docs/release/privacy-labels.md` 的勾選完全一致
- [x] 示範帳號欄位已填入 `docs/release/review-notes.md` 所載的三碼
- [x] Review Notes 已貼上 `docs/release/review-notes.md` 的 **Part A-短**（Part A 有 31,016 字元，超過欄位 4,000 上限）
- [x] 截圖不含任何真實個資、不含政府識別標誌（7 張逐張目視確認，全為 `A000000000` / `1990/01/01` / `0900000000` 佔位值）
- [ ] App 內殘留的舊字樣已更新（見 `review-notes.md` §殘留待辦）
- [ ] 隱私標籤已依 `privacy-labels.md` **2026-09-06 大改後**的版本填寫（Identifiers › Device ID、Usage Data › Product Interaction、Diagnostics › Crash Data／Other Diagnostic Data 四格改為 Yes / Not Linked / 不追蹤）
- [ ] 隱私權政策網頁 §5「使用統計與當機回報」已上線，且與隱私標籤逐格對得上
- [ ] Firebase 主控台端設定已完成（資料保留最短、關 Google Signals、關廣告個人化、關精細位置、不開 BigQuery）——見 `privacy-labels.md` §6 的 TODO
- [ ] 送審用的 archive 內**確實**含有正式專案的 `GoogleService-Info.plist`（build 4 曾解包確認過；**build 5 要重新確認一次**，`.template` 不可被打包）
### 送審前剩下的（只剩隱私標籤要人工做）

- [x] **App Review Information 的聯絡人**：REDACTED / REDACTED、`+886REDACTED`、`megshao0918@gmail.com`（見 `review-notes.md` §8）
- [x] **價格與供應地區**：免費（`customerPrice 0 / proceeds 0`，基準地區 TWN），**只在台灣上架**——175 個地區只有 `TWN` 為 `available`，且 `availableInNewTerritories = false`，Apple 日後新增地區不會自動跟著上架。

  > `POST /v2/appAvailabilities` 不接受「只列出要開的地區」：只給 `TWN` 會被逐一退回其餘 174 個地區的 `RELATIONSHIP.INVALID`。必須把全部地區都放進 `included`，各自帶 `available` 布林值，並用 `${local-id}` 格式的 inline id。
- [ ] **App Privacy 隱私標籤**：App Store Connect **沒有開放 API**，只能在網頁後台照 `privacy-labels.md` 逐格勾。
- [ ] **What's New**：首次上架的版本記錄不接受這個欄位（API 回 `STATE_ERROR: Attribute 'whatsNew' cannot be edited at this time`），文案留在本文件 §6 待 1.0.1 用。

