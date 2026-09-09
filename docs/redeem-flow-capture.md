# 兌換流程 API 實測記錄（R2）— 一次性

帳號：本人授權測試。目標：萊爾富・超值商品券。逐步錄下端點/欄位/回應。
（不記錄個資明碼；只記 API 形狀。）


## 步驟 5 結果（實測）
- POST /registrant/member/redeem/{uuid} (body _csrf,vendorId=3,item=tmp-20260822-item-hilife)
  → **302 Location /member/tasks**（兌換即完成指派，不直接進 OTP）
- 之後該期 state 由 REDEEMABLE → 見下方 tasks 重抓

## 步驟 6 兌換後 → 檢視加碼券（R2，實測完成）
兌換後該期 state = REDEEMED，任務卡出現連結 `/member/voucher/{uuid}`。
檢視券碼需每次 OTP 驗證（券碼不在頁面上，OTP 通過才產生）：

- **檢視頁**：GET `/registrant/member/voucher/{uuid}` → 兩個 form：
  - 發送：`voucher-otp-resend-form`
  - 驗證：`voucher-otp-verify-form`
- **發送 OTP**：POST `/registrant/member/voucher/{uuid}/resend`  body: `_csrf`
  - 驗證碼發送至登記手機（091****225）；有 `data-resend-after` 秒數倒數；同門號每日次數上限。
- **驗證 OTP / 出示券碼**：POST `/registrant/member/voucher/{uuid}`  body: `_csrf`, `otp`(6碼)
  - 通過後回傳含券碼（QR/一維碼）的頁面。→ 待驗證後補記券碼 DOM 結構。

### App 對接建議
- RedeemService.redeem() 後導向 VoucherView(uuid)
- VoucherView：按鈕→POST /voucher/{uuid}/resend 發 OTP；輸入6碼→POST /voucher/{uuid}(otp) →解析券碼/QR
- 每次檢視都要重新 OTP（券碼不快取）

## 步驟 7 OTP 驗證回應（實測）
- **錯誤 OTP**：POST /member/voucher/{uuid} (otp=錯) → **HTTP 200**，回同一檢視頁，
  含 `<p class="notice notice--error">驗證碼錯誤，還可以再試 N 次。</p>`
  → 有嘗試上限（共 3 次），每錯一次 N 遞減；用罄後應需重新發送 OTP。
- 正確 OTP → 200，頁面出現券碼區塊（QR/一維碼）。→ 待正確碼補 DOM。
- App 處理：解析 `.notice--error` 顯示錯誤與剩餘次數；成功則解析券碼區塊。

## 步驟 8 正確 OTP → 券碼頁（實測完成，R2 收尾）
- 正確 OTP：POST /member/voucher/{uuid} (otp=正確6碼) → **302 Location /member/voucher/{uuid}/view**
- 券碼頁：GET `/registrant/member/voucher/{uuid}/view`（title「我的加碼券」）
- 結構：
  - `.voucher-banner` / `.voucher-meta`：通路、品項、兌換期限（如 115/12/31）
  - 一或多個 `<section class="voucher-figure">`，每個含
    `<... class="voucher-figure__code" data-voucher-code data-format="CODE_128" data-value="<號碼>">`
    ＋ `.voucher-figure__caption`（如「① 商品條碼」「② 券號條碼」）＋ `.voucher-figure__fallback`（條碼無法顯示時提示手動輸入號碼）
  - `.voucher-notices`：使用注意事項
- **萊爾富 超值商品券為兩段式**：兩個 CODE_128 條碼（①商品條碼 ②券號條碼），店員須各掃一次，缺一不可。
- 條碼由前端 JsBarcode(3.12.3) 依 data-value 即時生成；另載 node-qrcode（別家品項可能用 QR，故 App 要讀 data-format 分流：CODE_128→Code128、QR_CODE→QR）。
- 合規：官網明訂須以「本人帳號即時畫面」抵用，不得截圖/列印/翻拍 → App 的 VoucherView 必須每次即時 OTP 取得、不得快取券碼畫面。
- （實測真實券碼值已驗證可取得，基於隱私未寫入本檔。）

## App 對接總結（R2 完成，可實作 VoucherView）
1. RedeemService.redeem() 成功後 → VoucherView(uuid)
2. sendOtp: POST /member/voucher/{uuid}/resend (body _csrf)  ← 有 data-resend-after 倒數、每日上限
3. verifyOtp: POST /member/voucher/{uuid} (body _csrf, otp) →
   - 錯誤：200 + `.notice--error`「驗證碼錯誤，還可以再試 N 次」（共3次，用罄需重發）
   - 正確：302 → /member/voucher/{uuid}/view
4. GET /member/voucher/{uuid}/view → 解析 voucher-figure[] {format, value, caption} + banner/meta/notices
5. App 用 CoreImage 依 format 生條碼(CODE128)/QR；不快取，離開即需重新 OTP

## 補充：任務狀態 NOT_UPLOADED（測試帳號實測）
- 新帳號當期（尚未上傳）真實 state = **`period-state--NOT_UPLOADED`**（徽章「尚未上傳」），非 OPEN。
- 有「上傳運動紀錄」按鈕 → `href="/registrant/member/upload"`（不帶 UUID，綁當前期）。
- period-remaining 顯示上傳窗倒數（例「剩 1 天 12 小時」）。
- TaskParser 已修：`NOT_UPLOADED`（與 OPEN）→ `.open`。（狀態機順序推定：NOT_STARTED → NOT_UPLOADED(可上傳) → 待審核 → REDEEMABLE → REDEEMED；待審核/已上傳的 class 名尚未實測確認。）

## R1 解答：上傳運動紀錄表單（實測，唯讀 GET）
- GET /registrant/member/upload（需登入、當期為 NOT_UPLOADED 才有表單）。
- 欄位：`_csrf`（hidden）、**`screenshot`（type=file，即上傳檔案欄位）**。
- 限制：accept=image/jpeg,image/png；單檔上限 5MB（data-max-bytes=5242880）；僅能上傳一張。
- 內容規則：須原始截圖、日期須落在當週區間、須含運動時間/距離/步數；不得裁切/AI生成/翻拍；每人每期限一次；審查約 5 工作日。
- POST 端點同 action：/registrant/member/upload（multipart/form-data，body: _csrf + screenshot=@檔案）。
- → App UploadService 可據此接：multipart POST，file 欄位名 `screenshot`。

## R1 上傳 POST 實測結果（測試帳號，2026-09-05）
- 請求：POST https://500.gov.tw/registrant/member/upload
  - Content-Type: multipart/form-data
  - body: `_csrf`（hidden，來自上傳頁）＋ `screenshot`=@圖檔（image/png）
  - Referer: /registrant/member/upload
- 回應：**302 Location /registrant/member/tasks**（成功；無錯誤頁）
- 上傳後該期 state：`period-state--NOT_UPLOADED` → **`period-state--UNDER_REVIEW`**（徽章「待審核」）
- 圖片：1206×2622 PNG 357KB（<5MB），日期 9/3 落在第1期 09/01–09/06，通過前端限制。
- 坑：登入 session 偶發掉回 /access（CDN 黏著）→ 上傳腳本已加「登入後驗證 member/tasks 有 period-card、確認 file 欄位才 POST、最多重試3次」。

## 任務狀態機（實測完整）
NOT_STARTED（尚未開始）→ **NOT_UPLOADED（可上傳，有「上傳運動紀錄」鈕→/member/upload）** → **UNDER_REVIEW（待審核，約5工作日）** → REDEEMABLE（可兌換，有UUID）→ REDEEMED（已兌換）
- TaskParser 映射：NOT_STARTED→.notStarted；NOT_UPLOADED/OPEN→.open；UNDER_REVIEW/PENDING_REVIEW→.pendingReview；REDEEMABLE→.redeemable；REDEEMED→.redeemed。
