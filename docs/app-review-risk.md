# App Store 審查風險評估（揮汗有禮 非官方 App）

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
| 4 | 讀 HealthKit 步數上傳換券 | 5.1.3(i) | 逐字：健康資料換利益須「由提供利益之實體提交，且不得分享第三方」——兩項都不符 |
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
4. **HealthKit 只讀不傳**：改為顯示「已達標可上傳」+本機提醒；上傳用 `PHPickerViewController` 讓使用者自選截圖（不要用 HealthKit 數據產圖上傳）。→ 隱私標籤 Health=Not Collected。
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
