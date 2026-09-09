# App Store 審查風險評估（Exercise Rewards・非官方 App）

研究基礎：Apple App Review Guidelines（2026-06 現行版）、Apple 開發者論壇判例、WebKit 官方部落格、活動辦法媒體轉述。

## 總體
- **現況設計：中高風險（偏會被拒）。做完降險後：中風險，殘餘風險無法歸零。**
- thin wrapper(4.2) 反而**低風險**（我們大多原生，WebView 只在註冊）。

## 主要風險（依拒審機率排序）
| # | 風險 | 條號 | 說明 |
|---|---|---|---|
| 1 | 審查員**無法實測**（需真實健保卡+戶役政+台灣簡訊） | 2.1(a) | 幾乎必先卡這關 → 需 Demo Mode + 示範影片 |
| 2 | 非官方抓政府網站、無授權，活動辦法禁自動化工具 | 5.2.2 / 5.2.1 | 「Authorization must be provided upon request」你拿不出 |
| 3 | 蒐集身分證/健保卡等敏感資料，服務提供者是運動部 | 5.1.1(ix) | 須由提供服務之法人提交；**個人帳號幾乎必拒** |
| 4 | ~~讀 HealthKit 步數上傳換券~~（**v1.1 起功能已完全移除，本風險消除**） | 5.1.3(i) | 逐字：健康資料換利益須「由提供利益之實體提交，且不得分享第三方」——兩項都不符。現況：App 完全不讀健康資料，本條不再適用 |
| 5 | App 名稱直接用活動名「揮汗有禮」 | 4.1(c)/5.2.1/4.1(b) | 官方已在做「運動幣 APP 需求調查」，官方 app 一出→impersonation 風險升 |
| 6 | 在政府身分驗證頁 cp.gov.tw 注入 JS | 5.1.1(vi)/WebKit App-Bound Domains 立場 | 審查員會問「在身分驗證頁注入腳本還能讀到什麼」→難辯護，**建議全移除** |
| 7 | 只是包網站的殼 | 4.2 | 低（大多原生） |

## 其他條款
- 4.8 登入服務：政府/電子ID 驗證屬**例外**，不需 Sign in with Apple。
- 5.1.1(v) 帳號刪除：需提供 App 內刪除或深連結到官網帳號管理 + 「清除本機資料」。
- 2.3.1(a)：新功能（含注入 JS 自動填）**必須在 Review Notes 具體說明**，否則算 undocumented feature（可能升級為 Code of Conduct）。
- 4.0：政府網站改版即失效 → 「stop working may be removed」。

## 「WebView 註冊」四方案（審查風險比較）
| 方案 | 做法 | 風險 | UX |
|---|---|---|---|
| A 現況 | WKWebView 注入 JS 自動填+自動翻頁，cp.gov.tw 也注入 | **高** | 最好 |
| B 受限預填 | `WKAppBoundDomains=[500.gov.tw]`，只在 500 預填、**不自動送出/翻頁**、每步使用者按；cp.gov.tw 注入技術上關閉、使用者自行輸入；預填前原生確認卡 | **中** | 略降 |
| C 系統瀏覽器+剪貼簿 | SFSafariViewController/ASWebAuthenticationSession 開官方頁，App 提供「複製各欄位」讓使用者貼上 | **低** | 明顯變差 |
| D 不做註冊 | 只服務已註冊者；「尚未註冊？」用 UIApplication.open 開 Safari 到官網；App 不碰身分證/健保卡/生日 | **最低** | 首次多一步（註冊 14 週只做一次） |

**建議**：公開商店走 **D**（退而求其次 C）；TestFlight 測試版可用 **B** 觀察 Beta App Review。**A 不建議提交。**

## 具體降險清單
1. **改名**：中性工具名（例「汗幣助手」「步步有禮」），副標才寫「揮汗有禮活動非官方輔助工具」；名稱/圖示不得含 運動部/政府/官方/500/國徽。啟動頁+「我的資料」頁（安全與隱私區塊底部）+商店描述三處放非官方聲明。開源連結放描述與 Review Notes（透明佐證）。
2. **組織帳號**提交（5.1.1(ix)）。
3. 身分證/健保卡/生日**不落 Keychain**（用完即清；Keychain 只留 session/登入所需）。目前已不存健保卡；idNo 為登入必需仍存——可評估。
4. **~~HealthKit 只讀不傳~~ → v1.1 直接不讀**：健康連結功能整個移除（entitlement、權限字串、健康分頁、首頁步數環全刪）；上傳一律用 `PhotosPicker` 讓使用者自選截圖。→ 隱私標籤 Health=Not Collected，理由從「讀了但沒送出」變成「根本沒讀」。
5. **移除 cp.gov.tw 上一切 JS 注入**；若保留 500 預填，設 `WKAppBoundDomains=[500.gov.tw]` 並於 Review Notes 附 Info.plist 截圖佐證邊界。
6. **Demo Mode**（Review Notes 指定開啟）mock 全部端點跑完整流程 + 真機示範影片。
7. **主動聯繫運動部**求書面「知悉不反對」（5.2.2 授權文件）；若明確反對＝不該上架公開商店的訊號。
8. 隱私權政策：明寫開發者不營運伺服器、不接收任何資料；資料送 500.gov.tw 屬「與第三方分享」，隱私標籤如實勾。

## 散佈管道
| 管道 | 適合度 |
|---|---|
| App Store | 目標，但需先做完降險；殘餘風險在 |
| **TestFlight 外部（≤10000人）** | **建議先走**，涵蓋 14 週活動期、試 Apple 反應 |
| Ad Hoc（100 台） | 只夠親友 |
| Enterprise | 僅限組織員工內部，**不可對外** |
| 開源+使用者自簽(AltStore/Xcode) | 與開源定位相符，公開商店被拒的後路 |

## 殘餘風險（做完仍無法消除）
1. 5.2.2 授權：功能本質是「非官方 client 操作政府網站」，隨時可能被要求授權文件。
2. 5.1.1(ix)/5.2.1：政府服務+敏感個資，提交者身分審查（COVID 判例）自由裁量大。
3. 官方 app 出現 → 4.1(b) impersonation + 被檢舉下架。
4. 網站改版即失效（4.0）。

## 主要引用
- Guidelines: https://developer.apple.com/app-store/review/guidelines/ （§2.1,2.3.1,4.1,4.2,4.8,5.1.1,5.1.3,5.2.1,5.2.2）
- App Review 提交/demo/影片: https://developer.apple.com/distribute/app-review/
- App-Bound Domains（注入立場）: https://webkit.org/blog/10882/app-bound-domains/
- DTS WKWebView 注入回覆: https://developer.apple.com/forums/thread/718101
- 5.1.1(ix)/5.2.1 判例: forums 131731 / 129290 / 750018 / 683829；5.2.2: forum 115490
- 帳號刪除: https://developer.apple.com/support/offering-account-deletion-in-your-app/
- TestFlight: https://developer.apple.com/testflight/

（未查得：500.gov.tw/sports.gov.tw 活動辦法原文因 cookie/403 無法抓，「自動化工具」條款依康健等媒體轉述。）
</content>

---

## 1.0 送審版落實狀態（2026-09-05 自審）

對照上面「具體降險清單」逐項：

| # | 降險項目 | 1.0 狀態 | 依據 |
|---|---|---|---|
| 1 | 改名為中性工具名 | ⚠️ 部分 | `CFBundleDisplayName = Exercise Rewards`、商店名稱與副標已定案（副標「揮汗有禮非官方串接」——活動名緊接「非官方」）；**但首頁標頭仍以大字自稱「揮汗有禮」**（`HomeView`），見下方決策紀錄 |
| 2 | 組織帳號提交 | ❌ 未做 | 仍為個人開發者帳號（`DEVELOPMENT_TEAM: 8DVXA389TX`）——**5.1.1(ix) 殘餘風險最高的一項** |
| 3 | 身分證/健保卡/生日不落 Keychain | ⚠️ 部分 | 個資已最小化到登入必需三欄（身分證／生日／手機）；姓名／email／**健保卡卡號完全不收集**；idNo 與 birthDate 為登入必需仍存 Keychain |
| 4 | HealthKit 完全不使用 | ✅ 已做（v1.1 強化） | 1.0 已移除「以 HealthKit 數據產生上傳圖卡」路徑；**v1.1 進一步把整個健康連結功能刪除**——無 entitlement、無權限用途字串、原始碼無 `import HealthKit`。5.1.3(i) 從「需要辯護」變成「不適用」，遙測裡也不再有任何健康相關事件（見下方重評 §R1） |
| 5 | 移除 WebView JS 注入 | ✅ 已做 | 全專案無 `WKWebView`／`WebKit`（`grep` 零命中），註冊改以外部 Safari 開官網 → 等同上表方案 **D** |
| 6 | Demo Mode + 示範影片 | ⚠️ 部分 | `App/Sources/App/DemoMode.swift` 已實作（哨兵三碼、全 Mock、常駐橫幅、個資只在記憶體）；示範影片與 Review Notes 文字待補 |
| 7 | 聯繫運動部取得「知悉不反對」 | ❌ 未做 | 5.2.2 授權文件仍拿不出 |
| 8 | 隱私權政策 + 隱私標籤如實勾 | ⚠️ 文件已備妥，**ASC 尚未填** | 需在 App Store Connect 填。Health 仍為 Not Collected（不傳給開發者，也不進遙測）；身分資料屬「與第三方（500.gov.tw）分享」；**2026-09-06 起另有四格因 Firebase 改為 Collected / Not Linked**——Identifiers › Device ID、Usage Data › Product Interaction、Diagnostics › Crash Data、Diagnostics › Other Diagnostic Data。逐格答案見 `spec/release/privacy-labels.md`（2026-09-06 大改版）|

### 決策紀錄：首頁標頭保留「揮汗有禮」（2026-09-05）

使用者在知悉風險後決定，`HomeView` 的首頁標頭**維持以大字顯示「揮汗有禮」**，理由是活動參加者的辨識度。

- **曝險**：這是全 App 對 4.1／5.2.1 曝險最大的一處。審查員打開 App，最顯眼的自稱是官方活動名，
  而商店名稱是 Exercise Rewards——兩者不一致，且等同以官方活動名自稱。官方日後推出自有 App 時，
  這裡會是最先被指為 impersonation 的地方（風險 #5）。
- **已採取的緩解**：在 Review Notes 的 4.1 段落**主動揭露**此事，說明它是對「本 App 協助的活動」的
  描述性引用而非身分宣稱，並表明若審查團隊希望移除，立即照辦。主動講遠優於被審查員自己發現。
- **其餘自稱處已對齊**：Onboarding 主標、「我的資料」頁尾（`Exercise Rewards v1.0.0 · 非官方工具`）、
  商店名稱與描述，全部使用 Exercise Rewards。
- **若因 4.1／5.2.1 被退**：第一個該改的就是這個標頭，成本只有一行文字。

### Review Notes 必須主動揭露的三件事（2.3.1）
1. **示範模式**：入口就是登入表單，輸入 `A000000000` / `1990-01-01` / `0900000000` 即進入；
   全程不連線官方網站、資料為範例。（此三碼須同步填進 App Store Connect 的示範帳號欄位。）
2. **本 App 為非官方工具**，以一般 HTTP client 操作使用者本人在 `500.gov.tw` 的帳號，
   不繞過任何身分驗證，開發者不營運任何自建伺服器（開源連結一併附上；唯一的第三方相依與遙測見第 5 點）。
3. **`WKAppBoundDomains` 的宣告用意**：本 App 目前完全不使用 WKWebView，該鍵是前瞻性防護宣告
   而非既有 WebView 的設定；若審查員質疑，可直接說明並移除。
4. **看截圖畫面會連到官方網站回傳的圖片儲存網域**：`GET /member/screenshot/{uuid}` 由官方站
   302 到一個自帶簽章的圖片網址。這是白名單（`500.gov.tw`）唯一的刻意例外，只讀取使用者本人
   上傳的圖片。**兩道自己的關卡**：`TasksService.screenshotImageURL` 先驗證該 `Location`
   必須是 `https` 且 host 通過 `isAllowedHost` 或 `*.amazonaws.com`；`ScreenshotView` 再用
   **專用的 `URLSession`**（`ephemeral`、`httpCookieStorage = nil`、`urlCache = nil`）下載。
   **刻意不用 `AsyncImage`**——它走 `URLSession.shared`，而那個 cookie jar 就是
   `HTTPCookieStorage.shared`，與 App 自己的 session 同一個；擋住外洩的是 cookie 的
   domain scope，不是「這條路徑沒有 cookie」，兩者在 `Location` 指回官方站同源時就有差。
5. **第三方 SDK：Firebase Analytics／Crashlytics**（2026-09-06 新增，同日二次修訂預設值）。
   **首次啟動的免責聲明會明白揭露它，使用者按下「同意並開始使用」時才初始化 Firebase——在那之前一行程式碼都不執行；
   同意之後預設開啟**，可隨時在「我的資料 › 安全與隱私 › 傳送匿名使用統計」關閉。Info.plist 四個旗標仍為 `false`，
   但那是冷啟動預設值（守住「還沒 `configure()` 就絕不收集」），**不是「預設關閉」**。
   **絕不含任何個資**（v1.1 起 App 也不存在任何健康資料可送）。要一併說明兩件事：
   (a) 網域白名單管不到 SDK 自己的連線，不要讓「只連 500.gov.tw」看起來比實際範圍大；
   (b) **審查員自己的裝置會連一次 Google**——免責聲明擋在 Onboarding 之前、示範模式在 Onboarding 之後，
   所以順序是「先同意（Firebase 於此初始化）→ 才進示範模式」。主動講，不要等審查員自己發現。
   詳見 `spec/release/review-notes.md` §2／§5b。


---

## 2026-09-06 變更：加入 Firebase Analytics／Crashlytics 後的風險重評

**變更內容**：加入 `firebase-ios-sdk` 12.18.0（product：`FirebaseAnalyticsCore`、`FirebaseCrashlytics`、`FirebaseCore`）。
SPM 解析 13 個套件、實際連進二進位 6 個。

**2026-09-06 二次修訂（遙測預設值）**：`Telemetry.defaultEnabled` 由 `false` 改為 `true`，初始化時機綁到**首次啟動免責聲明的同意**上
（`DisclaimerConsent.record()` → `Telemetry.configure()`）。正確敘述是「先告知 → 使用者主動同意 → 之後預設開啟 → 隨時可關」，
**不是 opt-in**。本節下方的逐條重評已依此更新，新增的部分標為「二次修訂」。
決策紀錄與代價見 `spec/PRD.md` §8.2；量測設計見 `spec/analytics-plan.md`。

### 總體風險變化

**中風險 → 中高風險。** 這次變更沒有新增任何「會被直接拒審」的行為，但拿掉了一個最省事的辯護句
（「binary 裡根本沒有第三方 SDK」），把兩條原本不必解釋的題目變成必須主動解釋。
**風險的形態從「行為風險」變成「一致性風險」**：實作沒問題，出問題會出在文件、標籤與實作三者對不齊。

### 逐條 guideline 重評

| # | 條號 | 變更前 | 變更後 | 說明與應對 |
|---|---|---|---|---|
| R1 | **5.1.3(i)** 健康資料 | 高風險，但辯護乾淨：「binary 裡沒有任何第三方 SDK」 | **仍高風險，辯護變長** | 一個帶 HealthKit entitlement 的 App 裡出現 Google SDK，審查員必然會問「健康資料有沒有進 Firebase」。**事實上沒有**：`AnalyticsEvent`／`UserProperty`／`CrashKey` 都是封閉列舉，沒有任何成員帶步數、距離、運動時間，**連「今日是否達標」這種由步數推導的布林值都刻意不送**（`Telemetry.swift` 檔頭列為禁止項第 2 條，並引用本條為理由）。唯一沾邊的是 `health_link_tap`——「使用者按了連結 Apple 健康的按鈕」這個純 UI 動作，按下當下 HealthKit 尚未被呼叫，**授權結果也不送**；`UserProperty` 是不可建構的空列舉，完全不設任何使用者屬性。**應對**：Review Notes §5b 與 §7 的 5.1.3(i) 段已逐點主動揭露；隱私標籤 Health / Fitness 維持 Not Collected。**這是本次變更代價最高的一格。**<br>**二次修訂後：風險等級不變。** 遙測「送得出去的東西」是封閉列舉決定的，跟預設值無關；預設開啟不會讓任何健康資料變得送得出去。改變的只有「審查員實際會看到 Firebase 在跑」，所以 5.1.3(i) 的解釋從「可能被問」升級成「一定會被問」——但答案與證據完全相同。 |
| R2 | **5.1.1(ix)** 敏感服務的資料蒐集 | 高風險（政府服務 + 身分證號 + 個人開發者帳號） | **略升** | 原本可以說「開發者什麼都收不到」。現在要改成更精確的版本：**身分資料仍然一筆都不進遙測**（任何形式，含雜湊、截斷、拼接），開發者收到的只有匿名操作事件與當機報告。**應對**：Review Notes 的 5.1.1(ix) 段已改寫成「邊界式」論述，不再宣稱「什麼都沒有」。**真正的主風險仍是提交者身分（個人 vs 組織帳號），這一點沒有因為 Firebase 而改變。**<br>**二次修訂後：風險等級不變。** 身分資料進不進遙測，是封閉列舉與六道閘門決定的，跟預設值無關。可辯護的部分反而變強了一點：揭露從「設定頁第三層的開關」升級成「進 App 必經、必須主動勾選的阻斷式畫面」。 |
| R3 | **5.1.1／5.1.2** 隱私標籤一致性 | 低（幾乎全 Not Collected，不容易填錯） | **明顯升高，且是本次最容易踩到的一條** | 四格從 Not Collected 改為 Collected（Identifiers › Device ID、Usage Data › Product Interaction、Diagnostics › Crash Data、Diagnostics › Other Diagnostic Data）。標籤不實可導致下架與 metadata 違規。**應對**：依 `spec/release/privacy-labels.md`（2026-09-06 大改版）逐格填，並與 `App/Resources/PrivacyInfo.xcprivacy` 交叉核對——最終隱私報告是 App manifest 與所有 SDK manifest 的聯集，問卷不能比它少。**Location › Coarse Location 仍是 `TODO(待確認)`。**<br>**二次修訂後：逐格答案（Collected／Linked／Tracking／Purpose）一格都沒有變**，理由見 `privacy-labels.md` 前提 C——Optional Disclosure 豁免在改動前就不成立，改成預設開啟只會更不成立。但**風險強度升高**：改動前實務上多數使用者不會打開，現在同意即開始收集，所以「標籤要與實際行為一致」從理論義務變成每一台裝置上都在發生的事實。 |
| R4 | **2.3.1** 準確的 metadata／無隱藏功能 | 低 | **低，但多一項要講** | 遙測開關是使用者看得到的設定，不是隱藏旗標；但 Crashlytics 會向 `firebase-settings.crashlytics.com` 取自己的設定，這在字面上是一種「遠端設定」。**應對**：Review Notes 的 2.3.1 段已主動說明——那是 Google SDK 自我設定，改變不了本 App 的任何行為或功能，且我們自己沒有任何 remote config 或 feature flag 服務。<br>**二次修訂後：這是唯一風險形態真的改變的一條，但仍是低。** 2.3.1 管的是「描述與實際是否一致」。只要商店描述、隱私政策、官網、Review Notes、隱私標籤五處都寫「同意後預設開啟」而不是「opt-in／預設關閉」，就沒有問題；**風險完全來自文件沒改乾淨**，不是來自行為本身。舊稿的「預設關閉」「出廠是關的」「opt-in」字樣已全面清除，日後複貼回來就是不實陳述。 |
| R5 | **2.1** App 完整性／審查可測 | 中（靠示範模式） | **不變（但一句舊承諾被推翻）** | 示範模式仍完全不發 App 自己的網路請求、一個遙測事件都不送，且會強制關閉 SDK 收集旗標。**二次修訂推翻的舊承諾**：「示範模式下對 Google 零連線」**不再成立**。免責聲明擋在 Onboarding 之前（`RootView` 依 `disclaimerAgreedVersion` 判斷），示範模式卻是在 Onboarding 的登入表單輸入示範三碼才進入的（`OnboardingView`／`enterDemoIfSentinel`），所以審查員的實際路徑是「同意免責聲明 → **Firebase 在此初始化、送出 `first_open`、Installations 連線一次** → 才進示範模式」。時序改不掉：示範模式也走 `finish()`，無法用 `hasCompletedOnboarding` 事先區分；要避開就得把初始化延到真實登入成功，那會失去整個 onboarding 漏斗。**應對：在 Review Notes §2 與 §5b 主動告知審查員這個時序**——審查員自己發現一個沒人提過的 Google 連線，比我們先講糟得多；而且這個時序本身就是最好的證明：**任何東西被收集之前，一定先出現揭露畫面**。**副作用不變**：審查期間的當機仍收不到（示範模式擋住），送審前自行在示範模式跑完整流程作為補償。 |
| R6 | **3.1 / 廣告與追蹤** | 不適用 | **仍不適用** | 用 `FirebaseAnalyticsCore`（底層 `GoogleAppMeasurementCore`），結構上不含 IDFA 收集能力；Release 二進位未連結 `AdSupport`／`AppTrackingTransparency`／`AdServices`（`otool -l` 可驗）。因此 `NSPrivacyTracking = false`、無追蹤網域、不需要也不可能出現 ATT 提示。 |
| R7 | **4.0 / 官網改版即失效** | 中（只能等使用者來信） | **降低（二次修訂後降得更多）** | 這是加 Firebase 的主要理由：非致命錯誤可以在官網改版時提供最早的警報，縮短「壞掉 → 修好」的時間。**二次修訂**：改成「同意後預設開啟」之後，實際回報的裝置比例大幅提高，警報才真的有樣本可用——這正是改預設值的動機。樣本仍會偏向「沒有主動去關掉開關」的人。 |
| R8 | **5.2.2 授權文件／官方 App 出現（4.1）** | 高 | **不變** | 與遙測無關，仍是全案殘餘風險最高的兩項。 |

### 這次變更帶來的新硬約束（違反即為不實陳述）

以下四句同時出現在 `README.md`、`CHANGELOG.md`、`docs/privacy.html` §5、`docs/index.html`、
`spec/release/app-store-metadata.md`、`spec/release/review-notes.md` §5b 與隱私標籤。任何一句在程式碼裡變成假的，
上述所有文件都要同步改：

1. ~~**遙測預設關閉**（`Telemetry.defaultEnabled == false`）~~ → **2026-09-06 二次修訂，已作廢。** 取而代之的是：
   **同意之前 Firebase 一行程式碼都不執行**——`DisclaimerConsent.record()` 必須含 `Telemetry.configure()`，
   `Telemetry.configure()` 的三道 guard（未同意免責聲明／使用者關閉／示範模式）必須都在，
   `DisclaimerView` 的揭露文案必須含「匿名使用統計」，Info.plist 四個旗標必須維持 `false`（冷啟動預設值）。
   這是現在唯一支撐所有對外敘述的技術事實。
2. **個資零外傳**（三個登入欄位任何形式都不進遙測）。
3. **完全不讀取健康資料**（v1.1 起；在那之前是「唯讀且零外傳，連推導結論也不送」）。
4. **不連結廣告識別框架**（`AdSupport`／`AppTrackingTransparency`／`AdServices`）。
5. **對外文案不得出現「預設關閉」「出廠是關的」「opt-in」「使用者自己打開才會送」**——這些現在都是不實陳述。

建議把這五條做成 CI 檢查（見 `spec/PRD.md` §8.5）。`TODO(待確認：CI 檢查尚未建立)`

### 送審前必做

- [ ] App Store Connect 隱私標籤依 `privacy-labels.md` 2026-09-06 版填寫，並與 `PrivacyInfo.xcprivacy` 對齊
- [ ] `docs/privacy.html` §5 已上線（隱私政策 URL 的內容須與標籤逐格一致）
- [ ] Review Notes 貼上含 §5b 的版本（**必須是二次修訂版**：含「同意後預設開啟」與「審查員會先同意、Firebase 於此初始化、之後才進示範模式」的時序說明）
- [ ] 全文 grep 一次 `預設關閉`／`出廠是關`／`opt-in`／`自己打開`，確認送審資料裡沒有殘留舊敘述
- [ ] archive 內確實含正式的 `GoogleService-Info.plist`（不進版控，缺檔時遙測全程 no-op）
- [ ] Firebase 主控台：資料保留設最短、關閉 Google Signals、關閉廣告個人化、關閉精細位置、不開 BigQuery、限制 API key 的 bundle ID
