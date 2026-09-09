# 註冊流程 API 實測記錄（R-register）— 一次性

本人同意之測試對象。只記錄 API 形狀（端點/欄位名/回應結構/導向），**不寫入任何真實個資明碼**。

## 預期流程（依先前端點探測）
1. GET /registrant/register → 取 _csrf（表單欄位：name, idNo, birthDate, phone, email, agree）
2. POST /registrant/register (body: _csrf,name,idNo,birthDate,phone,email,agree=true) → 預期 302 /register/nhi-verify
3. GET /registrant/register/nhi-verify → 取健保卡欄位名/_csrf（戶役政生日+健保卡號驗證）
4. POST /registrant/register/nhi-verify (body: ?) → 預期 → /register/otp
5. GET /registrant/register/otp → 取 OTP 發送/驗證欄位
6. POST 發送 OTP → SMS；POST 驗證 OTP → 完成註冊
（以下逐步實測填入）

## 實測 步驟3-4（已完成，形狀）
- POST /registrant/register (body _csrf,name,idNo,birthDate,phone,email,agree=true) → **302 /register/moi-verify**
- 步驟2/4 內政部身分驗證 = **全自動非同步**，非表單：
  - 前端輪詢 GET /registrant/register/moi-verify/status（Accept: application/json）
  - 回 JSON {state: WAITING|PASSED|FAILED|EXPIRED, next, message}；PASSED→導向 next（下一步）；期間勿關頁
  - FAILED 範例：{"state":"FAILED","message":"身分驗證未通過：姓名、身分證號或出生日期與內政部資料不符，請確認後重新登記。"}
  - App 對接：POST /register 後進入輪詢畫面，輪詢 status 到非 WAITING；FAILED 顯示 message、回 /register 重填。
- ⚠️ 本次測試資料未通過戶役政比對，nhi-verify(健保卡) 與 otp 兩步尚未實測，待正確資料後續抓。
## 實測 步驟5（健保卡驗證 = 外部政府入口）
- GET /register/nhi-verify：非表單，只有「前往健保卡驗證」鈕（POST 只帶 _csrf）。
- POST /register/nhi-verify → 302 到 **https://www.cp.gov.tw/portal/PIIMVerify.aspx**
  ?checkFields=8&successUrl=https://500.gov.tw/registrant/register/nhi-verify/result&toVerify=<加密token>
  = 內政部「多因子身分核實及認證機制」，ASP.NET WebForms。
  - 欄位：ctl00$ContentPlaceHolder1$txt_NhiID（健保卡號12碼）、btnOK、__VIEWSTATE/__VIEWSTATEGENERATOR/__EVENTVALIDATION 等。
  - 成功→導回 successUrl（/register/nhi-verify/result）繼續後續（預期→ OTP）。
- **App 對接**：此步以 WKWebView/SFSafariViewController 開啟 PIIMVerify URL，讓使用者在官方頁輸入健保卡號完成，偵測導回 /nhi-verify/result 再繼續。錯誤訊息由官方頁自行顯示（App 不需解析）。
- ⚠️ 外部政府 MFA 入口可能有自己的錯誤/鎖定限制，勿隨意用腳本測錯誤卡號。
## 實測 步驟5結果 + 步驟6（OTP）
- PIIMVerify 送正確健保卡號(12碼) → 302 /register/nhi-verify/result?result=<JWT，iss=www.gsp.gov.tw, result:success, ckFields:[CheckNhiSerial]> → 302 /register/otp → 200 簡訊驗證頁。
- **到達 /register/otp 會自動發送 OTP** 到登記手機（每日簡訊最多 20 次）。
- OTP 頁：form action /registrant/register/otp，欄位 _csrf, otp(6碼, maxlength6)。
- 驗證：POST /registrant/register/otp (body _csrf, otp)
- 重新發送：POST /registrant/register/otp/resend（data-resend-after=59）
- 待：正確 OTP → 完成註冊（導向待補）。App 對接同 voucher OTP 模式。
- 錯誤 OTP：POST /register/otp (otp錯) → HTTP 200，停頁，含「驗證碼錯誤，還可以再試 N 次。」（共3次，用罄需重發；每日簡訊上限20）。與 voucher OTP 同格式，App 可共用解析。
- 正確 OTP：POST /register/otp → HTTP 200，回「登記完成」頁（✓ 登記完成，OTP驗證已通過）。註冊結束，之後走登入。

## R-register 完整流程（App 對接總結）
1. POST /access(idNo) → 302 /register（未註冊）
2. POST /register(_csrf,name,idNo,birthDate=ISO,phone,email,agree=true) → 302 /register/moi-verify
3. 輪詢 GET /register/moi-verify/status(JSON {state,next,message}) → PASSED → next=/register/nhi-verify（FAILED 顯示 message 回重填）
4. GET /register/nhi-verify（僅按鈕）→ POST /register/nhi-verify(_csrf) → 302 外部 cp.gov.tw PIIMVerify（健保卡MFA）→ 成功 302 /register/nhi-verify/result?result=<JWT> → 302 /register/otp（自動發OTP）
   → App：用 WKWebView 開 PIIMVerify URL，偵測導回 /nhi-verify/result 續行
5. POST /register/otp(_csrf,otp)；錯誤 200「還可以再試N次」(3次)；正確 200「登記完成」
6. 完成後導首頁，改走一鍵登入。

## App 實作：RegisterWebView（UI 行為與送審備註）
- 整段註冊在單一 WKWebView（持久 cookie store）內完成；App 注入 JS 自動填已知欄位並自動前進。
- **UI 覆蓋層策略**：access/register/moi-verify/nhi-verify 這些自動步驟一律以覆蓋層藏住（使用者看不到官方頁閃過）；**只露出兩頁需使用者操作**：健保卡 MFA（cp.gov.tw PIIMVerify，預填卡號但由使用者按確認）、簡訊 OTP（使用者輸入）。
- moi-verify 失敗監看：比對失敗/逾時會收掉覆蓋層，露出官方錯誤讓使用者看到並可取消。
- 完成偵測：頁面文字含「登記完成」或導回 /registrant/。
- 資料最小化：姓名＋健保卡僅在註冊分支暫存於 @State、注入 JS 後即棄，不寫入 Keychain；只存 idNo/birthDate/phone/email。

### ⚠️ 送審（App Review）需特別備註（App Review Notes 要寫）
- 本 App 為**非官方**工具，於 App Review Notes 明確聲明，並在 App 內顯示「非官方工具」。
- 註冊流程使用 WKWebView 載入官方 500.gov.tw 與內政部 cp.gov.tw（健保卡 MFA）頁面，並以注入 JS 自動填「使用者本人輸入的資料」以節省重複輸入；健保卡與 OTP 保留由使用者親自操作。
- 需附測試帳號或說明審查員如何驗證；說明個資只存本機、不上雲、開源。
- 詳見 fable agent 的 App Review 風險評估報告（另行產出）。
