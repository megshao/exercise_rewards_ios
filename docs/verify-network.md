# 自己驗證 App 的網路行為

這份文件給想親眼確認「這支 App 到底連了哪裡、送了什麼」的人。
不需要會寫程式，但需要一台 Mac 或 PC、一支 iPhone、同一個 Wi-Fi，以及大約 15 分鐘。

隱私權政策第 8 節把「你能驗證到什麼程度」分成四層；這份文件是第 1 層（App 隱私權報告）與第 2 層（看請求內容）的操作說明。

## 先講清楚：這個方法能驗到什麼、驗不到什麼

能驗到：

- App 連了哪些網域、每一筆請求的完整內容（網址、標頭、表單欄位、上傳的檔案）。
- 開關關著時，有沒有任何東西送到 Google。

> **驗證前必讀**：「傳送匿名使用統計」在你同意首次啟動的免責聲明之後**預設是開的**。
> 所以剛裝好正常使用時，看到 Google 網域是**預期中的**，不是異常。
> 要驗「零連線」請先到「我的資料 › 安全與隱私」把開關關掉，**再把 App 完全關閉重開**
> （Firebase 沒有反初始化，同一次執行期間 SDK 仍在記憶體裡）。
> 另一個零連線的時機是「還沒按下免責聲明的同意」——那時 Firebase 一行都還沒執行。
- 送到 `500.gov.tw` 的欄位是不是只有登入必需的那三個。

驗不到：

- 「所有情況下」的行為。你看到的是這一次操作的行為；程式理論上可以只在特定條件下才送東西。要補這塊，得讀原始碼（第 3 層），而讀原始碼又得信任商店版就是那份原始碼（第 4 層）。黑箱測試的天限就在這裡，我們不假裝它沒有。
- 遙測開著時，Google Analytics 的事件內容不容易讀（它是二進位 protobuf 格式）。你看得到網域、頻率、大小，字串欄位也會以明文出現在封包裡（所以搜得到有沒有身分證號），但沒辦法像讀 JSON 那樣一眼看懂每個欄位。

門檻與代價：

- 要在手機上安裝並信任一張你自己產生的憑證。驗完請移除（步驟在最後）。
- 你自己的身分證號、生日、手機號碼會出現在 mitmproxy 的畫面與存檔裡。**不要把 flow 存檔直接貼到公開的 issue。**

## 0. 最簡單的版本：App 隱私權報告（不用電腦）

1. 設定 › 隱私權與安全性 › App 隱私權報告 › 開啟。
2. 正常使用 App 幾天。
3. 回到同一頁，找到 Sports Rewards，看「網路活動」底下列了哪些網域。

在**尚未同意免責聲明**、或關掉「傳送匿名使用統計」並完全重開之後，只應該看到：

| 網域 | 什麼時候出現 |
|---|---|
| `500.gov.tw` | 登入、抓任務、上傳、兌換、券碼 |
| 官方網站存放截圖的圖片網域（實測為 `*.amazonaws.com`） | 只在你點開「查看已上傳的截圖」時 |

看到任何 Google 網域（`googleapis.com`、`crashlytics.com`、`app-analytics-services.com`、`google-analytics.com`……）就是我們違反承諾，請截圖回報。

限制：只看得到「連去哪」、看不到「送了什麼」；只保留 7 天。（v1.1 起 App 不再讀取 Apple 健康，因此也不需要去「健康 › 分享 › App 與服務」對照。）另外，剛關掉統計開關的那一次執行 Firebase 還在記憶體裡，驗「關著時零連線」前請先把 App 完全關閉再重開。

## 1. 準備 mitmproxy

### 1.1 電腦端

```sh
brew install mitmproxy        # macOS；其他平台見 mitmproxy.org
mitmweb                       # 啟動，預設監聽 8080，瀏覽器介面在 http://127.0.0.1:8081
```

查自己電腦在 Wi-Fi 上的 IP（macOS：系統設定 › Wi-Fi › 詳細資訊；或 `ipconfig getifaddr en0`）。

### 1.2 iPhone 端

1. 設定 › Wi-Fi › 目前網路右邊的 (i) › 設定代理伺服器 › 手動：伺服器填電腦 IP，連接埠 8080。
2. 用 Safari 開 `http://mitm.it`，點 iOS 那一格下載描述檔。
3. 設定 › 一般 › VPN 與裝置管理 › 安裝剛下載的描述檔。
4. 設定 › 一般 › 關於本機 › 憑證信任設定 › 把 mitmproxy 打開為完全信任。

沒做第 4 步的話，HTTPS 連線會全部失敗，你會看到 App 顯示網路錯誤——那是你的設定沒完成，不是 App 在阻擋。

### 1.3 確認能看到流量

在 iPhone 用 Safari 隨便開一個網站，mitmweb 的清單裡應該出現那筆請求。可以了就把 Safari 收掉，接下來只操作 Sports Rewards。

建議在 mitmweb 的過濾框輸入：

```
~d 500.gov.tw | ~d amazonaws.com | ~d google | ~d crashlytics | ~d firebase
```

先只看這些（`amazonaws.com` 那一條是依目前實測的截圖圖片網域寫的；若官方網站換了儲存供應商，改成你在 302 `Location` 看到的網域）。iPhone 上其他 App 與系統服務的流量也會經過 proxy（其中不少 Apple 服務有做 pinning，會顯示成握手失敗，那是正常噪音，跟本 App 無關）。

## 2. 預期會看到的網域

| 網域 | 誰發的 | 什麼時候 | 開關關著時會出現嗎 |
|---|---|---|---|
| `500.gov.tw` | App 自己的網路程式碼 | 登入、抓任務、上傳、兌換、券碼 | 會 |
| 官方網站存放截圖的圖片網域（實測為 `*.amazonaws.com`） | `ScreenshotView` 的專用 `URLSession`（ephemeral、無 cookie 罐、不進 URL cache） | 只在點開「查看已上傳的截圖」時 | 會（只在那一刻） |
| `firebaseinstallations.googleapis.com` | Firebase SDK | 打開統計開關那一刻（要一組安裝編號） | **不會** |
| `app-analytics-services.com` | Firebase SDK | 開關開著時，事件批次上傳 | **不會** |
| `firebase-settings.crashlytics.com` | Firebase SDK | 開關開著時，啟動後抓設定 | **不會** |
| `crashlyticsreports-pa.googleapis.com` | Firebase SDK | 開關開著、且上一次有當機或非致命錯誤要回報時 | **不會** |
| `firebaselogging.googleapis.com` | Firebase SDK | 開關開著時，SDK 自己的傳輸日誌 | **不會** |

以上五個 Google 網域是從送審版本的二進位裡直接撈出來的字串。Google 可能改網域，所以判準不是「只有這五個」，而是**在還沒同意免責聲明之前、或關掉開關並完全重開之後，任何 Google 網域都不該出現**。同意後且開關開著時它們出現是正常的。

圖片網域是**官方網站**決定的，不是本 App 決定的：截圖網址由官網以 302 回傳。但 App 不是照單全收——`TasksService.screenshotImageURL` 會先檢查那個 `Location`：**scheme 必須是 `https`，host 必須是 `500.gov.tw`（含子網域）或 `*.amazonaws.com`**，否則丟 `blockedEgress` 並顯示載入失敗。官方站若換掉儲存供應商、換到白名單外的網域，你會看到「無法載入截圖」而不是一個往陌生網域的請求（那時請開 issue，我們會補上新網域）。判準是「不帶 cookie、只在點開截圖時出現、而且網域在上面那兩類之內」。

除了這張表上的東西，本 App 不該連任何地方。

## 3. 每個操作預期的請求

所有 `500.gov.tw` 的請求都在 `https://500.gov.tw/registrant/...` 底下。官方網站沒有 API，全部是一般的網頁表單；App 以一般瀏覽器的身分提交同一份表單，因此 `User-Agent` 是 iPhone Safari 的字串。

### 登入（首次設定、「重新登入」、冷啟動自動登入）

```
GET  /registrant/access                         ← 可能先被 302 到 ?_cookie_check=1 再回來，這是官網 CDN 的 cookie 握手，正常
POST /registrant/access
     _csrf=<官網給的一次性 token>&idNo=<你的身分證號>
     → 302 /registrant/login（已註冊）或 /registrant/register（未註冊，App 會停在這裡並導你去 Safari）

GET  /registrant/login
POST /registrant/login
     _csrf=<token>&idNo=<身分證號>&birthDate=<yyyy-MM-dd>&phone=<09xxxxxxxx>
     → 302 /registrant/member/tasks（成功）；回到 /login 或停在 200 就是三碼不符

GET  /registrant/member/tasks                   ← 登入成功後立刻抓一次任務
```

**要看的重點**：兩個 POST 的表單欄位就是上面那些。`_csrf` 是官網每頁給的一次性 token，不是 App 產生的識別碼。沒有裝置 ID、沒有步數、沒有任何其他欄位。

### 抓任務（首頁刷新、任務分頁、券夾）

```
GET  /registrant/member/tasks                   → 200 HTML
```

沒登入或 session 過期時會 302 到 `/registrant/login`，App 會自動重新登入（於是你會再看到一組上面的登入序列）。

### 上傳截圖

```
GET  /registrant/member/upload                  ← 抓 _csrf、確認本期還能上傳
POST /registrant/member/upload                  multipart/form-data
     _csrf=<token>
     screenshot=<你選的那張圖，檔名與 image/jpeg 或 image/png>
     → 302 /registrant/member/tasks（成功）；停在 200 是官網退件
```

**要看的重點**：multipart 裡只有 `_csrf` 與 `screenshot` 兩個部分。圖片內容就是你從相簿選的那張（App 不合成、不改圖、不加水印）。

### 查看已上傳的截圖

```
GET  /registrant/member/screenshot/<期別 UUID>
     → 302 Location: https://<官方網站的圖片儲存網域>/...?...簽章...（實測是 AWS S3 的 presigned URL）

GET  https://<同上>                              ← 這一筆是 ScreenshotView 的專用 URLSession 發的
```

**要看的重點**：往那個圖片網域的請求**不該帶 `Cookie` 標頭**，也不該帶 `Authorization`。它能讀是因為網址裡自帶簽章，而那個網址是官網給的。

這件事有兩層保證，講清楚哪一層在做事：
- **第一層是 cookie 自己的網域範圍**：登入 cookie 的 domain 是 `500.gov.tw`，瀏覽器／`URLSession` 本來就不會把它送去別的網域。
- **第二層是這條路徑用的連線**：`ScreenshotView` 用的是自己開的 `URLSession`（`ephemeral`、`httpCookieStorage = nil`、`urlCache = nil`），**完全沒有 cookie 罐**。這一層才擋得住「`Location` 指回 `500.gov.tw` 自己」的情況——那是同源，只靠第一層是擋不住的。
  （之前這裡用的是 `AsyncImage`。`AsyncImage` 走 `URLSession.shared`，而它的 cookie 罐就是 `HTTPCookieStorage.shared`，跟 App 自己那個 session 是同一個；而且 `URLSession.shared` 會把圖片以網址為 key 寫進 `Library/Caches`。兩件事都已經改掉。）

### 兌換

```
GET  /registrant/member/redeem/<期別 UUID>       ← 商家清單 + _csrf
POST /registrant/member/redeem/<期別 UUID>
     _csrf=<token>&vendorId=<商家代碼>&item=<品項代碼>
     → 302（送出成功）；停在 200 是官網拒絕
```

### 券碼（簡訊驗證）

```
GET  /registrant/member/voucher/<期別 UUID>              ← 簡訊驗證頁 + _csrf
POST /registrant/member/voucher/<期別 UUID>/resend       _csrf=<token>          ← 重新發送簡訊
POST /registrant/member/voucher/<期別 UUID>              _csrf=<token>&otp=<你輸入的 6 碼>
     → 302 .../view（驗證成功）；停在 200 是輸錯
GET  /registrant/member/voucher/<期別 UUID>/view         → 200 HTML，內含券碼與條碼
```

**要看的重點**：簡訊驗證碼只出現在往 `500.gov.tw` 的那一筆 POST。券碼只出現在 `/view` 的回應裡，之後不會再被送到任何地方。

### 「立即清除本機資料」

App 目前**沒有登出按鈕**，所以你不會看到 `POST /registrant/logout`。cookie 會在兩個時機被清掉，兩者都不發任何額外請求：

- **重新登入時**：登入流程一開始就先清空舊 cookie，再走 `access` → `login` 握手。
- **「立即清除本機資料」時**：直接清空本機 cookie 與 Keychain 欄位。

清除本機資料時，如果統計開關本來是開的，**會先送出最後一筆 `local_data_clear` 事件**，
然後才重置偏好與同意紀錄——順序是刻意的，因為偏好一旦重置那筆事件就送不出去了。
所以你會在 mitmproxy 上看到一筆往 Google 的請求，**那是正常的**。之後就不會再有了：
同意紀錄也被清掉，下次啟動會重新看到免責聲明。

## 4. 遙測打開後會多出什麼

在「我的資料 › 安全與隱私 › 傳送匿名使用統計」打開開關之後，第一次會看到：

1. `firebaseinstallations.googleapis.com`——要一組隨機安裝編號。這是整支 App 第一次接觸 Google。
2. `firebase-settings.crashlytics.com`——抓 Crashlytics 設定。
3. 之後陸續出現 `app-analytics-services.com`（事件批次上傳，通常間隔幾十秒到幾分鐘）與 `firebaselogging.googleapis.com`。
4. `crashlyticsreports-pa.googleapis.com` 只在有當機或非致命錯誤要回報時出現。

事件內容是 protobuf，mitmweb 會顯示成一堆不可讀的位元組，中間夾著可讀的字串。你能做的檢查是：

- 在 mitmweb 用搜尋（`~b <你的身分證號>`、`~b <你的手機號碼>`、`~b <你的生日>`）掃所有往 Google 的請求。**應該一筆都搜不到。** protobuf 裡的字串是明文 UTF-8，真的有送就會被搜到。
- 看每一筆的大小。事件名與參數值都是固定清單裡的短字串（`home`、`tasks`、`login_failed`、`site_error`……），單筆請求通常只有幾 KB。

關掉開關後：這一次執行期間 SDK 還在記憶體裡（Firebase 沒有反初始化），但收集旗標已關、安裝編號已重置。要驗「關著時零連線」，請先完全關閉 App 再重開。

## 5. 怎麼判斷「有沒有異常」

五條判準，任何一條不成立都請回報：

1. **開關關著、且 App 已完全關閉重開之後**：除了 `500.gov.tw` 與官方網站回傳的圖片儲存網域，本 App 不該連任何地方。
2. **往 `500.gov.tw` 的表單欄位只有這幾個**：`_csrf`、`idNo`、`birthDate`、`phone`、`screenshot`（檔案）、`vendorId`、`item`、`otp`。多出任何欄位——尤其像步數、距離、裝置識別碼——就是異常。
3. **往圖片儲存網域的請求**：不帶 `Cookie`、不帶 `Authorization`，只在你點開截圖時發生，而且網域只會是 `500.gov.tw`（含子網域）或 `*.amazonaws.com`——其他網域會被 App 主動擋掉並顯示載入失敗。
4. **遙測開著時，往 Google 的請求裡搜不到**你的身分證號、生日、手機號碼、步數，也搜不到任務的 UUID 與券碼。
5. **每一筆都是 `https://`**。官方站 302 的 `Location` 是 `http://`，client 一律正規化回 https 再送，所以你看到的實際請求全部應該是 https。看到任何一筆 `http://` 就是異常。

## 6. 驗完之後

1. 設定 › Wi-Fi › (i) › 設定代理伺服器 › 關閉。
2. 設定 › 一般 › VPN 與裝置管理 › 刪除 mitmproxy 描述檔（憑證信任會一起消失）。
3. 如果你有存 flow 檔（`mitmweb` 的 File › Save），記得它裡面有你的個資，不要外傳。

## 7. 發現異常怎麼回報

- 信箱：megshao0918@gmail.com
- GitHub issue：<https://github.com/megshao/sports_rewards_ios/issues>

請附：App 版本（「我的資料」頁最底下）、iOS 版本、你看到的網域或欄位名、當時在做什麼操作。**請把身分證號、生日、手機、cookie、`_csrf`、驗證碼、券碼先塗掉**——我們不需要那些就能查。

## 8. 這份文件跟原始碼的對應

想對照原始碼確認上面寫的東西：

- 網域白名單、https 強制、不跟隨 redirect：`Sources/SportsRewardsKit/Networking/URLSessionHTTPClient.swift`
- 登入序列與欄位：`Sources/SportsRewardsKit/Services/AuthService.swift`
- 上傳欄位：`App/Sources/App/UploadService.swift`
- 兌換與券碼：`Sources/SportsRewardsKit/Services/RedeemService.swift`、`VoucherService.swift`
- 截圖 302 → S3：`Sources/SportsRewardsKit/Services/TasksService.swift`、`App/Sources/Views/ScreenshotView.swift`
- Firebase 什麼時候才初始化、送出去的事件清單：`App/Sources/App/Telemetry.swift`
- ATS（強制 TLS 1.2+、forward secrecy）與 Firebase 四個收集旗標：`App/project.yml`

沒有任何一個檔案做 certificate pinning。這是刻意的：pinning 會讓你上面做的每一步都失敗。
