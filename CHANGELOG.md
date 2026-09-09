# Changelog

本檔案記錄 Exercise Rewards（bundle id `com.megshao.exerciserewards`）的所有重要變更。
格式依循 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，版本號依循 [語意化版本](https://semver.org/lang/zh-TW/)。

---

## [1.1.0] - 2026-09-09

### Added

- **官網改版時交接到官方網站，而不是誤報成網路錯誤**（#3）。這支 App 以正規表示式讀
  `500.gov.tw` 的 HTML，官網一改版所有已安裝的版本會同時失效，而重送審要好幾天。原本這種失敗
  顯示的是「無法載入任務資料，請確認網路連線後重新整理」——歸因錯了，使用者會去重設 wifi 來
  應對一個伺服器端的改版。現在改成說清楚發生什麼事，並把使用者交接到還能服務他的官網頁面。
  任務／首頁／兌換／券碼／券夾五頁都接上；已有資料的畫面保留資料並在頂端掛 banner 說明可能過期，
  而不是靜默沿用快取。
- **券夾的已兌換券卡可以「查看可兌換品項」**（#7）。已兌換的期別在官網已經沒有兌換頁，而品項頁
  連結只長在兌換頁上，所以路徑改用三層解析：兌換當下記在本機 → 借用還可兌換期別的官網清單 →
  公開的離線備份快照。三層都拿不到就不顯示那顆按鈕。
- **廠商品項目錄的離線備份**（#7）。`VendorCatalogService` 從 GitHub Pages 下載一份公開快照，
  在官網品項頁載不到時接手顯示，畫面會標註擷取日期。快照用 `Scripts/capture-vendor-catalog.py`
  產生，完整性以官網自己印的品項數校驗。

### Changed

- **「我的資料」的三個欄位改為唯讀**（#6）。它們是官網的登入憑證，在 App 內改不會變更官網上的
  任何資料，只會讓下一次登入失敗——而失敗的原因（憑證被改過）從畫面上完全看不出來。個資唯一的
  寫入點回到首次設定。「儲存到本機」按鈕一併移除。
- **「立即清除本機資料」改名為「立即登出並清除本機資料」並獨立成「換帳號」區塊**（#6）。
  這支 App 沒有伺服器也沒有帳號切換的概念，換身分就是把本機憑證清乾淨再重新登入；原本它是
  設定清單裡的一列，看起來像另一個設定項。清除範圍沒有縮小。
- **「檢視券碼」改名為「顯示加碼券條碼結帳」**（#7）。它會走一次簡訊驗證並出示條碼，是到櫃檯
  要按的那顆，不是單純檢視。
- **任務卡的「檢視加碼券」只切換到券夾分頁**（#7）。券夾才是這張券的完整入口，直接跳進簡訊驗證
  會把使用者推進一條他還沒決定要走的流程。
- **看完條碼關閉後一律回到「我的券夾」**（#5）。券碼頁可能是從券夾、任務、首頁或兌換結果卡
  （sheet 疊 sheet）打開的，原本關閉會停在打開它的那一層。
- **隱私揭露不再無條件宣稱「只連 500.gov.tw」**（#7）。多了一個唯讀、無 cookie、零上傳的公開
  備份檔出口，所以隱私權政策、官網首頁、商店描述與 `README` 都改成「帶著登入狀態的連線只到
  500.gov.tw」並明列例外。政策也誠實寫明 GitHub 會看到 IP 與時間。

<!-- 以下為 1.1.0 期間的其餘變更 -->

### Fixed

- **兌換頁按「確認兌換」不再是空操作**（#4）。alert 的 `isPresented` binding 在 `set` 裡把
  待確認的品項清成 nil，而 SwiftUI 是**先關 alert 再執行按鈕的 action**，所以 `confirmRedeem()`
  的 guard 永遠先失敗——dialog 開得起來、關得掉，但兌換從來沒送出去。連帶修正遙測：原本每次
  確認都被記成一次 `redeem_cancel`，而 `redeem_submit` 一次都沒送出過。
- **兌換鈕整顆都可點**（#4）。`padding` 與背景畫在 `Button` 外側，版面撐大了但可點區仍只有文字
  本身——實機量到可點區 26×15.7pt、色塊 58×35.7pt，約八成面積是死區。
- **從券夾兌換完，該期不再停在「可兌換」**（#5）。券夾的兌換 sheet 少了 `onDismiss` 重抓；
  隔壁券碼 sheet 「不需要重抓」的理由（只動本機標記）被誤套到它身上，但兌換改的是官網端狀態。
- **首次設定選完出生日期後，焦點自動移到手機號碼**（#6）。滾輪是那張表單裡唯一填完不會接到
  下一格的欄位（不吃鍵盤，所以沒有 next／return）。
- **首頁「本週任務」與任務頁置頂高亮不再卡在第 1 期**。判斷「當期」的規則原本是
  「清單裡第一個非『尚未開始』的期別」，**完全沒有讀期別的日期**。官網回的卡片是 1→14 遞增，
  第 1 期一旦走到「可兌換」或「已兌換」就永遠不再是「尚未開始」，於是它永遠是第一個符合的
  ——當期會整整 14 期停在第 1 期，一次都不前進。2026-09-07 回報的「已經 9/7 了，還顯示
  9/1~9/6 為當週」就是這個 bug 的第一天。
  - 現在改依台北時間的日曆判斷：今天落在哪一期的起訖日之內就是哪一期；活動尚未開始顯示最早一期，
    全部結束則停在最後一期。
  - 官網若改掉日期格式而全部期別都解析不出來，會退回舊的狀態啟發式而不是留白——
    官網的 markup 不是契約，猜錯一期仍好過整個區塊空白。
- **過期未上傳的期別不再顯示「上傳運動紀錄」按鈕**。官網對上傳窗已關的卡片照樣回
  `NOT_UPLOADED`，也照樣附「剩 N 小時」倒數，而 App 判斷能否上傳只看這個狀態。結果使用者可以
  點進上傳頁、選好照片、按下「確認上傳」，**送出之後**才被伺服器以「目前不在可上傳期間」擋下來。
  現在期別結束當天午夜一過，按鈕就換成「本期上傳期間已結束」，倒數不再顯示，狀態徽章由
  「未上傳」改為「已結束」。
  - 伺服器端那道檢查（`UploadService` 的 `windowClosed`）保留不動，仍是最終權威。

### Changed

- **App 名稱改為 `Exercise Rewards`**。運動部的英文名是 Ministry of Sports；非官方 App 用舊名
  去做該機關的獎勵活動，在英文名上與主辦機關共用 Sports 這個關鍵字，是 Guideline 4.1／5.2.1 的裁量面。
  改為 Exercise Rewards 拿掉那個字。中文曝光不受影響——搜尋命中靠副標與關鍵字，
  兩者都不含 Sports 或 Exercise。
  - 同時 bundle id 改為 `com.megshao.exerciserewards`、GitHub repo 改為 `exercise_rewards_ios`
    （皆因尚未發布任何版本而可以重建）。GitHub Pages 的隱私權政策與支援網址跟著移到新的 repo 名下，
    App Store Connect 兩個網址欄位與 App 內的連結一併更新。
  - Swift Package、Xcode target 與 scheme 同步改名為 `ExerciseRewardsKit`／`ExerciseRewards`。
  - 本檔案 1.0.0 及之前的歷史條目一併改名：從未有以舊名發布出去的版本，
    不存在需要保留原名的已發布事實。
- 判斷當期的規則從 App 的 View 層搬進 `ExerciseRewardsKit`（`TaskPeriod.current(in:now:)`），
  並補上單元測試——它是領域規則而非排版，先前在 App module 內完全無法被測試覆蓋。
- 示範模式的 14 期資料改為**依當下日期動態產生**（第 6 期永遠是本週），順序也改回 1→14。
  舊版寫死日期、又刻意把當期排到陣列第 0 位好讓「取第一個非尚未開始」剛好選中它，
  等於用示範資料把正式站的 bug 蓋住，截圖測試因此驗不到。


## [1.0.0] - 2026-09-07

首次公開發行的送審版本（`CFBundleVersion` = 6，對應 git tag `v1.0.0`）。

> build 4 曾於 2026-09-06 上傳過，但下方所有變更都發生在那之後。
> build 5 只在本機封存、未上傳，之後又修掉「本週任務不會換期」與「過期期別仍可點上傳」
> 兩個 bug，因此 1.0.0 實際送審的是 build 6；build 1–5 皆作廢。

### Removed

- **Apple 健康連結（HealthKit）整個功能移除**。不再讀取步數、步行與跑步距離、運動時間，也不再判斷「今日是否達標」。
  一併刪除的東西：`HealthKit` entitlement、`NSHealthShareUsageDescription` 與 `NSHealthUpdateUsageDescription`
  兩個權限用途字串（使用者不會再看到健康權限提示）、「健康」分頁、首頁的今日步數環、
  `HealthReading`／`HealthSummary`／`GoalEvaluator`／`HealthKitReader`，以及遙測的 `health_link_tap` 事件與 `health` 畫面。
  原始碼中已無任何 `import HealthKit`。
  - **對送審的影響**：Guideline 5.1.3(i)（健康資料換取獎勵）與「帶 HealthKit entitlement 的 App 裡出現 Google SDK」
    這兩個原本最高的風險一起消失。隱私標籤 Health / Fitness 仍是 Not Collected，但理由從「讀了但從未離開裝置」
    變成「根本沒有讀」。相關文件（`docs/release/review-notes.md` §4、`docs/release/privacy-labels.md` §2）已同步改寫。
  - 舊版寫在 UserDefaults 的健康授權旗標，會在「立即清除本機資料」時一併清掉。

### Added

- **加碼券可標記「已使用」**。券已經在門市用掉之後，就不該再出現「顯示條碼」——
  但**官網沒有這個狀態**：實測一張已經用掉的券，`/member/tasks` 仍然是 `REDEEMED`「已兌換」、
  仍然掛著「檢視加碼券」連結，券碼頁（OTP 關卡）也與沒用過的券完全一樣。
  因此改由使用者自己告訴 App：
  - 出示條碼之後，券碼頁底部會問「已經在門市用掉了嗎？」，可一鍵標記。券夾的券卡上也有同樣的入口。
  - 標記後該張券在首頁與券夾都轉灰、標「已使用」，**不再顯示「顯示條碼」／「檢視券碼」／「檢視加碼券」**；
    券夾會把它移到最下方的「已使用」區。隨時可以還原。
  - **純本機備忘**：只寫這支手機的 UserDefaults，不送官網、不影響官網的券、不進遙測
    （遙測只送「標記或還原」這個方向，不帶期別 UUID、期數或兌換內容）。
    「立即清除本機資料」與示範模式切換都會清掉。
- **顯示「兌換內容」**：已兌換的期別會顯示官網卡片上那一行「通路／品項」
  （例如「萊爾富／指定雞胸果昔兌換券」），首頁、任務頁與券夾都看得到，
  不必再點進券碼頁才知道當初換了什麼。
- **兌換頁每一列新增「兌換品項」**：可在真的送出兌換之前，先看該通路的加碼券能換哪些商品。
  資料來源是官網兌換頁同一列本來就有的連結（`/registrant/intro/vendor-{id}.html`），
  在 App 內以原生畫面呈現分類、品項與搜尋，不會把使用者帶離兌換流程。
  - 官網那幾頁有**兩種版型**，都支援：逐項列出（全家／7-11／萊爾富，`<details data-category>` ＋ `<li data-name>`）
    與只給類別和舉例（全聯／萬家福・樂家康，分類表格）。舉例版會明確標示「以上為舉例」，不會假裝那是完整清單。
  - **連結存在與否就是唯一的開關**：官網的規則是「靜態頁存在才長出連結」，因此 App 不自己用 `vendorId` 拼網址；
    沒有介紹頁的商家就不顯示這顆按鈕。
  - 連結的 `href` 屬不受信任輸入，解析時採白名單（必須完全符合 `/intro/<檔名>.html`），
    服務層再驗一次；站外網址、路徑穿越、帶 query 一律不採用。

### Fixed

- **兌換頁的切列邊界不再把官網的 class 寫法當成契約**。原本比對完整字串
  `<li class="item-row"`，官網只要改成 `class="item-row item-row--featured"`、
  調換 class 順序或多加一個屬性，切列就會全部失敗、退回舊的切表單路徑 ——
  **品項照樣顯示、兌換照樣可用，但每一列的「兌換品項」按鈕靜默消失**，且不會丟出任何錯誤。
  改成比對「class 裡有 `item-row` 這個 token」，並補上五種 class 寫法的測試。
- **補上那個靜默退化的警報**：解析成功但一列介紹頁連結都沒有時，
  送一筆 `SiteDrift.redeem_intro_missing` 非致命錯誤（只帶品項數這個整數）。
  這條路徑上原本唯一不會丟錯的失敗，現在看得見了。
- **可兌換商品頁認不出版型時不再只給錯誤畫面**：兩種已知版型都對不上時，
  退到 `<li>`／`<p>` 純文字兜出一個「商品資訊」分類，使用者至少看得到內容；
  同時把 `VendorIntro.layout` 標成 `.unrecognised`，由畫面送
  `SiteDrift.vendor_intro_layout` 通知該更新解析器。
  只有連一段可讀文字都撈不到（根本不是商品頁）才丟 `AppError.parsing`。
- **商家名稱比對收斂成唯一一份**。`RedeemView.VendorLogo` 的品牌色與縮寫改走
  `Vendor(vendorName:)`；先前兩邊各有一份 `contains` 判斷並且已經漂掉 ——
  logo 認得萬家福／樂家康，遙測卻把它們算成 `other`。現在補上該分類，要新增商家只改一處。
- **條碼支援預先加上 Aztec 與 PDF417**。CoreImage 本來就內建這兩顆濾鏡，
  接起來幾乎沒有成本，而它們是台灣零售券碼除了 Code 128／QR 之外最可能出現的兩種 ——
  官網換券種時使用者當下就有條碼可掃，不必等改版送審。
  `BarcodeFormat` 的遙測分類同步跟上，否則 `barcode_render_failed` 會把
  「畫得出來卻失敗」與「根本不支援」混在一起。EAN-13／CODE_39 CoreImage 沒有內建，
  刻意不接，等遙測真的看到 `format=other` 再說。

### Changed

- **首次啟動改成「歡迎 → 免責聲明 → 個資填寫」**。原本第一個畫面就是一整頁免責聲明，
  使用者連「這是什麼 App」都還不知道就得決定同不同意。現在先給一頁簡介
  （**App icon**、`Exercise Rewards` 大標、一句用途說明與非官方聲明），
  按「開始使用」才進聲明頁 —— 同意變成有前提的。
  - 免責聲明仍然是**阻斷式**的，仍然擋在任何資料輸入之前，
    `Telemetry.configure()` 仍然只在按下同意的那一刻執行。
    「同意前 Firebase 一行程式碼都不執行」這句話不但成立，還多涵蓋了歡迎頁。
  - 代價是歡迎頁不能埋遙測（埋了也會被閘門擋掉），
    因此導覽漏斗的第一步 `tutorial_begin` 改在個資表單出現時才送。
  - 歡迎頁的圖示改用 **App icon 本體**，與桌面上那顆一致。
    （asset catalog 的 `.appiconset` 執行期取不到，另放一份 `AppIconMark.imageset`
    供畫面使用；換 icon 時**兩份都要換**。）
  - 「立即清除本機資料」會一併重設歡迎頁旗標，真正回到第一次安裝的狀態。
- **加碼券的「已使用」狀態改為跨分頁即時同步**。原本每個畫面各自快照一份標記，
  於是在券夾標記完切回任務分頁不會更新 —— 連下拉重新整理都沒用，
  因為下拉只重抓官網資料，而「已使用」不在官網資料裡。
  改成共用一份 `VoucherUsageStore`（`@Published`），任一處寫入三個分頁一起重畫。
- **首頁的加碼券排序改為三段**：尚未兌換 → 已兌換未使用 → 已使用，同段內依期別由舊到新。
  首頁只有五列，用過的券若卡在前面會把還沒用的擠出畫面。
  已使用的那幾列**不放任何按鈕**（還原的入口留在券夾與券碼頁）。
- **審核完成後不再顯示上傳倒數**。官網的 `period-remaining` 是**上傳窗**倒數
  （「本期任務可上傳時間 剩 N 小時 N 分」），而且對已走完審核的期別照樣回傳 ——
  實測一張已兌換的券，卡片上仍寫著那句話。可兌換／已兌換一律改顯示狀態徽章。
  規則放在 `TaskState.showsUploadCountdown`（Kit 層，有單元測試）。
  待審核刻意保留：上傳窗還開著時，剩餘時間對「審核沒過還能不能重上傳」仍有用。
- **首頁改為「本週任務 ＋ 加碼券」**。移除今日步數環之後，首頁改成列出手上的加碼券：
  - 收錄可兌換（尚未兌換）與已兌換兩種期別，**尚未兌換的排在前面**，同組內依建立時間由舊到新。
  - **最多顯示五列**，超過時右上角出現「查看全部 N 張 ›」導向券夾。
  - 尚未兌換 → 「去兌換」；已兌換 → 「顯示條碼」（仍然每次都要重走一次簡訊 OTP 才會出示券碼）。
- 分頁從四個減為三個：首頁、任務、券夾。
- 免責聲明、「我的資料」隱私聲明、App Store 描述與關鍵字都拿掉了健康相關敘述——
  App 不再讀健康資料，留著會造成期待落差。

---

## [1.0.0] - 2026-09-05

首次公開發行。iOS 16.0 以上、僅 iPhone、僅直向、介面固定繁體中文（zh-Hant）。
本 App 為非官方個人輔助工具，與運動部及任何政府機關無隸屬、合作或授權關係。

### Added

- **一鍵登入官方「我的任務」**：身分證號、出生日期、手機號碼填一次，之後直接登入 500.gov.tw 的會員區，不用每次重打。
- **首次啟動導覽與登入流程**：歡迎頁 → 三欄位表單 → 送出即驗證。查到「此身分證尚未註冊」時，改為提示並以外部 Safari 開啟官網註冊頁（App 本身不做註冊、不碰身分驗證）。
- **任務儀表板**：一次呈現 14 期任務的狀態（尚未開始／可上傳／待審核／可兌換／已兌換）、開放期間與倒數，本週置頂，可下拉刷新，離線時顯示上次快取。
- **今日健康摘要**：連結 Apple 健康後顯示今日步數、步行與跑步距離、運動時間，並判斷是否達到活動門檻（單日 8,000 步／健走 30 分／跑步 5 公里）。
- **上傳運動紀錄**：從相簿挑選截圖，直接以 multipart 送到當期任務（file 欄位 `screenshot`），每期限一次。
- **兌換加碼券**：選擇合作商家與品項送出兌換，後續以簡訊驗證取得券碼。
- **券夾**：集中檢視已取得的加碼券，可再次出示 QR／一維條碼給店家掃描。
- **「我的資料」頁**：檢視與編輯本機個資、遮罩顯示、頁首三點隱私聲明、「立即清除本機資料」（含二次確認，清除後回到初次設定——連免責聲明的同意紀錄與遙測偏好一起重置，下次啟動會重新看到免責聲明）。
- **出生日期選擇器**：自製「年／月／日」三欄滾輪，可切換民國／西元（預設民國），底部同時顯示雙年份；換月自動夾住不存在的日期。
- **示範模式（Demo Mode）**：在登入表單輸入指定的示範三碼即進入全 mock 環境，不發任何網路請求、不寫 Keychain，畫面常駐「示範模式」橫幅，並可在「我的資料」一鍵離開。此模式提供給 App Store 審查員實測完整流程，示範三碼與 App Store Connect 的示範帳號欄位同步。示範模式下遙測**一個事件都不送**（`Telemetry.gate` 的第一道，也是唯一沒有 bypass 的閘門，SDK 層的收集開關也會一併關掉），即使使用者先前打開過統計開關也一樣。**時序上要講清楚**：免責聲明擋在 Onboarding 之前、示範模式是在 Onboarding 的登入表單才進入的，所以審查員是「先同意（Firebase 於此初始化）→ 才進示範模式」；示範模式擋得住事件，擋不住同意當下那一次 SDK 初始化的連線。
- **首次啟動的免責聲明同意畫面**：擋在 Onboarding 之前，必須主動勾選才能繼續。畫面上明寫這是非官方工具、活動權益以官方公告為準，以及「App 會把匿名的操作紀錄與當機報告送給 Google Firebase」；勾選文字涵蓋「並同意傳送不含個資的匿名使用統計（可隨時關閉）」。按下「同意並開始使用」時才呼叫 `Telemetry.configure()`——**那是整支 App 第一次執行 Firebase 程式碼的時機**。同意紀錄以版本號保存，日後修改聲明可讓既有使用者重新同意。
- **匿名使用統計與當機回報（Firebase Analytics + Crashlytics，同意後預設開啟）**：新增「我的資料 › 安全與隱私 › 傳送匿名使用統計」開關。**在使用者按下免責聲明的同意之前，一個位元組都不會送到 Google**；同意之後這個開關**預設是開的**，隨時可關，關掉即刻停止收集。這不是 opt-in，而是「先告知 → 主動同意 → 預設開啟 → 隨時可關」。`Info.plist` 的 `FIREBASE_ANALYTICS_COLLECTION_ENABLED`、`FirebaseCrashlyticsCollectionEnabled`、`GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`、`GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS` 四個旗標仍全為 `false`——那是**冷啟動的預設值**，由 `applyCollectionFlags` 在初始化後依使用者偏好覆寫，留 `false` 是為了守住「還沒 `configure` 就絕不收集」。送出的是匿名操作事件（哪個畫面、哪一步失敗）與當機報告；**不含身分證號、出生日期、手機號碼，也不含任何 Apple 健康的數值或由步數推導出來的結論**。
- **開源**：全部程式碼以 MIT 授權公開，核心邏輯抽成 `ExerciseRewardsKit` Swift Package，可 headless `swift build` / `swift test`。

### Changed

- **App Store 顯示名定為 `Exercise Rewards`**：活動名「揮汗有禮」不作為 App 名稱，避免被誤認為官方 App。
- **個資最小化為三個欄位**：只收登入必要的身分證號、出生日期、手機號碼；姓名、Email、健保卡卡號一律不再收集（資料模型欄位保留但永遠為空）。
- **安全與隱私設定併入「我的資料」頁**：移除獨立的「資安中心」子頁，本機資料說明與清除功能少一層導覽即可操作。
- **首頁步數環改為三態**（確認中／已連結／未連結）：未連結時顯示淺灰虛線占位環與「尚未連結 Apple 健康」，不再出現任何示意用的假步數，冷啟動也不會閃現「未連結」結論。
- **介面語言固定繁體中文**：開發語言鎖 `zh-Hant`，並注入 `Locale(zh_Hant_TW)`，系統元件（滾輪、警示按鈕）不會退回英文；配色鎖淺色主題。
- **註冊改為導向官方網站**：App 內不做註冊表單、不注入任何腳本到政府身分驗證頁面。

### Removed

- **Face ID／Touch ID 開啟鎖與敏感動作再驗證**：移除 `BiometricGate` 與 `SensitiveAuthCoordinator`，同時移除 `NSFaceIDUsageDescription`。本版不再要求生物辨識權限；個資的保護改為單純依靠 iOS Keychain（`WhenUnlockedThisDeviceOnly`，裝置解鎖時才可讀）與「立即清除本機資料」。
- **以 HealthKit 數據產生上傳圖卡的功能**：不再由 App 合成任何要上傳的圖片。上傳一律由使用者自己從相簿挑選截圖，健康數據因此完全不離開裝置。
- **獨立的「設定」頁與「資安中心」子頁**：內容併入「我的資料」。

### Security

- **無自建後端**：本 App 沒有任何自建伺服器，開發者不接收、不儲存個資，也看不到任何身分或健康資料。唯一例外是使用者同意免責聲明、且「傳送匿名使用統計」開著的時候，開發者可在 Firebase 主控台看到匿名的操作事件與當機報告（見下一條）。
- **唯一的第三方相依：firebase-ios-sdk 12.18.0**（Analytics + Crashlytics）。SPM 會解析 **13 個套件**，但**實際連進 App 二進位的只有 6 個**：`firebase-ios-sdk`、`GoogleAppMeasurement`、`GoogleDataTransport`、`GoogleUtilities`、`nanopb`、`promises`。其餘仍只用 Foundation / SwiftUI / HealthKit。
- **選 `FirebaseAnalyticsCore` 而非 `FirebaseAnalytics`**：底層為 `GoogleAppMeasurementCore`，**結構上不含 IDFA 收集能力**。Release 二進位已驗證未連結 `AdSupport`、`AppTrackingTransparency`、`AdServices`，因此不會出現 ATT 追蹤提示，`PrivacyInfo.xcprivacy` 的 `NSPrivacyTracking` 為 `false`、追蹤網域清單為空。
- **遙測的初始化綁在免責聲明同意之後**：`Telemetry.defaultEnabled` 是 `true`，但 `configure()` 有三道前置條件，缺一不初始化——尚未同意免責聲明、使用者關掉開關、示範模式。理由是 `FirebaseApp.configure()` 一執行就會產生 app instance ID 並送出 `first_open`，而且即使兩個收集旗標都是 `false`，Firebase Installations 仍會連 `firebaseinstallations.googleapis.com` 要一組安裝編號。所以界線放在「執行與否」而不是旗標開關：**在使用者讀到免責聲明並按下同意之前，Firebase 一行程式碼都不會跑**。代價是同意那一刻起就開始收集（`first_open` 與 Installations 連線確實發生），以及同意之前的當機永遠看不到。
- **遙測只有一個出口 `Telemetry.swift`**：其他檔案禁止 `import FirebaseAnalytics` / `FirebaseCrashlytics`。事件名與參數值全來自封閉列舉：`AnalyticsValue` 的底層儲存是 `private`，唯一能產生字串參數的建構子只收封閉列舉的 rawValue，自由字串**值**在編譯期就構造不出來（參數的**鍵**與 Crashlytics breadcrumb 仍是字串，由送出前的樣式掃描把關），**完全不設任何使用者屬性**。送出前再過六道閘門——示範模式、截圖模式、使用者未同意、Firebase 未初始化、參數命中 `Redact` 敏感樣式、整數值域檢查（最後兩道在 DEBUG build 直接 `assertionFailure`）。非致命錯誤**不接受 `Error` 物件**，只收已經分類完成的 `TelemetryIssue` 列舉與狀態碼，所以伺服器原文與 `userInfo` 結構上就送不出去。
- **個資與健康資料一律不進遙測**：身分證號、出生日期、手機號碼的任何形式（原文、雜湊、截斷、拼接）都不送；HealthKit 衍生值也全部不送，**連「今日是否達標」這種由步數推導的布林值都不送**（Apple 禁止把健康資料分享給第三方）。唯一沾到健康的是 `health_link_tap`——只記錄「使用者按了前往連結的按鈕」這個 UI 動作，連授權結果都不送。
- **新增 `PrivacyInfo.xcprivacy`**：宣告 `NSPrivacyTracking = false`、無追蹤網域、UserDefaults 使用理由 `CA92.1`，以及 CrashData／OtherDiagnosticData／ProductInteraction 三類資料（皆 not linked、not tracking）。
- **`GoogleService-Info.plist` 不進版控**：本 repo 公開，真檔一律排除，只附 `.template`。真檔不存在時 `Telemetry.configure()` 直接跳過初始化，遙測全程 no-op 且不 crash，clone 下來就能 build。
- **網域白名單**：`URLSessionHTTPClient` 只允許連線 `500.gov.tw`（含子網域，並擋 suffix 偽冒），其餘一律拋出 `blockedEgress`。**界線**：這個白名單管的是 App 自己發出的 HTTP 請求；Firebase SDK 走它自己的 `URLSession`，不受白名單管轄——遙測運作時，SDK 會另外連往 `app-analytics-services.com`、`firebaseinstallations.googleapis.com`、`firebase-settings.crashlytics.com`、`crashlyticsreports-pa.googleapis.com`、`firebaselogging.googleapis.com`。
- **ATS 強制 HTTPS**：`NSAllowsArbitraryLoads=false`，`500.gov.tw` 要求 TLS 1.2 以上與 forward secrecy，不開放任何明文例外。
- **修正官網 http 降級 redirect**：官網 302 的 `Location` 為 `http://`，client 一律正規化回 `https://` 再送，避免 Secure cookie 遺失與明文傳輸。
- **個資只存 iOS Keychain**：`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`，不同步 iCloud、不隨備份轉移；絕不寫入 `UserDefaults`、plist 或明文檔案。
- **Cookie 存在 App 沙盒容器、不外流**：`LBSCookie` / `JSESSIONID` 由 `URLSessionHTTPClient`（`persistCookies: true`）保存以維持登入狀態，僅限本 App 容器可讀；**重新登入前**（`AuthService` 登入流程開頭）與「立即清除本機資料」時都會呼叫 `resetSession()` 清空。cookie 的 domain scope 為 `500.gov.tw`，不會被送往其他網域。
- **統一日誌出口 `SecureLog` + `Redact`**：身分證、生日、手機、Email、健保卡號、cookie、`_csrf`、OTP、presigned URL 一律遮罩；debug 層級只在 DEBUG build 輸出。
- **HealthKit 唯讀**：只要求 `stepCount`、`distanceWalkingRunning`、`appleExerciseTime` 的讀取權限，從不寫入，資料也不離開裝置——**包含不進遙測**，即使使用者開啟了匿名統計也一樣。
- **不繞過任何身分驗證**：戶役政、健保卡、簡訊 OTP 皆為真實驗證，App 設計上不提供繞過路徑，也不提供任何可竄改運動數據的入口。
- **`ITSAppUsesNonExemptEncryption=false`**：只使用系統 TLS，屬出口管制豁免。

[1.1.0]: https://github.com/megshao/exercise_rewards_ios/releases/tag/v1.1.0
[1.0.0]: https://github.com/megshao/exercise_rewards_ios/releases/tag/v1.0.0
