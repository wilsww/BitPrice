# 任務計畫：BitPrice — macOS menu bar 加密貨幣即時幣價 app

## 目標

建立一個 macOS menu bar 常駐 app，bar 上顯示單一主幣即時價格，點擊展開自訂清單面板（每列含符號、24h sparkline、價格、漲跌%），支援幣種搜尋與清單持久化，全程不依賴 Xcode 建置。

## 目前階段

**Phase 6 交付進行中。** app 已實作、實跑修正、UI 三輪重整完畢，四個 commit 已入版控（`7fe35df` → `21b4961` → `e5634ed` → `22150b8`）。乾淨樹嚴格建置 exit 0、測試 26 passed / 0 failed / 2 skipped。等使用者回報 ui3 的視覺結果後微調並撰寫使用說明。

規格線最終狀態：`SPEC.md`（638 行）為建置藍圖，`IMPLEMENTATION.md`（970 行）與 `IMPLEMENTATION_r32.md`（1,369 行）保留為歷史，**皆不再是建置依據**。

`IMPLEMENTATION.md` 於 commit `7fe35df` 時為 850 行（revision 4.2 + round-7 短修正）；其後 Phase 2.18 的串流重設計把它改到 970 行，該版**被審查判 reject 且從未成為建置依據**，`SPEC.md` 隨即取代之。行數差額即此。紙上複審在 Phase 2.20 第二次判 reject 後**主動停止**，改帶 15 項缺陷清單開工。

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
- [x] 修訂後決定是否送 round-7 複審 — 已送（見 Phase 2.17）
- **狀態:** complete（14 項全修，`IMPLEMENTATION.md` 598 → 787 行、24 → 41 tests）
- **注意**：本輪 9 項 major 中，第 1、3、8 項與 4 項 minor 中的第 1 項，都是 revision 4 簡化時斷掉的連接點。修訂時**不應**整批加回 revision 3.2 的機制，而是補上缺的連接

### Phase 2.16b: revision 4.2（round-7 部分筆記的修正）
Round-7 兩個 lens 被中止前未產出 verdict，但其工作筆記已抓到 3 項真缺陷。逐項查證後全部成立並修正。

- [x] **`PersistedState` 缺 root decoder** — `schemaVersion` 是非 optional `Int`，synthesized decoding 遇缺鍵即失敗，我在 §3 寫的「absent 分支」根本走不到，舊檔會被誤判為 malformed。加自訂 `init(from:)` 用 `decodeIfPresent ?? 0`，並補「已知較舊版本」分支
- [x] **`lastValidTick` 是 session-wide** — combined stream 中某一 product 持續 tick 會讓整個 session 看似健康，另一 product 永久靜默卻不觸發 reconnect，等於架空 §6 item 4。改為 per-product 計齡，session age 取最舊者
- [x] **epoch 取得是循環論證** — §4.3 只給 `events`/`reconnect`/`stop`，`AppModel` 無從得知當前 epoch，只能從事件裡讀；但 buffer 中的舊事件可能先到，採用它的 epoch 正好授權了該機制要擋的東西。`reconnect()` 改為回傳新 epoch，並加 `currentEpoch()`
- [x] 新增 tests 26（partial stream silence）、27（absent schemaVersion），其後測試重新編號至 43
- **狀態:** complete（839 行、43 tests）
- **教訓**：這 3 項全是 revision 4.1 修訂時自己引入或未補完的，與 round 3–4 的模式相同。第 2、3 項尤其值得記：我補的機制在文字上成立，但缺少讓它實際可運作的介面或粒度

### Phase 2.17: round-7 複審完成 — 判 reject
`run_id=r42`，gpt-5.6-sol high effort，雙 lens 各自獨立。**20 項全 `true_hit`：2 blocking、12 major、6 minor。** 完整判定見 `findings.md`「Round-7」節。

委派本身首次完全按預期完成：contamination gate 通過、`git status` 乾淨、spec md5 `b06d3c0` 未變。Phase 2.16b 的 sandbox 破口修復實戰驗證有效。

- [x] 收錄 verdict 至 `findings.md`
- [x] 修正 test 24/26 的 60 秒邊界（演算法為嚴格大於，測試卻要求剛好 60 秒即重連）
- [x] `PriceAlert` 的 `decodeIfPresent(isArmed) ?? false` 限定只作用於 schemaVersion 0
- [x] §4.2 補上「unrecognized older version 進入 read-only recovery」，與 §3 第四分支對齊
- [x] **FLAG — 串流介面整體重設計** → 已於 Phase 2.18 完成
- [ ] FLAG — 其餘既存 major/minor 中未被重設計涵蓋者（watchlist 上限、termination flush、Coinbase late response、root invariant 驗證、sparkline 24 小時保證、單一實例 atomicity）→ **改列為實作期風險清單**，不再於紙上修訂
- **狀態:** complete（短項已補；串流重設計見 Phase 2.18）

#### FLAG：串流介面必須整體重設計，不得再局部修補

兩個 blocker 都出在 `BinanceStreamClient` 的介面，且都是 revision 4.2 修法自己造成的：

1. `reconnect()` 有回傳值但**無參數** — watchlist 變動時重建的是舊 URL；啟動路徑的 `events(for:)` 則能收 product 集合卻不回傳 epoch。兩條路徑各缺一半
2. client **自主 retry** 產生的 successor epoch 沒有任何管道能到達 `AppModel`，而 §4.3 為了堵住循環論證所寫的 `currentEpoch()` 禁令，同時關掉了唯一替代路徑 → Binance 斷線後永久卡死

外加 §2.2 的 retry counter 粒度是 session、但需偵測的是 per-product，造成靜默 product 每 60–75 秒強制整條重連且永不進入 backoff cap。

**這個介面已連補四輪，每輪修出下一輪的 blocker。** 兩個 lens 在 `what_would_change_my_mind` 各自獨立提出同一結論：合併為單一 lifecycle contract，一次涵蓋 start、product 集合替換、空集合停止、client 自主 retry 的 epoch 交付、continuation 所有權、epoch 安裝與 consumer barrier。

**不要**在現有三個 method 上做第五次增補。

### Phase 2.18: 串流介面整體重設計（revision 4.3）
不是第五次局部修補。§4.3 整段刪除重寫，§4.1/§4.1.1/§2.2/§3 同步改。

**根因判定**：三個 blocker 不是三個缺陷，是同一個。`AppModel` **持有授權狀態**（current epoch），卻必須從一個會自行改變該狀態的元件**帶外取得**。回傳值永遠補不上這個縫，因為該元件不是每次都經由回傳路徑。

- [x] 授權移入 actor 內。`AppModel` 不再持有 epoch、不做任何 epoch 比對
- [x] 三 method 改為三個**意圖**：`setProducts(_:)`（start / 換集合 / 空集合停止，三合一且 idempotent）、`events()`（終身單一 stream）、`reconnectForHealth()`（無回傳值）
- [x] 刪除 `currentEpoch()`、`stop()`、`FeedEvent.epoch`
- [x] 新增 `.superseded` **in-band ordered barrier** 取代 consumer 端過濾 — 靠 stream 順序判定新舊，不靠跨 actor 的識別碼比對。`AsyncStream` 本就保證順序，跨 actor 識別碼一致性則否
- [x] 自主 retry 與外部呼叫走同一條 supersede 路徑，因此不需要任何管道回傳 epoch → blocker 2 從結構上消失
- [x] retry counter 粒度改為「**所有**訂閱 product 都收到有效 tick 才 reset」→ 靜默迴圈 major 消失
- [x] §4.1 改為每次 watchlist 變更都呼叫 `setProducts`，抑制重連由 idempotent 契約保證，不再是呼叫端的前置條件（呼叫端版本正是「重連舊 URL」的來源）
- [x] 併入 B#5（empty→nonempty 重啟）：週期迴圈改 gate 於 watchlist 而非 Binance set
- [x] 併入 A#6（重複 venue product ID）：入口即拒絕，tick 遞送維持 lookup 而非 fan-out
- [x] tests 24/25/28/29 改寫 + 新增 29a（自主 retry 復原）、29b（空集合生命週期）、29c（重複 product ID）
- [x] 委派 Codex 審查此契約（run `r43b`）— 唯一被證實有效的防線
- [x] **審查判 REJECT**（兩 lens 獨立收斂）。`.superseded` barrier 依賴 `AsyncStream` 不存在的 purge 能力；`reconnectForHealth()` 無參數不可能 idempotent；另有兩處我自己造成的殘留矛盾（§6 item 2、§2.2:89）。全文見 `findings.md`
- **狀態:** rejected — 需第二版契約
- **注意**：本次刻意**不**逐條修 20 項清單。C 群其餘 6 項轉為實作期風險清單
- **教訓（第五次同一形狀）**：我把授權移進 actor（方向正確），但選的替代機制假設了一個語言不提供的操作。**寫契約時必須逐一指出每個機制由哪個具體 API 提供**，不能只寫「barrier 會處理」。這次是**審查擋下的，不是自己看出來的** —— 再次印證 findings.md:845

### Phase 2.19: 委派 Codex 從零重新設計 → `SPEC.md`（2026-08-13）
不再由主 agent 寫契約。理由：同一介面連續五次自我引入缺陷，無任何一次通過紀錄；寫的人不能當審的人，而我已證明是這介面上最不適合寫的人。

`run_id=rd1`，implement mode，`--expect-changed` 三檔驗收。Codex 用自己的 planning-with-files 產出 `.planning/redesign/{task_plan,findings,progress}.md`，交付物為 **`SPEC.md`（638 行）**。

- [x] Brief 把失敗形狀寫成**結構性約束**而非警告：每個機制必須指名哪個 interface member 提供每個 input、哪個 platform API 執行每個操作，指不出來就重新設計
- [x] 今天兩份 lens verdict 列為必讀輸入（`what_would_change_my_mind` 為最有價值部分）
- [x] 實測事實列為不可協商；venue confirmation 明列為使用者已裁決、不得再翻
- [x] 驗證 Codex 未動 `IMPLEMENTATION.md` 與根目錄三份規劃檔（mtime 全部早於 dispatch 20:19）
- **狀態:** complete（待獨立複審）

#### 架構轉向：消滅問題而非修補

| 舊設計 | `SPEC.md` |
|---|---|
| `BinanceStreamClient` 為獨立 actor + `AsyncStream` | `BinanceFeedController` 與 `AppModel` **同屬 `@MainActor`**，無 `AsyncStream`、無 continuation |
| epoch 跨 actor 交付 | identity 留在 controller 內；每個 `await` 後、每次 mutation 前比對 captured vs current |
| `reconnectForHealth()` 外部呼叫 | **無此 method**。lease 與 retry 全在 controller 內完成 |
| 60 秒無 tick 判定 product 已死 | **刪除**。改 5 分鐘 lease 無條件輪替，明寫是 bound 不是 detector |
| CoinGecko 批次 sparkline | **刪除**。改有時間戳的 1h K 線（Binance klines / Coinbase candles） |
| 500 ms debounce | **刪除**。每次編輯即時 full-state atomic write |
| `NSRunningApplication` check-then-act | `flock(LOCK_EX \| LOCK_NB)` |

關鍵順序：**新 identity 同步安裝完成後才取消舊工作**。舊 `receive()` 晚到能抵達 main actor，但在套用 quote 前就失敗於 identity check。**沒有 app 層 buffer 需要清除** —— 前次 blocker（`AsyncStream` 無 purge API）因此不存在。

#### 五次失敗形狀逐一結構性消失

1. 介面無參數傳 product 集合 → 只剩 `replaceProducts(_:)` 一個入口，必然收集合
2. 自主 retry 的 epoch 無管道 → 無 epoch 跨界；自主 retry 用同一組 current-ID check
3. counter 粒度 session vs 需偵測 per-product → **product 靜默完全不再觸發修復**，counter 改為 connection-level（lease 完成 + delegate-open 滿 60 秒才 reset）
4. handoff 非原子 → 同一 actor，無 handoff
5. 假設 `AsyncStream` 有 purge → 無 stream

#### round-7 六項未修缺陷：全部逐項查證已解（非接受）

watchlist 上限 25、termination flush（debounce 刪除故窗口不存在）、Coinbase late response（`FallbackRequestToken` 五欄位 + 15 秒 elapsed check）、root invariant（§4.3 十二條驗證器，違反者進 recovery 不靜默修復）、sparkline 24 小時（改時間戳 K 線）、單一實例 atomicity（`flock`）。

- [ ] **獨立複審 `SPEC.md`** — 未做。Codex 寫的，Codex 不能自審
- **教訓**：這次真正換了寫的人。前五次都是「同一個 agent 修自己的介面」，第六次換手後，五個缺陷是**被結構消滅**而非被補丁

### Phase 2.20: `SPEC.md` 獨立複審 → reject（run `spec1`）
全新 thread、雙 lens、`--web-search`。lensA 8 項、lensB 7 項，**四項獨立收斂**，全部經我對照檔案查證屬實。判定與全文見 `findings.md`。

主架構未被推翻（五個舊失敗形狀確實結構性消失），但六個 blocking 中至少三個是同一形狀的新實例 —— 換作者未換掉形狀。決定**不再修訂第七次**，改帶清單開工。

- **狀態:** complete

### Phase 3–4: 實作（委派 Codex，run `impl1`，2026-08-13）
15 項複審缺陷**前置為建置需求**，非事後待辦。修法逐項取自兩個 lens 的 `what_would_change_my_mind`。

- [x] 11 個 source 檔（2,841 行）+ `Info.plist` + `scripts/build-app.sh` + `scripts/run-tests.sh`
- [x] `Tests/TestMain.swift`（578 行）+ 真實 v0/v1 JSON fixture
- [x] `.planning/impl/{task_plan,findings,progress}.md`
- **狀態:** complete

#### 我獨立驗收的結果（非採信 Codex 報告）

| 驗收項 | 指令 | 結果 |
|---|---|---|
| 乾淨樹嚴格建置 | `rm -rf build && bash scripts/build-app.sh` | **exit 0** |
| 測試 | `bash scripts/run-tests.sh` | **25 passed, 0 failed, 2 skipped**（skip 皆印出理由） |
| 嚴格模式確實啟用 | grep build script | `-swift-version 6`、`warnings-as-errors`、`-target arm64-apple-macosx14.0` |
| SwiftPM 未被使用 | grep `swift build` / `Package.swift` | 全無 |
| bundle 真實性 | `codesign --verify --strict` / `plutil -lint` / `file` | 全通過，Mach-O arm64 |
| bundle metadata | `plutil -extract` | `LSUIElement=true`、`LSMinimumSystemVersion=14.0` |
| 保護檔案未被動 | mtime vs dispatch 21:04 | 四檔全部早於 dispatch |

#### 15 項缺陷抽查（讀碼確認）

- **缺陷 1**：`makeLifetimeSession` 一次建立終身重用；`didOpen`/`didClose` 皆帶 `connectionID: UUID`，整數不再是唯一憑證
- **缺陷 3**：`actor TokenBucketPacer`，Coinbase `ratePerSecond: 10, burst: 15`（與官方文件一致），Binance/CoinGecko 各自實例，clock 為注入
- **缺陷 6**：`Tests/Fixtures/watchlist-v0.json`、`watchlist-v1.json` 真實存在

#### 未能驗證（本機限制，Codex 誠實聲明未謊報）

無 Aqua GUI session → 無法啟動 app、無法驗證通知呈現、無 live network smoke test。測試以注入 fake 完成 deterministic 驗證。

### Phase 5: 實跑驗證 — 六項缺陷（2026-08-13，commit `e5634ed`）
使用者首次在真實桌面啟動 app。**七輪規格複審、43 項規定測試、25 項實作測試全數放行的六個缺陷，數分鐘內全部浮現。**

- [x] **崩潰：alert 觸發即整個 app 死** — UserNotifications 在自己的 queue 回呼，`NotificationService` 標 `@MainActor` 使 closure 繼承該隔離，Swift 6 runtime 在 `dispatch_assert_queue` trap。**修了兩次**：移除型別上的 `@MainActor` 不夠，`withCheckedContinuation` 的 body 繼承的是**呼叫端**隔離，而 `AppModel` 從 `Task { @MainActor }` 呼叫。改為每個 continuation body 明標 `@Sendable`，非 Sendable 的 `UNNotificationRequest` 在 closure 內建構
- [x] **面板每次互動即消失** — `MenuBarExtra(.window)` 失去 key window 即關閉，而 `.sheet` 正是造成此事。編輯器改由 `PanelRoute` enum 就地替換面板內容；venue `Picker` 同缺陷改 inline radio，direction 改 `.segmented`
- [x] **無退出途徑** — `LSUIElement` 移除 Dock icon 與 app menu，`pkill` 是唯一出口。面板加電源鍵 + 兩段式確認
- [x] **存 alert 導致退出**（我自己加退出鍵造成的回歸）— Save 帶 `.defaultAction`、quit 帶 `⌘Q`，回到清單後同一鍵盤事件抵達 quit。兩個 shortcut 全移除
- [x] **漲跌%取整** — `NSDecimalNumber.rounding(nil)` 把真實的 `+1.34%` 印成 `+1%`，讀起來像解析失敗。改兩位小數。原 test 22 只斷言正負號故一路通過，已補回歸斷言
- [x] **hysteresis 不可見** — 引擎正確，UI 從未揭露規則：1% hysteresis 在 63,966 門檻上等於要跌 640 才 re-arm，看起來像壞掉。編輯器改為明寫觸發價與 re-arm 價
- [x] 使用者實測確認：通知橫幅送達；Wi-Fi 關閉轉 stale、開啟即回 live。**此復原路徑正是四輪紙上複審都沒改對的那條**
- **狀態:** complete

### Phase 5.1: UI 三輪重整（委派 Codex `ui1`/`ui2`/`ui3`，commit `22150b8`）
三輪皆為呈現層變更，硬約束派工：禁 `.sheet`/`.popover`/`.alert`/`.confirmationDialog`/`NSAlert`/menu-style `Picker`、禁 `.keyboardShortcut`、禁動 `NotificationService.swift`、禁 `@preconcurrency`/`@unchecked Sendable`/`Task.detached`、禁 SwiftPM、禁造假資料。**每條約束都來自一個已發生的崩潰或缺陷。**

- [x] **ui1-1 app 圖示** — `scripts/make-icon.swift` 程式繪製，`make-icon.sh` 產 10 尺寸 iconset 後 `iconutil` 打包，build 時嵌入。無第三方素材、無 binary 進版控
- [x] **ui1-2 bar 顯示主幣價格** — 根因為 API 誤用：`MenuBarExtra(_:systemImage:)` **只渲染圖片並靜默丟棄標題**。`menuBarTitle` 一直正確產出 `"BTC 63,928.65"` 卻從未顯示。改 `label:` 形式
- [x] **ui1-3/ui2-2/ui3-3 字級** — 三輪逐步放大，全程用 Dynamic Type styles 而非固定點數，面板增至 660×780
- [x] **ui1-4 版面重構** — 一列一幣（star / symbol / quote / price / change% / Alert）；sparkline、mapping IDs、排序鍵移入底部詳細區。**mapping IDs 保留而非刪除** —— 那是使用者確認該列追蹤哪個市場的唯一依據，正是 venue confirmation 存在的理由
- [x] **ui1-5 選取與設主幣刻意分離** — 星號決定 bar 顯示什麼，混為一談會使「看個圖」靜默改掉 bar
- [x] **ui2-1 退出鍵移至標題左側 + 確認式** — 新增 `PanelRoute.confirmQuit`。不能用系統對話框，與「按鈕害面板消失」是同一機制
- [x] **ui2-2 Add coin 對齊** — symbol 改固定寬度前導欄，`SAND`/`SNDKON`/`S&AMP;L` 不再各自把名稱推到不同 x
- [x] **ui3-2 走勢圖 X/Y 座標軸** — `ChartAxisCalculator` 取真實 min/max 與真實時間戳。**絕不造假 tick**；flat / 單點 / 空序列三個退化情況皆處理並以 test 22b 斷言，涵蓋 63,824 與 0.33 兩種價格尺度
- [x] **ui3-1/ui3-4 使用者前提查證後不成立，未照單修改** — 星號**確實有作用**（設定 `primaryItemID` 並驅動 `menuBarTitle`）；圖示**已正確產生**（10 尺寸、256px 為 60 KB 非空白），Finder 顯示的是舊快取。以 AskUserQuestion 交回裁決，選擇為「保留星號但加強說明」與「先只清快取」
- **狀態:** complete
- **未驗證（本機無 Aqua GUI session）**：版面比例、字級是否足夠、座標軸標籤是否擁擠、圖示清快取後外觀 —— 只有桌面前的人能判斷

### Phase 6: 交付
- [x] 四個 commit 入版控：`7fe35df`（規格）→ `21b4961`（實作）→ `e5634ed`（實跑修正）→ `22150b8`（UI 重整）
- [x] 提供安裝與清快取步驟（複製至 `~/Applications` 以繞開 TCC 對 `~/Documents` 的阻擋）
- [x] 補齊根目錄三份規劃檔的實作期紀錄
- [ ] 使用者回報 ui3 視覺結果並依回報微調
- [ ] 撰寫使用說明（啟動、加幣、設定主幣、設 alert）
- **狀態:** in progress

### Phase 5.2: Settings 頁面與 alert 總開關（規劃中，待委派 `ui4`）
使用者於 2026-08-14 提出三項，另加一項我從截圖發現的缺陷。

- [ ] **新增 Settings 頁面** — `PanelRoute` 加 `.settings` case，header 右側加齒輪鍵。與 `.add`/`.alert`/`.confirmQuit` 同一就地替換模式，不得引入任何獨立 window
- [ ] **退出鍵移入 Settings** — header 左側電源鍵移除，`PanelRoute.confirmQuit` 隨之刪除。**使用者裁決：Settings 內直接退出，不再另跳確認頁**（齒輪 → Settings → Quit 已是三步，Settings 頁本身構成刻意進入，誤觸風險由路徑深度消化）
- [ ] **Alert 總開關** — **使用者裁決：完全暫停求值**。關閉期間 `AppModel.evaluateAlert` 直接 return，`isArmed`/`lastFiredAt` 完全凍結不變。重新開啟後若價格仍在門檻外，下一個 tick 立即觸發
- [ ] **總開關關閉時必須在清單列上可見** — 否則使用者會看到 `Alert` 鍵、設定完成、然後什麼都不發生。**這正是 hysteresis 缺陷的形狀**（引擎正確、UI 未揭露），不得重演
- [ ] **Y 軸刻度位數不一致**（截圖發現，使用者未提）— 端點為真實 min/max（`0.3384`/`0.3268`，4 位），中間刻度為 `min + step × i` 的除不盡值，經 `formatPrice` 對 <1 價格給到 6 位而印出 `0.334533`。**使用者裁決：刻度值取整到一致位數，但軸的上下界仍須涵蓋真實 min/max**

#### 持久化：`schemaVersion` 維持 1，不得升版

`alertsEnabled` 為 root 層布林值。**`currentSchemaVersion` 必須維持 `1`**，以 `decodeIfPresent(...) ?? true` 讀取。

理由：`DomainModels.swift:387` 的 `guard state.schemaVersion == currentSchemaVersion` 是**嚴格相等**。若升到 2，現有使用者的 v1 檔案會落入 `.unregisteredOlder` 分支 → **整個 app 進 read-only recovery mode，watchlist 退回只有 BTC 的種子**。這與 round-6 major 5（新增非 optional 欄位使整份檔案 decode 失敗）是同一形狀。

`V1StateDTO.init(from:)` 為手寫逐鍵解碼，未知鍵自動忽略，故新欄位不會破壞舊版讀取。反向降級亦安全：舊版 app 忽略 `alertsEnabled` → alert 全開，**不會靜默吞掉通知**。

#### Y 軸：刻度值與軸界必須分離

取整後的刻度**不可**反過來當作繪圖的 min/max，否則資料點會畫到格線外或被裁掉。刻度線是參考線（不宣稱是資料點，故可取整）；軸界是資料真實範圍（必須涵蓋 min/max）。兩者是不同的量。

### Phase 5.3: Settings 頁面精修與字級設定（規劃中，待委派 `ui5`）
使用者於 2026-08-14 檢視 `ui4` 成果後提出五項。續接 `ui4` thread `01a0006d-7b5d-7831-94c1-a9986de4a7d5`。

- [ ] **Settings 標題置中** — 與 header 兩側控件對稱
- [ ] **Alert 開關改用 switch 控件** — 目前為 checkbox。`Toggle` + `.toggleStyle(.switch)`（macOS 13+ 原生）。語意更貼切：checkbox 讀起來像「選項」，switch 讀起來像「電源總開關」
- [ ] **Quit 移至右上角、返回鍵移至左上角** — **使用者裁決：兩鍵分居兩端**。返回是安全操作、Quit 是破壞性且已無確認頁，相鄰放置會誤點。上一輪「Settings 內直接退出」的裁決維持不變
- [ ] **`Done` 改為返回語意** — 此頁設定即時生效，`Done` 暗示需確認才生效，屬誤導。改為返回箭頭 / `Back`
- [ ] **新增 app 內字級設定** — 見下方前提
- [ ] **幣別列與 Settings 的圖示再放大**

#### 字級：現況並非「寫死」，但使用者的體感成立

程式全面使用 Dynamic Type styles（`.title2`/`.headline`/`.body`），**無任何固定點數**，因此已跟隨 macOS 系統文字大小。使用者回報「不可調整」的實際原因是該系統設定藏在「系統設定 → 輔助使用 → 顯示器 → 文字大小」且多數 app 不支援，故無人會去調。

app 內以 `.dynamicTypeSize(...)` 覆寫整個面板可行，但有兩項後果：

1. 放大後面板不會自動長高 → **使用者裁決：面板隨字級同步放大**（小 560×700 / 中 660×780 / 大 760×880 / 特大 860×980）
2. 此設定會**覆寫**系統輔助使用設定，對真的調過系統設定的人是退步 —— 故採相對級距而非絕對點數，且中級即為現行外觀

字級偏好與 `alertsEnabled` 同樣持久化於 root，**`schemaVersion` 一樣不得升版**（理由同 Phase 5.2）。

### Phase 5.4: 字級改用倍率、圖示對齊（規劃中，待委派 `ui6`）
`ui5` 交付後使用者實跑發現兩項。續接同一 thread。

- [ ] **字級設定無效 —— 只有面板放大，字沒變** —— 見下方根因
- [ ] **`+` 與齒輪視覺大小不一致** —— 兩者皆 `.imageScale(.large)` 且字級相同，差異來自 SF Symbol 本身的視覺重量：`plus` 為兩條細筆畫，`gearshape` 為帶齒實心輪廓，同 point size 下面積差距明顯。**使用者裁決：改用 `plus.circle` / `gearshape.circle`**，兩者皆有外框以對齊視覺重量

#### 根因：`.dynamicTypeSize` 在 macOS 不縮放語意字體

`.dynamicTypeSize(...)` 是 **iOS 機制**。macOS 的文字縮放走系統輔助使用設定，SwiftUI **不允許 app 覆寫**。該 modifier 確實寫進了 environment，但**沒有任何 `Text` 會因此改變大小**；而同時掛上的 `.frame` 依級距生效，於是產生「框變大、字沒變」。

**這是我的規劃缺陷，非 Codex 執行錯誤。** brief 直接指名了 `.dynamicTypeSize(...)` 這個 API。這正是本專案的招牌失敗形狀再現一次：**假設一個平台操作存在，但它在該平台上不做那件事**。前次是 `AsyncStream.Continuation` 沒有 purge，這次是 macOS 的 `dynamicTypeSize` 不縮放字體。差別在於這次由實跑在數分鐘內抓到，而非七輪紙上複審。

#### 修法與其代價（使用者已裁決：採倍率）

macOS 上「app 內可調字級」與「跟隨系統輔助使用設定」**不可兼得**。採倍率方案：

- 四級距對應倍率（Small 0.85 / Medium 1.00 / Large 1.20 / Extra Large 1.45），Medium 即現行外觀
- **必須引入固定點數**，故解除 `ui5` brief 中「禁 `.system(size:)`」的約束
- 但固定點數**只允許出現在單一集中的字型函式內**。散落各處等同回到 ui1 之前的狀態，該狀態正是「UI 文字都過小」那輪的成因
- 明確接受的代價：不再跟隨 macOS 輔助使用的文字大小設定

### 實作期風險清單（round-7 C 群，不再於紙上修訂）
下列六項於 Phase 2.17 決定轉為實作期風險，Phase 2.19 的 `SPEC.md` 已逐項查證為**已解**（非接受）。實跑至今未觸發，保留備查：

watchlist 上限 25、termination flush（debounce 已刪除故窗口不存在）、Coinbase late response（`FallbackRequestToken` 五欄位 + 15 秒 elapsed check）、root invariant（`SPEC.md` §4.3 十二條驗證器，違反者進 recovery 而非靜默修復）、sparkline 24 小時保證（改用有時間戳的 K 線）、單一實例 atomicity（`flock(LOCK_EX | LOCK_NB)`）。

### 已知未測路徑
- 刪除主幣後的 fallback 選取
- 損壞檔案的 read-only recovery mode（有 fixture 測試，無實跑）

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
| 第二次 reject 後**停止紙上修訂**，帶 15 項清單開工 | 六個 blocking 全屬「實作第一天就會撞到並且立刻知道答案」的類型（缺 initializer、缺 token、schema 未定、限流未定）。再推一輪只會產出 round-9。改由編譯器與測試取代 review 當驗證來源 —— 事後證明成立：一次委派即交付通過嚴格建置與全部測試的實作 |
| sparkline 改用有時間戳的 1h K 線（Binance klines / Coinbase candles），放棄 CoinGecko 批次 sparkline | CoinGecko sparkline 無時間戳，無法誠實宣稱「24 小時」，也畫不出 X 軸。此決定在 UI 階段回收價值：`ChartAxisCalculator` 的時間刻度直接取自真實時間戳 |
| 面板內一切互動就地渲染，禁用所有系統彈出式呈現 | `MenuBarExtra(.window)` 失去 key window 即關閉，`.sheet`/`.popover`/`.alert`/`.confirmationDialog`/menu-style `Picker` 全數觸發此行為。編輯器、venue 選擇、退出確認一律走 `PanelRoute` enum 就地替換 |
| 面板內禁用 `.keyboardShortcut` | Save 的 `.defaultAction` 與 quit 的 `⌘Q` 曾讓同一個鍵盤事件跨畫面抵達退出鍵 |
| 圖示程式繪製、build 時產生，不進版控 | 零第三方素材依賴，可重現，且不必在 git 存 binary |
| 選取列與設定主幣分離 | 星號決定 menu bar 顯示哪一幣；若點列即設主幣，使用者只是想看走勢圖就會靜默改掉 bar |
| mapping IDs 保留（移入詳細區而非刪除） | 那是使用者確認該列實際追蹤哪個市場的唯一依據，正是 venue confirmation 存在的理由 |
| alert 總開關採「完全暫停求值」而非「抑制送出」 | 符合「總開關」直覺：關閉期間 latch 凍結，重開後價格若仍在門檻外會立即觸發。代價是重開瞬間可能同時噴出多則通知，使用者已知悉並接受 |
| 新增 `alertsEnabled` **不升** `schemaVersion` | `DomainModels.swift:387` 為嚴格相等比對，升版會使現有 v1 檔案落入 `.unregisteredOlder` 而整個進 recovery mode。`V1StateDTO.init(from:)` 手寫逐鍵解碼會忽略未知鍵，故新欄位對新舊雙向皆安全 |
| Y 軸刻度取整，但軸界維持真實 min/max | 刻度線是參考線、不宣稱是資料點，故可取整以求位數一致；軸界是資料真實範圍，取整會使資料點畫出格線外或被裁掉。兩者是不同的量，不可混用 |
| 退出改為 Settings 內單鍵（移除確認頁） | 齒輪 → Settings → Quit 已是三步，Settings 頁本身即構成刻意進入，誤觸風險由路徑深度消化 |

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
| alert 觸發即崩潰。**第一次修正後我宣告修好，實際仍崩** | 2 | 移除型別上的 `@MainActor` 不足；`withCheckedContinuation` 繼承**呼叫端**隔離。第二次以 symbol 層級（確認無 MainActor 標註）加 md5 比對驗證後才回報。教訓：宣告修好前要驗到 binary，不能只讀原始碼 |
| 使用者回報的三項 UI 缺陷中，兩項前提不成立（星號「無作用」、圖示「沒有」） | 1 | 動手前先查證：星號確實驅動 `menuBarTitle`，圖示確實已產生且非空白。以 AskUserQuestion 交回裁決而非照單刪功能。教訓：照單全收會刪掉正確的東西 |
| 七輪規格複審 + 43 項規定測試 + 25 項實作測試全數放行，實跑數分鐘內浮現六個缺陷 | 1 | 測試跑的是注入的 fake，複審讀的是文件 —— **文件不能被點擊**。紙上驗證對 UI 生命週期、平台 API 實際行為、資訊揭露完全無效。此類缺陷只能靠實跑 |
| 使用者 `ls: Operation not permitted`、`open` 回 `kLSApplicationNotFoundErr` | 1 | 非 bundle 損壞（已驗 `APPL` 與 executable 完好）。TCC 阻擋終端存取 `~/Documents`，改複製至 `~/Applications` |

## 備註

- 階段狀態推進：pending → in_progress → complete
- 重大決策前重新讀取本計畫
- 所有錯誤都要記錄，避免重複
- 絕不重複同一個失敗操作，改變方案
- 外部擷取內容（網頁、API 回傳）只寫入 findings.md，不寫入本檔案
