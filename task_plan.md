# 任務計畫：BitPrice — macOS menu bar 加密貨幣即時幣價 app

## 目標

建立一個 macOS menu bar 常駐 app，bar 上顯示單一主幣即時價格，點擊展開自訂清單面板（每列含符號、24h sparkline、價格、漲跌%），支援幣種搜尋與清單持久化，全程不依賴 Xcode 建置。

## 目前階段

Phase 2.16 完成 — revision 4.1 已產出（787 行、41 tests）。round-7 首次委派因審查者寫入專案檔案而中止，尚未取得複審結果

## 階段

### Phase 1: 需求與探索
- [x] 釐清使用者意圖（menu bar 幣價 + 自訂清單 + 搜尋）
- [x] 實測本機環境（macOS 15.6.1、Swift 6.1.2、Xcode 未安裝）
- [x] 實測 5 家公開 API 可用性與速率限制
- [x] 實測 sparkline 資料來源與批次能力
- [x] 分析參考 app 截圖，記錄介面結構
- [x] 發現寫入 findings.md
- **狀態:** complete

### Phase 2: 規劃與架構
- [x] 定義三層資料架構（WebSocket 價格 / REST sparkline / 搜尋）
- [x] 驗算 API 配額可行性
- [x] 確認建置路徑（原定 SwiftPM，Phase 2.6 實測後改為 `swiftc` 直接編譯 + 手工 `.app` bundle）
- [x] 確認 UI 規格（單一主幣、列四元素、24h 範圍）
- [x] 決策與理由記入 findings.md
- [x] 產出實作文件 `IMPLEMENTATION.md`
- [x] 委派 Codex review（thread `019fc726-637f-74b2-aff1-3c344477d7ee`）
- [x] 審查結果記入 findings.md（2 blocker、8 major、7 minor、3 nit）
- [x] 依審查結果修訂 `IMPLEMENTATION.md`（Phase 2.5，見下）
- **狀態:** complete

### Phase 2.5: 規格修訂（Codex 審查後新增）
實作前必須關掉的缺口。Codex 判定：架構可行，但這四塊未定義前不應開始寫程式。

- [x] **B1** Coinbase fallback 契約重寫 — Coinbase spot 無 24h 漲跌，需獨立契約 + `Quote.changeUnavailable` 狀態 + product ID 獨立解析持久化
- [x] **B2** 識別碼解析升為 `MarketMapping` 一級產物 — 含糊時要求使用者選擇，絕不由 symbol 重算 product ID
- [x] **改用 Binance 動態 `SUBSCRIBE`/`UNSUBSCRIBE`** 取代重建 combined-stream URL（revision 2 曾完成；revision 4 已反轉，改回重建 combined-stream URL，見 §6 item 3）
- [x] **M3** 定義 generation/token task 所有權模型 — 每 socket 單調遞增 ID，只有當前 generation 可套用變更（revision 4 已撤回 application-wide generation，改用 socket-local session UUID，見 §6 item 2）
- [x] **M4** 明確 socket 狀態機 `stopped → connecting → connected → suspending → suspended → reconnecting`（revision 4 簡化為三態 + 單一 owned task，見 §6 item 1）
- [x] **M5** 定義「healthy」為四個時間戳的組合，非單一條件（revision 4 簡化為 current-session identity + last valid success，見 §6 item 7）
- [x] **M6** 連線狀態拆為 `binanceState`/`coinGeckoState`/`coinbaseState`/`lastSuccessfulUpdate`（revision 4 UI 簡化為 live/stale/offline，見 §6 item 10）
- [x] **M1** 修正 Binance ping/限額描述 — 必須回應 server ping frame，app ping 不能取代（revision 4 砍除 app ping 與 23h reconnect，見 §6 item 14；server ping gap 另案處理）
- [x] **M2** sparkline 168 點不視為保證 — 加長度驗證與缺漏行為
- [x] **M7** `exchangeInfo` 快取加刷新策略（revision 4 撤回 listing-cache refresh，自動重新解析不納入本版，見 §6 item 13）
- [x] **M8** 補 HTTP status 檢查、percent-encoding、null/非有限數值防護
- [x] 修正 7 項 minor（含 §2 表與 §5.5 的 Coinbase 輪詢契約矛盾、`isStale` 未安排發布、空 watchlist 行為；revision 4 另簡化 rich per-source health）
- [x] 驗證計畫從 15 項擴充，補上 17 項未涵蓋案例（revision 4 後重整為 §8 的 24 項 focused tests）
- [x] §6 加入 `plutil -lint`、`codesign --verify`、`otool -L` 驗證步驟
- [x] 修訂後再次委派 Codex 複審（續接同 thread）
- **狀態:** complete（全部項目已在 revision 2 處理；後續複審與 revision 4 的反轉／簡化見 Phase 2.7–2.15）

### Phase 2.6: 工具鏈修復（已完成）
- [x] 診斷 `import Foundation` 失敗根因：兩個 modulemap 撞名宣告 `module SwiftBridging`
- [x] 使用者執行 sudo 停用舊檔 `module.modulemap` → `.disabled`
- [x] 驗證修復：`import Foundation` 通過（`fnd ok`）
- [x] 確認 SwiftPM 為獨立問題，修 modulemap 後仍壞（四種 manifest 組合皆失敗）
- [x] 驗證 `swiftc` 直接編譯路徑可用（Swift 6 模式 + Foundation/UserNotifications/AppKit）
- [x] 發現部署目標必須改 14.0（`.macOS(.v15)` 不存在於此工具鏈）
- [x] 確認 bare executable 會崩潰而非靜默失敗（`bundleProxyForCurrentProcess is nil`）
- [x] 確認手工 ad-hoc bundle 通過 `plutil -lint` 與 `codesign --verify`
- **狀態:** complete
- **未解**：SwiftPM 需 CLT 重裝；通知送達無法在此環境驗證（無 GUI session，AppKit 連不上 WindowServer）

### Phase 2.7: revision 2 規格與複審
- [x] 依 Codex round-1 意見全面改寫 `IMPLEMENTATION.md`（revision 2，含 changelog 對照表）
- [x] 新增 price alert 規格（§4.1 latch + cooldown 雙機制、§5.9 通知、§5.10 判定邏輯）
- [x] 初始清單改為 BTC 一檔、空清單列為合法狀態（不開 socket、不排程 timer）
- [x] 記錄工具鏈實測結果（§0、§0.1）與部署目標修正
- [x] 驗證計畫擴充至 48 項 + 4 項前置條件（含 test 20a 需手動執行）
- [x] 委派 Codex round-2 複審（續接 thread `019fc726-637f-74b2-aff1-3c344477d7ee`，確認 resume 成功）
- [x] 取得並記錄 Codex round-2 findings（首次回報遺漏內容，重新索取後取得完整）
- [x] round-2 結果：7 項關閉、3 項部分關閉、2 新 blocker、8 新 major
- **狀態:** complete

### Phase 2.8: revision 3 規格修訂（round-2 後新增，Phase 3 仍 gated）
Codex 明列實作前必須解決 6 項。架構再次獲確認，問題集中在生命週期與 mapping 完整性。

- [x] **B-new-1** 改雙 venue mapping `WatchItemMapping{binance:, coinbase:}` — 現行單一 mapping 讓 §7 的 geo-block fallback 無法成立；另加 `open > 0` 驗證
- [x] **B-new-2** ticker 比對降為候選過濾器 — 唯一相符**不等於**專案身分確認；需更強訊號（contract address）或一律使用者確認；UI 用字改「ticker 相符」
- [x] **M-new-1** 引入 **confirmed** 訂閱集合 + 控制命令序列化 + ack 後立即重新協調（revision 3 曾完成；revision 4 改回 combined-stream URL，整組 desired/confirmed/ack 設計撤回，見 §6 items 3–5）
- [x] **M-new-2** 明文規定 sleep 清空 confirmed、wake 從 desired 完整重新訂閱（revision 4 隨 desired/confirmed 設計撤回，見 §6 item 3）
- [x] **M-new-3** AlertEngine：hysteresis 改 `Decimal`、加輸入驗證（`threshold > 0`、`0 <= hysteresis < 100`、有限值、`cooldown >= 0`）、定義 migration 預設
- [x] **M-new-4** alert 持久化改非同步 — main actor 快照後 off-actor encode/write，加 revision number 保序（revision 4 改為 `@MainActor` 同步小型 atomic write，見 §6 item 8）
- [x] **M-new-5** Swift 6 並行：`TickerUpdate` 等全部標 `Sendable`、Foundation timer 改 `Task { @MainActor in }` 迴圈、`AlertEngine`→`WatchlistStore` 明確同 actor API（revision 4 保留 Sendable/Task 原則，持久化改由 `AppModel` + `PersistenceStore` 單一 main-actor domain）
- [x] **M-new-6** §0 的「verified working」限縮 — 只測過 Foundation/UserNotifications/AppKit，需完整 app（SwiftUI、MenuBarExtra、Canvas、WebSocket、Combine）驗證
- [x] **M-new-7** app 內 alert 歷史/badge 改為**強制需求**，不論 OS 通知成敗都要記錄（revision 4 明確撤回，僅保留 durable latch + OS notification，見 §6 item 9）
- [x] **M-new-8** 補 alert 邊界測試（revision 3 曾擴至 83 項；revision 4 保留行為與 failure-boundary 核心，縮為 §8 tests 19–23，見 §6 item 12）
- [x] 4 項 minor（Coinbase 只收 `status == online`、分來源時間戳、socket 用字、可注入 scheduler 供測試斷言；revision 4 將 rich per-source health 簡化，見 §6 item 10）
- [x] 2 項 nit（`Package.swift` 標註、「crossing」改「threshold breach」— 實為 level-triggered；revision 4 後不再使用 `Package.swift`）
- [x] 修訂後續接同 thread 進行 round-3 複審（high effort）
- **狀態:** complete（全部 14 項已處理，revision 3 產出）

### Phase 2.9: revision 3.1（round-3 後修正）
Round-3 以 high effort 審查，關閉 9/14，並抓出 1 個 revision 3 自己引入的 blocker。

- [x] **blocker** 新建 alert 的 `isArmed` 未定義 → 若為 `false` 則已越過門檻的新 alert **永遠不觸發**，違背 UI 文案與 test 46。改為三情境：新建 `true`、migration `false`、編輯重設
- [x] **major 2** ack 遺失無復原 → 型別化 `SubscriptionCommand`（generation + requestID + operation）、10s 逾時、逾時後**重連非重送**、batch 全有全無、error ack 不再歸咎 mapping
- [x] **major 3** 歷史與 alert 狀態可能分開寫入而互相覆蓋 → 單一 `AppSnapshot`，禁 partial write，歷史在通知前先排入持久化
- [x] **major 4** Coinbase 降級後無回復路徑 → 新增 §2.4.1，`activeExchange` 不持久化、回復需 connect + 訂閱 ack 雙確認、交接不空白
- [x] **major 5** `.verifiedIdentity` 依賴未定義的 metadata → v1 明確不實作 auto-accept，全部 `.userConfirmed`
- [x] **major 6** observer callback 隔離缺漏 → 補 `NSWorkspace` sleep/wake、ack completion、`PersistenceWorker` 檔案獨佔、scheduler `Sendable` 等 7 項
- [x] 4 項 minor（build script null-delimited、`.scheduled` 非 `.delivered`、test 20a 標 manual-only、test 6 雙軸斷言）
- [x] 2 項 nit（"crossing" 全面改 "breach"、§0 開頭去除過時敘述）
- [x] 新增 tests 36g–36p、61–69（ack 遺失、failback、latch 初始化）
- [x] 兩個 open question 依 Codex 建議定案（contract-address v1 不做、多 alert 延後）
- **狀態:** complete

### Phase 2.10: Round-4 複審與 revision 3.2
- [x] 送 round-4（high effort）。**首次委派失敗** — subagent 背景執行啟動即錯（`bfs: error: No such file or directory`），Codex 沒跑；改主執行緒直接 `codex exec resume` 成功
- [x] Round-4 結果：round-3 blocker 關閉，但 **revision 3.1 自己引入新 blocker** + 7 major
- [x] **blocker** §5.10 fire 路徑順序 → `notify` 在 latch 變更前，崩潰會造成**重複觸發**。改為單一交易：append 歷史 → 改 latch → 排入一份快照 → 才通知
- [x] **major 7** re-arm 未持久化 → 崩潰後保持解除武裝，**錯過下一次合法突破**。任何 latch 轉換皆立即持久化
- [x] **major 2** stale `inFlight` 仍在三處（我的 grep 只修一部分）→ 全改 `pending`，加 test 83 規格衛生檢查
- [x] **major 3** 逾時與重連未序列化 → 三條件檢查（generation + 命令身分 + connected）、`reconnect()` idempotent
- [x] **major 6** 一般性錯誤無界重連迴圈 → circuit breaker，連續 5 次失敗進終端 `.offline`，5 分鐘慢速重試
- [x] **major 5** failback 震盪 → 需首筆 tick + 60 秒 dwell + 來源 hysteresis（5→30 分）
- [x] **major 4** Coinbase-only 項目啟動在錯誤來源 → 依 mapping 可用性初始化
- [x] **major 8** Sendable payload 轉換 → `Error`/`Notification`/WebSocket message 在 callback 邊界就轉換
- [x] 新增 tests 70–83
- [x] 自查發現並修正 `activeExchange` 曾是 `Codable WatchItem` 的欄位（與「不持久化」規則直接矛盾）
- **狀態:** complete

### Phase 2.11: Round-5（換模型 gpt-5.6-sol，high effort，新 thread）
- [x] 改 `~/.codex/config.toml` 預設為 `gpt-5.6-sol` + high（已備份 `config.toml.bak`）
- [x] 送 round-5，read-only sandbox，無寫入權
- [x] **前兩次審查因規格過長（1,369 行）耗盡預算，未產出結論** — 改為不讀檔、以描述提問才成功
- [x] 結論與前四輪相反：**規格過度設計**。16 項機制建議砍 13 留 3
- [x] 「1,369 行 + 83 測試讓正確實作更可能還是更不可能」→ 直答**更不可能**
- [x] 附帶發現：**時鐘來源錯誤**（前四輪完全沒查）— 8 項時間量測中 7 項該用單調時鐘
- [x] 自查發現並修正 §5.4「one socket for the whole app lifetime」與 §5.2「at most one at a time」矛盾
- **狀態:** complete

### Phase 2.12: 決定路線（等使用者）
三選一：
1. **接受簡化，改寫 revision 4** — 砍 12 項（建議保留「每幣使用者確認」，因 round-2 B2 blocker 正是此問題），規格縮到 ~400–500 行、測試縮到 20–25 項
2. **照 revision 3.2 開工** — 機制齊全但 Codex 認為更難正確實作
3. **折衷** — 保留現有規格為風險清單，實作走簡化架構，踩到再加回

- [x] 使用者選擇路線 1：改寫 revision 4（簡化）
- **狀態:** complete

### Phase 2.13: revision 4 草稿
- [x] `cp IMPLEMENTATION.md IMPLEMENTATION_r32.md`（1,369 行完整保存）
- [x] 委派 Codex 寫草稿（`--sandbox workspace-write`，限定只能建 `IMPLEMENTATION_v4_draft.md`）
- [x] **委派失敗** — Codex 又在讀完 1,369 行後耗盡預算，未寫出任何檔案。這是同一份規格第 4 次耗盡 Codex 的預算（round-5 兩次、此次一次、加 round-5 的 excerpt 版一次）
- [x] 依三次失敗協定改變方案：改由主 agent 自行撰寫，材料用 Codex 已交付的砍除清單與時鐘表
- [x] 主 agent 產出 `IMPLEMENTATION_v4_draft.md`：**555 行、32 項測試**；此草稿後被覆寫，最終採用 Codex 的 **598 行、24 項測試**版本（相較原 1,369 行減 59%）
- [x] 驗證四大硬問題全部保留：Coinbase 無 24h 漲跌（不假造 0.00%）、CoinGecko symbol 不唯一、alert latch 雙向持久化、時鐘來源
- [x] 驗證工具鏈事實全部保留：SwiftPM 壞、`macosx14.0`、bare executable 崩潰、`warnings-as-errors`
- [x] 確認未動到其他檔案（`diff` 比對 r32 相同）
- **狀態:** complete

### Phase 2.14: 定案 revision 4
- [x] **修正先前誤判**：Codex 的委派其實成功了，只是檔案寫入晚於我的 `ls` 檢查。我誤判失敗後自行寫了 555 行版，隨後被 Codex 的 598 行版覆寫。教訓：宣告背景工作失敗前，必須確認檔案系統狀態而非只看一次 `ls`
- [x] 完整讀過 Codex 版 598 行全文
- [x] 驗證四大硬問題全部保留：`never fabricate 0.00%`、`symbols not unique`、`bidirectional latch durability`、`max(0, timeIntervalSince)` + 完整時鐘表
- [x] 驗證工具鏈事實全部保留：`__allocating_init`、`macOS(.v14)`、`macosx14.0`、`bundleProxyForCurrentProcess`、`warnings-as-errors`
- [x] Codex 版優於我的版本之處：BTC seed 也需明文 mapping（`Provenance.builtInBTC`）、`primaryItemID` 存 UUID 並定義刪除行為、stream 名稱排序以利測試、connection UUID 明確區別於 generation number、`schemaVersion` 支援遷移、損壞檔案不自動覆寫而是提供 Reset
- [x] `IMPLEMENTATION_v4_draft.md` → `IMPLEMENTATION.md`（598 行），草稿檔刪除
- [x] `IMPLEMENTATION_r32.md` 保留為歷史（1,369 行，五輪推理）
- **狀態:** complete

### Phase 2.15: Revision 4 首次審查
- [x] 委派 `gpt-5.6-sol`、**全新 thread**、`--sandbox read-only`（寫的人不能當審的人）
- [x] 明確要求**不要**讀 r32 與 findings.md（前四次爆預算的原因）
- [x] 我自行發現一項待確認缺口：§6 item 14 砍掉 app-level ping，但 §2.2 從未說明 server ping frame 仍須回應（round-2 M1 的發現）。已列為審查重點 2
- [x] 取得審查結果 — session `019fc82f-c4ff-7bb3-9af0-3e5903e893fe`（2026-08-03 23:13），**1 blocker、9 major、4 minor**。委派方式改為「prompt 內嵌完整 598 行 spec + 明令不讀檔」，一次成功未爆預算
- [x] 審查全文結構化記入 `findings.md`（判定原文另存 scratchpad `r4_review_verdict.md`）
- [x] 依結果決定：**不開工**，先修訂為 revision 4.1（見 Phase 2.16）
- **狀態:** complete
- **結果一度遺失**：審查 2026-08-03 23:13 就已回傳，但未寫入任何規劃檔案。三份文件此後持續記載「等待審查結果」，2026-08-12 才從 `~/.codex/sessions/` 復原。教訓見錯誤表
- **與 Codex 的唯一實質分歧**：它主張砍掉「每幣使用者確認」（理由：選搜尋結果就是確認），我保留並在 §2.4 寫下理由 — 使用者選的是 CoinGecko 幣，決定顯示價格的是交易所市場，兩者只靠 ticker 相連而 ticker 不可靠。失效後果是顯示錯幣價且無任何可見錯誤。**本輪審查未挑戰此決定**
- **六輪觀察**：round 1–2 抓設計缺口（真問題）、round 3–4 抓自身引入的矛盾、round 5 換模型後判定整體方向過度設計、round 6（本輪）抓的是**簡化時掉出來的接縫** — 砍掉機制後沒補上的連接點，不是「還不夠複雜」。簡化方向未被推翻，但執行留了洞

### Phase 2.16: revision 4.1 規格修訂（round-6 後新增）
實作前必須關閉。缺陷全文與修法見 `findings.md`「Revision 4 首次審查結果」。

- [x] **blocker** session UUID 所有權矛盾（§2.2 vs §3 vs §4.3）— actor 端檢查擋不掉已進 `AsyncStream` buffer 的舊 failure event，會把新 session 標記為失敗。改為每個 `FeedEvent` 都帶 `sessionID`、由 `AppModel` 比對、文字改稱 client-local epoch
- [x] **major 1** staleness 從不觸發 reconnect — 沒有任何一節呼叫 `reconnect()`，half-open 連線可無限存活。加 `connectedInstant`、首次 unhealthy 觸發一次 idempotent reconnect、已 backoff 者不重啟
- [x] **major 2** liveness 契約缺失 — 明文寫出 framework 自動回 Pong（app 不得自解 control frame）、清醒偵測窗實為 **60–75 秒**（非 60）、wake 行為
- [x] **major 3** Coinbase-only 項目可能永不取得報價 — fallback 只在 Binance 失敗/stale 後啟動，此類項目兩者皆無。改用 `needsCoinbase` 條件，立即輪詢後每 60 秒
- [x] **major 4** alert 求值順序未定義 — cooldown guard 未限定於 armed breach，會讓 disarmed alert 在 cooldown 期間無法 re-arm。明訂六步順序
- [x] **major 5** `isArmed` migration 做不到 — 非 optional 欄位缺失使整個 decode 失敗並誤入 malformed-file 路徑。加 versioned migration + `decodeIfPresent(isArmed) ?? false`
- [x] **major 6** 時鐘表不完整 — 補 300 ms debounce、15 秒 REST timeout、backoff、CoinGecko `Retry-After`（秒數或 HTTP date）與其作用範圍
- [x] **major 7** corrupt-file 保護未落實 — 一般編輯仍會 save 而覆寫損壞檔。改為 read-only recovery mode，Reset 為唯一可取代該檔的操作；另補母目錄建立
- [x] **major 8** 「每 30 秒重試」無保證 — backoff 重置時機未定義，可能持續 1 秒 churn。改為只在收到有效 tick 後重置，health-triggered reconnect 每 session 一次
- [x] **major 9** §8 的 24 測試漏掉 14 類核心已規定行為（非罕見邊角）— 全部補為 acceptance test
- [x] 4 項 minor（只在 Binance product 集合改變時重連、quote asset 依 `Quote.source` 推導、§4.6 rollback 用字修正、§7 Binance 中斷改「有舊報價則 stale」）
- [ ] 修訂後決定是否送 round-7 複審
- **狀態:** complete（14 項全修，`IMPLEMENTATION.md` 598 → 787 行、24 → 41 tests）
- **注意**：本輪 9 項 major 中，第 1、3、8 項與 4 項 minor 中的第 1 項，都是 revision 4 簡化時斷掉的連接點。修訂時**不應**整批加回 revision 3.2 的機制，而是補上缺的連接

### Phase 3: 實作 — 專案骨架與資料層
- [ ] `Models.swift` — §3 的 persisted/runtime types、雙 venue mapping、alerts 與 `Sendable` 邊界
- [ ] `PersistenceStore.swift` — Application Support JSON、首次 BTC seed、空清單、損壞檔案復原與 durable alert latch
- [ ] `BinanceStreamClient.swift` — combined-stream WebSocket、session UUID、idempotent reconnect 與 capped backoff
- [ ] `RESTClients.swift` — CoinGecko search/markets、Binance catalog、Coinbase products/stats 與 HTTP 邊界
- [ ] `AlertEngine.swift` — `Decimal` breach/hysteresis/cooldown 判定與 validation
- [ ] `NotificationService.swift` — 權限請求、local notification submission 與錯誤回報
- [ ] `AppModel.swift` — sole coordinator，整合 persistence、feeds、fallback、sparkline、clocks 與 UI state
- [ ] 不建立 `Package.swift`；建置由 Phase 4 的 `scripts/build-app.sh` 直接驅動 `swiftc`
- **狀態:** pending

### Phase 4: 實作 — UI 與 bundle
- [ ] `BitPriceApp.swift` — `MenuBarExtra` 進入點、window style 與單一主幣 bar 標題
- [ ] `Views.swift` — panel、watch row、`SparklineView`、搜尋/venue confirmation、alert sheet 與清單管理
- [ ] `Info.plist` — `LSUIElement=true`、`LSMinimumSystemVersion=14.0` 與 bundle metadata
- [ ] `scripts/build-app.sh` — `swiftc` Swift 6 strict build、手工 `.app`、ad-hoc signing 與 bundle 驗證
- **狀態:** pending

### Phase 5: 測試與驗證
- [ ] 依 `IMPLEMENTATION.md` §8 tests 1–2：strict `swiftc` build、簽章/bundle 驗證與 Aqua session launch
- [ ] 依 §8 tests 3–8：watchlist、persistence、primary identity、搜尋排序與雙 venue mapping
- [ ] 依 §8 tests 9–12：Binance parsing、idempotent reconnect、combined URL rebuild 與 retry boundary
- [ ] 依 §8 tests 13–16：Coinbase fallback/change、sparkline 與 HTTP failure boundaries
- [ ] 依 §8 tests 17–18：`ContinuousClock`/`SuspendingClock` sleep semantics 與 write debounce
- [ ] 依 §8 tests 19–23：alert validation、fire/re-arm、cooldown/rollback 與 persistence failure
- [ ] 依 §8 test 24：真實 GUI session 手動 notification smoke test（不作 core alert logic 成敗依據）
- [ ] 測試結果記入 progress.md
- **狀態:** pending

### Phase 6: 交付
- [ ] 檢視所有產出檔案
- [ ] 撰寫使用說明（啟動、加幣、設定主幣）
- [ ] 交付使用者
- **狀態:** pending

## 關鍵問題

1. 免費 API 能否支撐即時價格？ → 不能靠 REST 輪詢；已改 Binance WebSocket
2. 多幣走勢圖如何低成本取得？ → CoinGecko markets 單次呼叫拿全清單
3. 無 Xcode 如何產出可執行 app？ → `scripts/build-app.sh` 直接以 `swiftc` 編譯，再手工組裝並 ad-hoc sign `.app` bundle
4. WebSocket 斷線如何處理？ → 指數退避重連，UI 顯示 stale 狀態（待實作驗證）
5. 使用者新增幣種時，Binance 無該交易對怎麼辦？ → 有 Coinbase mapping 時呼叫 `GET /products/{id}/stats`，以 `last`/`open` 計算 24h change；`open <= 0` 或無效時顯示 `—`，無 Coinbase mapping 則顯示 unavailable / “No fallback market”
6. 主幣如何選定與切換？ → persisted root 以 UUID `primaryItemID` 儲存，不由列順序推導；刪除主幣時改選第一個剩餘項目，刪除最後一項後無主幣

## 已定決策

| 決策 | 理由 |
|------|------|
| Binance WebSocket 作價格層 | CoinGecko 免費月配額 10k 不足即時輪詢；WebSocket 零配額免 key |
| CoinGecko markets 作 sparkline 層 | 唯一支援多幣批次走勢的端點，1 call 拿完全清單 |
| sparkline 間隔 10 分鐘 | 底層 1h K 線，10 分鐘已超額精細；月用量 4,320 / 上限 10,000 |
| 走勢範圍 24h | 與列上 24h 漲跌% 一致，圖與數字同範圍 |
| `swiftc` 直接編譯 + 手工 ad-hoc-signed `.app` bundle | SwiftPM 在 tools-version 6.1 與 5.9 都因 `PackageDescription.Package.__allocating_init` undefined symbol 無法使用；build script 不得呼叫 `swift build` |
| MenuBarExtra + LSUIElement=true | 部署目標 macOS 14.0（`PackageDescription` 最高支援 `.macOS(.v14)`，`LSMinimumSystemVersion=14.0`），並隱藏 Dock icon |
| SwiftUI Path 自繪 sparkline | 維持零第三方依賴 |
| watchlist.json 存 Application Support | 標準位置，人類可讀可手改 |
| bar 只顯示單一主幣 | 多幣輪播會晃動、並排超 3 檔擠爆 bar |
| 列上同時放價格與漲跌% | 不點開即見完整資訊（比參考 app 多一項） |
| 接受 round-5 過度設計判定，revision 4 簡化 59%（1,369 → 598 行；83 → 24 tests） | 四輪持續加機制已達負邊際價值；不同模型判定規格尺寸會降低正確實作機率。15 項刪減及後果逐項記錄於 `IMPLEMENTATION.md` §6 |
| 保留每幣 venue confirmation | ticker match 只是候選過濾，不是 identity assertion；取消確認可能在無可見錯誤下顯示錯幣價，因此此項未依 round-5 建議刪除 |

## 遇到的錯誤

| 錯誤 | 嘗試次數 | 解決方案 |
|------|---------|---------|
| `xcodebuild` 無輸出（Xcode 未安裝） | 1 | 最終改走 `swiftc` 直接編譯 + 手工 bundle 路徑 |
| Binance klines `symbols=` 回 `-1102 Mandatory parameter 'symbol' was not sent` | 1 | 該端點不支援批次；sparkline 改用 CoinGecko markets |
| CoinGecko 免費配額不足即時輪詢（驗算超上限 4–17 倍） | 1 | 價格層改 WebSocket，CoinGecko 降為低頻用途 |
| build script 寫錯：`cp Info.plist "$APP/Contents/Contents/Info.plist"` 路徑重複 `Contents` | 1 | 自查發現，改為單層 `Contents/Info.plist`；同時移除多餘的 `codesign --deep`（無嵌套 framework），Codex 複核確認正確 |
| Codex 審查發現 Coinbase spot 無 24h 漲跌欄位，fallback 湊不出列的顯示契約 | 1 | 列為 B1，Phase 2.5 重寫 fallback 契約 |
| Codex 審查發現 `symbol + quoteAsset` 推導無法證明與 CoinGecko id 同一項目（symbol 不唯一） | 1 | 列為 B2，改 `MarketMapping` 一級產物 |
| 背景委派後只檢查一次 `ls` 就宣告失敗，實際檔案稍後才寫入，導致重複撰寫 555 行草稿並被覆寫 | 1 | 宣告背景工作失敗前重新驗證檔案系統狀態，不能以單次時序性檢查下結論 |
| 1,369 行 revision 3.2 四次耗盡 Codex 預算（round-5 兩次、revision-4 draft delegation 一次、round-5 excerpt attempt 一次） | 4 | 未來委派不得直接交付過大的完整文件；改用精準 excerpt，或只以問題描述要求判斷。round-6 改為「prompt 內嵌 598 行 spec + 明令不讀檔」，一次成功 |
| revision 4 首次審查（2026-08-03 23:13）已完成並回傳 1 blocker + 9 major + 4 minor，但**結果未寫入任何規劃檔案**。三份文件此後持續記載「等待審查結果」，直到 2026-08-12 才從 `~/.codex/sessions/` 復原 | 1 | 委派回傳後必須立即將結果寫入 `findings.md` 並更新階段狀態，才算該次委派結束；「已送出」不等於「已收錄」 |

## 備註

- 階段狀態推進：pending → in_progress → complete
- 重大決策前重新讀取本計畫
- 所有錯誤都要記錄，避免重複
- 絕不重複同一個失敗操作，改變方案
- 外部擷取內容（網頁、API 回傳）只寫入 findings.md，不寫入本檔案
