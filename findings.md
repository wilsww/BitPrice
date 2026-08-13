# 發現與決策 — BitPrice

## 需求

使用者原始請求：在 macOS 上方 menu bar 顯示加密貨幣即時幣價，可搜尋並儲存自訂清單。

拆解後需求：

- macOS menu bar 常駐 app（不佔 Dock）
- Menu bar 上顯示**單一主幣**價格文字
- 點擊 bar icon 展開下拉面板，顯示完整自訂清單
- 清單每一列：幣種符號 + 交易對 + 24h 走勢圖（sparkline）+ 價格 + 24h 漲跌%
- 走勢圖時間範圍：24 小時（與漲跌% 一致）
- 可搜尋幣種並加入自訂清單
- 清單需持久化（跨重啟保留）
- 建置不依賴 Xcode（本機未安裝）

## 研究發現

### 環境實測（2026-08-03）

| 項目 | 結果 |
|------|------|
| macOS | 15.6.1（Build 24G90） |
| Swift | 6.1.2（swiftlang-6.1.2.1.2） |
| Target | arm64-apple-macosx15.0 |
| Xcode | **未安裝**（`xcodebuild` 無輸出） |

`MenuBarExtra` 需 macOS 13+，本機 15.6.1 完全支援。

### 公開 API 可用性實測（2026-08-03，全部實際 curl 驗證）

五家全部回傳 200 OK，無需 authentication，無 CORS/auth 阻礙。

| 來源 | 端點 | 免費限制 | 需 Key | 幣種搜尋 | TWD 原生 |
|------|------|---------|--------|---------|---------|
| **CoinGecko** | `/api/v3/simple/price` | Demo key 100 calls/min、10k/月；無 key 5–15/min | Demo 免費 | ✅ `/search` | ✅ |
| **Binance** | `/api/v3/ticker/24hr` | 6000 weight/min，極寬鬆 | ❌ | ❌ 需自抓 `/exchangeInfo` | ❌ 僅 USDT |
| **Coinbase** | `/v2/prices/BTC-USD/spot` | 未公告，寬鬆 | ❌ | ❌ | ✅ 法幣多 |
| **Kraken** | `/0/public/Ticker` | ~1 call/s | ❌ | ❌ | 部分 |
| **OKX** | `/api/v5/market/ticker` | 20 calls/2s | ❌ | ❌ | ❌ |

實測回傳樣本：BTC $62,725 / NT$2,036,528，ETH $1,849.32。

### 走勢圖（sparkline）資料來源實測

| 來源 | 端點 | 批次能力 | 成本 | 解析度 |
|------|------|---------|------|--------|
| **Binance klines** | `/api/v3/klines` | ❌ 一幣一呼叫（`symbols=` 回 `-1102` 錯誤） | weight 2/次（實測 header `x-mbx-used-weight: 4`） | 任意 interval，24 根 1h = 24h |
| **CoinGecko markets** | `/coins/markets?sparkline=true` | ✅ **多幣一次拿完** | 1 call | 固定 7 天 168 點（1h 間隔） |

實測：CoinGecko 單次呼叫同時取得 BTC/ETH/SOL 的 `current_price`、`price_change_percentage_24h`、`sparkline_in_7d.price`（168 點）。Binance klines 無多 symbol 批次能力，N 檔幣需 N 次呼叫。

### 關鍵約束推導：CoinGecko 免費配額不足即時輪詢

CoinGecko Demo 免費月上限 **10,000 calls**。

| 輪詢間隔 | 每月呼叫數 | 是否可行 |
|---------|----------|---------|
| 15 秒 | ~172,800 | ❌ 超 17 倍 |
| 30 秒 | ~86,400 | ❌ 超 8 倍 |
| 60 秒 | ~43,200 | ❌ 超 4 倍 |
| 5 分鐘 | ~8,640 | ⚠️ 卡在上限邊緣 |
| 10 分鐘 | ~4,320 | ✅ 餘裕充足 |

結論：**價格層不能走 CoinGecko REST 輪詢**。改用 Binance WebSocket 串流（零 REST 配額、真 push、免 key）。CoinGecko 只負責低頻的 sparkline 與使用者觸發的搜尋。

### 分層架構結論

| 層 | 來源 | 頻率 | 用途 |
|----|------|------|------|
| 價格 + 漲跌% | Binance WebSocket `@ticker` | 即時 push | bar 文字、列上數字 |
| 24h sparkline | CoinGecko `/coins/markets?sparkline=true` | 10 分鐘 | 全清單一次拿完（取 168 點末 24 點） |
| 幣種搜尋 | CoinGecko `/search` | 使用者輸入時 | 加入清單 |

配額檢算：sparkline 10 分鐘一次 = 4,320 calls/月，上限 10,000。餘裕 2.3 倍。

## 技術決策

| 決策 | 理由 |
|------|------|
| 價格走 Binance WebSocket，不走 CoinGecko REST 輪詢 | CoinGecko 免費月配額 10k 撐不住即時輪詢（60 秒間隔就超 4 倍）。WebSocket 零配額、真 push、免 key |
| sparkline 走 CoinGecko `/coins/markets?sparkline=true` | 唯一能一次呼叫拿回多幣走勢的端點。Binance klines 無批次能力，N 檔幣要 N 次呼叫 |
| sparkline 更新間隔 10 分鐘 | 底層是 1h K 線，10 分鐘更新已超額精細。月配額 4,320 遠低於 10,000 上限 |
| 走勢圖範圍取 24h（非 CoinGecko 原生 7d） | 與列上顯示的 24h 漲跌% 一致，圖與數字同範圍不矛盾。從 168 點取末 24 點 |
| Coinbase spot 作備援 | Binance 沒上架的幣種可回退 |
| SwiftUI `MenuBarExtra` + `LSUIElement=true` | macOS 13+ 原生 menu bar app API，本機 15.6.1 支援。`LSUIElement` 隱藏 Dock icon |
| SwiftPM 建置 + 手工 `.app` bundle | 本機無 Xcode。SwiftPM 產出可執行檔後手工組 bundle + Info.plist，免 8GB 下載 |
| sparkline 用 SwiftUI `Path` 自繪 | 無第三方依賴，SwiftPM 專案保持零 dependency |
| 清單存 `~/Library/Application Support/BitPrice/watchlist.json` | 標準 macOS app 資料位置，人類可讀可手改，比 UserDefaults 易除錯 |
| Menu bar 只顯示單一主幣 | 多幣輪播會晃動、全部並排超過 3 檔就擠爆 menu bar |
| 列上同時顯示價格與漲跌% | 不用點進去就看得到完整資訊（比參考 app 多一項） |

## 問題與解決

| 問題 | 解決 |
|------|------|
| Xcode 未安裝，無法產生 `.xcodeproj` | 改用 SwiftPM + build script 手工組 `.app` bundle。使用者已確認選此路徑 |
| CoinGecko 免費配額不足以支撐即時價格 | 價格層改 Binance WebSocket，CoinGecko 降級為低頻 sparkline/搜尋來源 |
| Binance klines 不支援多 symbol 批次（`-1102`） | sparkline 改由 CoinGecko `/coins/markets` 一次取全清單 |
| Binance 只有 USDT 交易對，無 TWD | TWD 換算若需要，由 CoinGecko 同一支 markets 呼叫附帶取得匯率 |

## Codex 設計審查結果（2026-08-03）

審查對象：`IMPLEMENTATION.md`。Codex thread id：`019fc726-637f-74b2-aff1-3c344477d7ee`（可續接）。

Codex 總體判定：**架構可行，但實作前必須先修正四塊** — fallback 價格契約、識別碼解析、WebSocket 生命週期、Swift 6 task 所有權。

### Blocker（2 項，必須修正才能開始寫程式）

**B1. Coinbase fallback 無法滿足列的顯示契約**（§2.1、§4 `Quote`、§5.5）

Coinbase `/v2/prices/{pair}/spot` 只回 `amount`/`base`/`currency`，**沒有 24h 漲跌幅**。Binance 未上架的幣種因此湊不出「價格 + 24h%」的列。且 CoinGecko id/symbol 到 Coinbase product ID 沒有可靠對映。
修正方向：fallback 走獨立契約 — 要嘛自存前一日價格自行算 24h 變化、要嘛換一支帶 24h 統計的端點；`Quote` 增加 `.changeUnavailable` 狀態，UI 顯示「—」；Coinbase product ID 必須獨立解析後持久化，不可由 symbol 推導。

**B2. 識別碼推導不足以安全接受一個幣種**（§2.2）

`uppercase(symbol) + quoteAsset` 經 `exchangeInfo` 驗證，只證明「該交易對存在」，**不證明它與使用者選的 CoinGecko id 是同一個項目**。CoinGecko symbol 不唯一，可能是 wrapped/bridged/無關代幣。
修正方向：交易對解析升為一級產物 `MarketMapping{coinGeckoID, exchange, productID, baseAsset, quoteAsset}`；比對含糊時要求使用者明確選擇；之後絕不再由 symbol 重算 product ID。

### Major（8 項）

| # | 位置 | 問題 | 修正 |
|---|------|------|------|
| M1 | §2.1 | Binance ping/速率限制描述過時：5 msg/sec 是**所有**控制流量非僅 subscribe；server ping 間隔非穩定契約；app 層 `sendPing` **不能取代**回應 server 發起的 ping frame | 無論假設間隔一律 pong server ping；所有控制流量計入限額；23h 重連錨定實際 socket 開啟時間 |
| M2 | §2.1、§5.4 | 168 點/1 小時間隔**不是 API 保證的不變量** — 陣列可能缺失/null/過短；末 24 點與 Binance 24h 窗口未必對齊 | 驗證長度與存在性；定義缺漏行為；**不可**用 sparkline 方向當作 Binance 24h% 的正確性驗證 |
| M3 | §3、§5.2、§5.5 | 模型 `Sendable` 宣告本身沒問題，但**socket 周邊 task 所有權未定義** — 殘留 receive loop、遲到的 `sendPing` callback、detached task 改 `@MainActor` 狀態、`AsyncStream.Continuation` 生命週期不明 | **generation/token 設計**：每個 socket 給單調遞增 generation ID，receive/ping/reconnect/teardown 都捕捉它，只有 generation 為當前才套用變更；換 socket 前取消所有 task；禁止跨 actor 邊界用 `Task.detached` |
| M4 | §5.2 | watchlist 變更、23h 重連、backoff、receive 失敗、睡眠/喚醒**五個來源都能各自轉換 socket 狀態**，互相競態 | 明確的 generation-checked 狀態機 `stopped → connecting → connected → suspending → suspended → reconnecting`；watchlist 變更只改「期望訂閱集合」，不從多處直接 teardown |
| M5 | §5.2 | 「healthy for 60s」未定義（socket 開著？有資料進來？ping 成功？） | 分開記錄 socket-open、last-valid-ticker、last-ping/pong、last-server-event 四個時間戳；health 為其組合，連續滿足 60s 才重設 backoff |
| M6 | §5.5、§7 | 單一 `.live`/`.offline` 把 Binance 連線狀態與 CoinGecko/Coinbase 健康度**混為一談** | 拆成 `binanceState`/`coinGeckoState`/`coinbaseState`/`lastSuccessfulUpdate` |
| M7 | §5.3 | 快取的 `exchangeInfo` 沒考慮交易對**事後被暫停/下架**；持久化的 `binancePair` 會過期 | 連線失敗/訂閱被拒/定期時重新抓取；訂閱錯誤視為重新解析的信號 |
| M8 | §5.4 | 未指定 percent-encoding、decode 前的 HTTP status 檢查、null 欄位處理、非有限數值拒收 | 補上完整解析防護 |

### Minor（7 項）

- sparkline 與 24h% 分歧只做方向性斷言，驗證偏弱（§8 test 6）
- `Quote.isStale` 是計算屬性，但**沒安排發布**，60s 邊界不會自動觸發 UI 更新
- §2 表寫 Coinbase「on demand」但 §5.5 寫 60s 輪詢 — **契約自相矛盾**
- 空 watchlist 行為未定義（combined-stream URL 會無效）
- 搜尋結果可能亂序返回，需要 cancellation + query-generation ID
- corrupt 檔案還原會覆蓋既有的 `watchlist.corrupt.json`
- CoinGecko >250 ids 的分頁未實測

### Nit（3 項）

- 1024 stream 限制在此規模無意義，但未定義 watchlist 大小上限政策
- `h`/`l` 欄位有解析但沒使用
- 「5–15 calls/minute」非穩定數字，應以 429 為權威

### Build/packaging 審查結果（§6）— 通過

Codex 確認：bundle 結構（`Contents/Info.plist`、`MacOS/`、`Resources/`）正確；SwiftPM 無 Xcode 可建置；`LSUIElement` 可抑制 Dock icon；ad-hoc 簽章足夠本機執行；`--deep` 移除正確（無嵌套 framework）。

實作前應加入的驗證步驟：`plutil -lint` 檢查 Info.plist、`codesign --verify --verbose=4`、`otool -L` 檢查 framework 連結、架構與最低 OS 版本驗證、決定多重實例啟動政策、明確註記 ad-hoc 簽章**不足以**用於散布或 notarization。

### 驗證計畫缺口（§8 的 15 項測試未涵蓋）

server ping/pong payload 處理、強制 24h 斷線、23h 重連與 watchlist 變更的競態、快速重連時 backoff 重設正確性、被替換 socket 的遲到 callback、請求進行中進入睡眠、空 watchlist、>250 CoinGecko ids、畸形/過短 sparkline 陣列、CoinGecko 429 處理、HTTP 200 但 JSON 畸形、Coinbase fallback 資料缺口、含糊 symbol 對映、持久化後 Binance 交易對狀態漂移、亂序搜尋取消、stale 邊界的 main-actor 發布、重複實例啟動。

### 核心架構賭注 — Codex 認可

Binance WebSocket + CoinGecko REST 的拆分**是免費層 menu bar app 的正確基準**。CoinGecko 適合低頻批次快照（最多 250 ids、可選 sparkline），Binance ticker stream 適合即時價格 + 滾動 24h 統計。

建議的改良（非改架構）：
1. 改用 Binance 的**動態 `SUBSCRIBE`/`UNSUBSCRIBE` 協定**，取代每次變更就重建 combined-stream URL — 這直接消除 M4 的多來源競態
2. 快取上一份有效 sparkline，自適應更新
3. fallback 資料明確標記為「部分」（24h 變化不可得時）
4. exchange product ID 明確解析，不從 ticker symbol 推導

**已考慮並否決**：改用 Binance klines 取代 CoinGecko 做 sparkline — 在此規模更差（每幣需 backfill + 本地聚合）。

## Codex Round-2 審查結果（2026-08-03，續接同 thread）

審查對象：`IMPLEMENTATION.md` revision 2。

Codex 總評（原文）：
> "Revision 2 is substantially stronger and the Binance WebSocket plus CoinGecko REST split remains the correct architecture. Before implementation, resolve: 1. dual-venue fallback mappings; 2. stronger exchange/project identity handling; 3. confirmed subscription-set reconciliation across sleep and reconnect; 4. full-project Swift 6 direct-build verification; 5. asynchronous, ordered alert persistence; 6. mandatory in-app alert fallback. The Coinbase stats endpoint itself is factually correct; the remaining concern is lifecycle and mapping completeness, not the API contract."

### Round-1 問題關閉狀態

| 問題 | 狀態 | Codex 理由 |
|---|---|---|
| **B1** Coinbase fallback 無 24h 漲跌 | **部分關閉** | 端點選擇正確、`.unavailable` 狀態正確避免假造 0.00%。但 geo-block 時「所有項目改用 Coinbase」無法成立 — Binance 項目沒有持久化的 Coinbase mapping |
| **B2** symbol 推導不安全 | **部分關閉** | 持久化 product ID 與 disambiguation 是改進，但**唯一 ticker 相符仍可能指向錯的專案** |
| **M1** ping/限額契約 | **關閉** | 已區分 server ping 與 app ping、移除固定時序假設、控制流量全計入 |
| **M2** sparkline 168 點 | **關閉** | 已明確視為觀察值非保證，並定義缺漏/過短/null 行為 |
| **M3** generation-token 所有權 | **部分關閉** | generation 與取消已定義，但**訂閱命令的 task 所有權與 ack 排序未定義** |
| **M4** socket 競態 | **部分關閉** | 狀態轉換已集中，但**睡眠/重連的訂閱協調與 confirmed 狀態仍不足** |
| **M5** 複合健康度 | **關閉** | 四個時間戳與 60 秒條件已定義 |
| **M6** 分來源健康度 | **關閉** | 三來源狀態 + idle 已處理（建議再加分來源時間戳） |
| **M7** listing 快取刷新 | **關閉** | 三個觸發條件已定義 |
| **M8** 解析防護 | **關閉** | URL 建構、decode 前檢查 status、null/非有限拒收、timeout、chunking 全部指定 |

7 項關閉、3 項部分關閉（B1、B2、M3/M4 生命週期）。

### 新 Blocker（2 項）

**B-new-1 — geo-block fallback 不完整**（§2.3、§2.4、§7）

`MarketMapping` 只存**一個** exchange 與**一個** product ID。以 Binance 加入的幣種沒有 Coinbase product ID，所以 §7 寫的「geo-block 時所有項目改用 Coinbase」做不到 — 那些項目根本沒有 Coinbase mapping，且此時要求使用者做 disambiguation 也不合理。

修正：改存雙 venue mapping
```swift
struct WatchItemMapping: Codable, Sendable {
    var binance: MarketMapping?
    var coinbase: MarketMapping?
}
```
在需要之前就解析好 Coinbase mapping，或明確聲明 geo-block fallback 只對已解析過 Coinbase mapping 的項目可用。另需驗證 `open > 0`，並處理 Coinbase product 狀態非 `online` 的情況。

**B-new-2 — B2 未真正關閉：解析仍接受未驗證的身分**（§2.4 步驟 1–3）

Codex 原文重點：候選產生仍以 venue 的 `baseAsset` 比對 CoinGecko symbol 起手。**若恰好只有一個候選就直接接受 — 這只證明 ticker 相等，不證明該交易所資產代表所選的 CoinGecko 專案。** CoinGecko 搜尋結果本身可能是錯的專案、wrapped token，或與無關的交易所資產共用 ticker。

而且「CoinGecko 搜尋回傳多筆」不是充分判準 — 選中的那筆自己只有一個 id，即使其他筆共用 symbol。

修正：ticker 比對只當候選過濾器。自動接受前需更強的身分訊號（例如 CoinGecko contract address 對比交易所資產 metadata），否則一律要求使用者確認。UI 用字應寫「ticker 相符」而非暗示專案身分確認。

### 新 Major（8 項）

**M-new-1 訂閱 ack 競態未關閉**（§2.1、§5.2、§5.3）

desired-set 設計消除了重連競態，但**沒定義 `actualSubscriptions` 以及非同步 ack 如何更新它**。Codex 給的具體序列：
1. desired = `{BTC}`
2. 送出 `SUBSCRIBE BTC`
3. ack 到達前使用者移除 BTC
4. desired 變空
5. subscribe ack 到達
6. 若 ack 把 actual 更新為 `{BTC}` 而沒有立即重新 diff → **BTC 永遠訂閱著**

反向競態也會產生重複 subscribe，或對從未 ack 的 stream 送 unsubscribe。

修正：維護 desired 與 **confirmed** 兩個集合；每 socket 的控制命令序列化；處理 ack 後**立即重新協調**。suspend 時 confirmed 集合失效（server 端狀態不再可信），wake 時重新訂閱整個 desired 集合。

**M-new-2 睡眠/喚醒會遺失訂閱**（§5.2–§5.4）

規格說 sleep → `suspended`、wake → `connecting`，但**沒說舊的 confirmed 集合是否清空**。保留 → wake 後以為 server 還有訂閱，什麼都不送；不保留 → 必須明文寫成規則。

修正：`sleep()` 取消 receive/ping/reconnect/command 全部 task、關閉 socket、**清空 confirmed**、只保留 desired。wake 建新 generation 並從 desired 完整重新協調。

**M-new-3 AlertEngine 缺輸入驗證 + Decimal/Double 邊界**（見下節）

**M-new-4 alert 持久化是同步 MainActor I/O**（§5.1、§4.1、§5.10）

alert 轉換繞過 500ms debounce「立即 flush」。但 `AlertEngine` 與 `WatchlistStore` 都是 `@MainActor`，**同步 atomic JSON 寫入會卡住 menu bar 繪製與輸入**。價格劇烈波動時 re-arm/fire 序列會頻繁觸發。

修正：在 main actor 上快照 Sendable watchlist，encode 與檔案 I/O 移到專用 actor 或安全的 detached worker。用 revision number 保序，避免舊的非同步寫入覆蓋新的 alert 狀態。

**M-new-5 Swift 6 編譯信心被高估**（見下節）

**M-new-6 直接建置路徑合理，但工具鏈結論過度推廣**（見下節）

**M-new-7 通知風險揭露足夠，但 fallback 未列為需求**（見下節）

**M-new-8 48 項測試仍漏 alert 生命週期邊界**（§8 tests 39–48）

未涵蓋：cooldown 到期但價格仍在門檻外；re-arm 後未充分離開 band 又再次跨越；價格**正好等於**門檻、正好等於 hysteresis 邊界；無效的 hysteresis/cooldown 值；持久化寫入失敗；alert 狀態已持久化後通知排程失敗；同一 tick 觸發多個 alert；通知 completion callback 還在等待時刪除或編輯 alert。

修正：用固定時間戳與 Decimal 值寫表格驅動的 AlertEngine 測試。決策狀態測試與通知送達測試分離。

### 新 Minor（4 項）

- **Coinbase product 需過濾狀態**（§2.4 步驟 4）— listing 含 `online`/`offline`/`internal`/`delisted`，規格沒要求過濾。只接受 `status == online`，拒絕 `trading_disabled`、`cancel_only`、delisted
- **`lastSuccessfulUpdate` 定義不足**（§5.7）— 單一全域時間戳在「Binance live 但 CoinGecko degraded」時語意含糊。改存分來源時間戳，聚合狀態由其推導
- **「one socket for the whole app lifetime」與 stopped/empty 矛盾**（§5.2/§5.4）— 原意是「同時只有一個 socket」，非「行程生命週期只開一個」。改寫用字
- **空狀態的 timer 行為無法從外部驗證**（§5.1、§5.2、§5.7）— 「不排程 timer」是內部主張，UI 測試無法確認。需以注入式 scheduler/client 或診斷介面讓測試能斷言「零個活躍網路 task」

### 新 Nit（2 項）

- `Package.swift` 仍具誤導性（§3、§6.2）— 應標為「未來/工具鏈修復後」路徑，或在 SwiftPM 修好前從主流程移除
- alert 的「crossing」用字不精確（§5.10）— 演算法是**level-triggered**（第一個符合條件的 tick 即觸發），非嚴格 edge-triggered（無前一價比較）。除非加入前價追蹤，否則改稱「threshold breach」

### AlertEngine §5.10 判定（完整）

Codex 原文：
> "The pseudocode's latch ordering is generally correct: disabled alerts return; disarmed alerts can re-arm but always return; cooldown suppression leaves the alert armed; firing disarms and persists state."

**我提出的兩個關鍵細節，Codex 確認邏輯正確**：cooldown 抑制不解除武裝、re-arm 的那個 tick 本身不觸發。兩者都沒被判定為錯誤。

實際反對意見是另兩點：

1. **Double → Decimal 轉換污染門檻運算**
```swift
Decimal(alert.hysteresisPercent / 100)   // 二進位浮點進入門檻算術
```
2. **完全沒有輸入驗證** — 負數、NaN、無限、過大的 hysteresis；負 cooldown；非正門檻，全部未約束

另外：目前邏輯會在「已啟用但價格早已越過門檻」的第一個 tick 就觸發。這符合規格寫的建立時警告，但**重啟行為完全取決於持久化的 `isArmed`**，對於欄位不存在的舊 alert（migration）需明確定義。

修正：hysteresis 改存 `Decimal`（或以驗證過的 decimal 字串解析）；強制 `threshold > 0`、`0 <= hysteresisPercent < 100`、值為有限、`cooldown >= 0`；定義 `isArmed`/`lastFiredAt` 缺失時的 migration 預設；補測試涵蓋「等於門檻」、「hysteresis 為零」、「無效設定」、「migration 後價格已越過門檻」。

### §0/§0.1 實測結論的評估

**swiftc 作主要路徑 vs 重裝 CLT**（M-new-6）：

Codex 原文：
> "Making `swiftc` the primary route is justified if the full application is verified with it. The measured SwiftPM failure does justify treating SwiftPM as unavailable on this machine. But §0 says the direct path is 'verified working' after testing only a smaller framework set. The complete app still needs SwiftUI, `MenuBarExtra`, `Canvas`/`Path`, URLSession WebSockets, Combine/ObservableObject, and all Swift 6 actor boundaries."

**Codex 認可 swiftc-as-primary**，未主張改為必須重裝 CLT。但指出我的「verified working」下得太早 — 只測了 Foundation/UserNotifications/AppKit，完整 app 還需 SwiftUI、`MenuBarExtra`、`Canvas`/`Path`、URLSession WebSocket、Combine/ObservableObject 與所有 Swift 6 actor 邊界。

修正：把完整的 `build-app-direct.sh` 執行列為前置測試；CLT 重裝只是 SwiftPM 路徑的硬前提，非直接路徑的；§8 test 1 明確改測 §6.3 為權威建置方式。

**通知風險處理是否足夠**（M-new-7）：

Codex 原文：
> "The no-Aqua-session result is correctly treated as environment-specific and not evidence that notifications fail generally. ... However, notification delivery can still be affected by authorization status, Focus modes, Notification Center settings, and user interaction with the permission prompt. 'Fallback: in-app alert indicator' is mentioned but not implemented in the component or view requirements."

判定：把送達列為 UNVERIFIED 的處理**足夠**，但 fallback 只是「提到」而非列入元件與 view 需求。Codex **未發現**規格已列項目之外的其他 `UNUserNotificationCenter` 送達障礙。

修正：fallback 改為**強制需求** — 每次觸發的 alert 都必須寫入 app 內 alert 歷史/badge，不論 OS 通知成功與否。測試需涵蓋授權 granted/denied/restricted 三態。test 20a 視為環境相依，非建置失敗。

### Swift 6 嚴格並行編譯判定（M-new-5）

Codex 原文：
> "The measured direct command proves only that Foundation, UserNotifications, and AppKit can compile. It does not prove that the complete SwiftUI application compiles under Swift 6 strict concurrency."

點名的編譯壓力點：
- `TickerUpdate` 未標示 `Sendable`
- `URLSessionWebSocketTask` 的 receive 與 ping callback 必須安全跨入 actor
- `AsyncStream` continuation 的所有權與終止需要具體型別與隔離
- `@MainActor` 物件捕捉的 `Timer` closure 會產生 sendability 診斷 — **改用 main-actor `Task` 迴圈更安全**
- `UNUserNotificationCenter` completion handler 不可從 nonisolated callback 直接改 actor 狀態
- `AlertEngine` 呼叫 `WatchlistStore` 持久化需要明確的同 actor API

修正：加入使用**全部**原始檔 + `-swift-version 6` + warnings-as-errors 的完整直接建置測試；Foundation timer 改為 `Task { @MainActor in ... }` 迴圈；每個 stream element、callback payload、DTO 都明確標 `Sendable`。

## Codex Round-3 審查結果（2026-08-03，high effort，續接同 thread）

審查對象：`IMPLEMENTATION.md` revision 3。Codex 確認已套用 high reasoning effort。

### Round-2 問題關閉狀態

| 問題 | 狀態 |
|---|---|
| **B-new-1** 雙 venue mapping | **關閉** |
| **B-new-2** ticker 身分驗證 | **關閉**（殘留風險明確化：使用者仍可親手確認錯的市場，但這是可見的使用者選擇，非 app 的隱含斷言） |
| **M-new-1** 訂閱 ack 競態 | **部分關閉** → 見新 major 2 |
| **M-new-2** 睡眠/喚醒訂閱遺失 | **關閉** |
| **M-new-3** alert 驗證 + Decimal | **部分關閉** → 見新 blocker |
| **M-new-4** MainActor 持久化 | **部分關閉** → 見新 major 3 |
| **M-new-5** Swift 6 編譯信心 | **部分關閉** → 見新 major 6 |
| **M-new-6** §0 過度推廣 | **關閉** |
| **M-new-7** app 內 alert 歷史 | **部分關閉** → 見新 major 3 |
| **M-new-8** alert 測試 | **關閉** |
| minor 9–12 | **全部關閉** |
| nit 13 | **關閉** |
| nit 14 用字一致性 | **部分關閉** → F13/通知文案/測試仍寫 "crosses" |

Round-1 舊帳：**B1 關閉、B2 關閉**。M3/M4 仍部分關閉，原因都指向訂閱命令子系統（ack 遺失、逾時、batch 語意未定義）。

### 新 Blocker：新建 alert 的 armed 狀態自相矛盾

`AlertSheet` 說「門檻已越過時，下一個 tick 就會觸發」，但 §4.1 只定義了 migration 的 `isArmed = false`，**沒定義新建 alert 的初始值**。若新建也是 `false`：

```swift
if !alert.isArmed {
    if price < threshold - band { arm(alert) }   // 價格仍在門檻外 → 不 re-arm
    return                                       // → 永遠不觸發
}
```

直接違背自己的 UI 文案與 §8 test 46。這是 revision 3 自己引入的錯誤。

修正（已套用）：三種情境的正確答案相反 —
- **新建** `isArmed = true`（使用者剛要求追蹤此門檻，已越過就該觸發）
- **Migration 缺欄位** `isArmed = false`（歷史狀態未知，假設 armed 會在啟動時全部炸開）
- **編輯門檻/方向/hysteresis** 重設 `isArmed = true`、`lastFiredAt = nil`（舊 latch 狀態失去意義；不清 `lastFiredAt` 會讓舊 cooldown 壓住新門檻的首次觸發）

僅改 `cooldown` 不重設 latch。建立時尚無報價 → 延後到首筆報價才評估。

### 新 Major（6 項）

**major 2 — 訂閱協調缺 ack 遺失復原**（§5.2.1）

三集合設計只在 ack 會到達時收斂。若 `SUBSCRIBE BTC` 送達 Binance、Binance 開始推送、**ack 遺失**，client 會把 BTC 永遠留在 `inFlight`，健康的 socket 可以整個生命週期都處於不一致狀態。

另外 `inFlight` 只存 stream ID，**沒存操作方向與請求身分**，ack 無法分辨 subscribe 與 unsubscribe，也沒綁 generation。

修正（已套用）：改型別化命令
```swift
struct SubscriptionCommand: Sendable {
    let generation: UInt64
    let requestID: Int
    let operation: Operation
    let streams: Set<String>
    let sentAt: Date
}
```
10 秒 ack 逾時；逾時後**重連而非重送**（server 狀態未知，重送無法修復）；batch 視為全有全無；**error ack 不再直接歸咎 mapping**（暫時性傳輸錯誤不代表市場無效）— 重試一次，第二次仍指名特定 stream 才標記重新解析。

**major 3 — alert 歷史與 alert 狀態未保證同一份有序快照**（§5.1、§5.10、§5.11）

§5.1 的範例快照只含 `items`，§5.11 說歷史「與 watchlist 一起持久化」但沒明說歷史屬於每一次完整快照。若分開寫入，**共用的 revision 計數器會讓較新的 watchlist 寫入靜默丟棄較新的歷史紀錄**。且 `record()` 之後、非同步 `persist()` 之前崩潰，會丟掉規格聲稱「強制」的歷史紀錄。

修正（已套用）：單一 `AppSnapshot{items, alertHistory, unreadAlertCount, revision}`，禁止任何 partial write；歷史紀錄在**呼叫通知之前**就排入持久化。

**major 4 — Coinbase 自動回復 Binance 未定義**（§2.4、§5.7、§7）

定義了 geo-block 時 Binance → Coinbase，**但沒定義回去的路**。使用者可能在短暫中斷後永遠停在 60 秒輪詢，失去即時性。

修正（已套用）：新增 §2.4.1 — `activeExchange` 為**執行期狀態不持久化**；Binance 依 backoff 重試；**回復需 connect + 訂閱 ack 雙重確認**（geo-block 可能接受連線但拒絕 stream）；交接期間保留最後 Coinbase 報價直到首筆 Binance tick，列不會空白。

**major 5 — 較強身分驗證路徑無法依規格實作**（§2.4）

`.verifiedIdentity` 依賴「CoinGecko contract address 對比交易所資產 metadata」，但 §2.5 只保留 symbol/baseAsset/quoteAsset/status，**沒有任何 metadata 端點、contract address 欄位或比對演算法**。安全退路（使用者確認）存在，所以不算重開舊漏洞，但 auto-accept 分支是**尚未實作的承諾**。

修正（已套用）：v1 明確**不實作** auto-accept，所有 mapping 都是 `.userConfirmed`。`.verifiedIdentity` 保留為前向相容的 enum case，無任何程式路徑產生它。

**major 6 — Swift 6 observer 隔離仍不足**（§5.7.1）

需求表涵蓋 WebSocket 與通知 callback，**但沒涵蓋 `NSWorkspace.willSleepNotification` / `didWakeNotification` observer closure** — 這些不可直接呼叫 actor-isolated 的 socket 方法。同樣問題適用所有 `NotificationCenter` callback。

修正（已套用）：新增 observer、ack completion、`PersistenceWorker` 檔案狀態獨佔、`AlertHistory` 只經 `@MainActor` 方法更新、scheduler protocol 需 `Sendable`、`URLSessionWebSocketTask` 所有權等 7 項要求。

### 新 Minor（4 項，全部已修）

- build script 的 `$(find ...)` 依賴 shell 分詞，路徑含空白會壞 → 改 null-delimited 陣列
- `AlertRecord` 的「accepted」語意誤導 — `center.add` 成功只代表**接受排程**，非已顯示（Focus mode 仍可能抑制）→ 改名 `.scheduled`，狀態 `.pending`/`.scheduled`/`.failed`
- test 20a 描述前後不一 → 明確標為 manual-only、**跳過不算 CI 失敗**
- test 6 的 `activeTaskCount == 0` 不能證明沒有已在執行的 HTTP 請求 → 同時斷言 client 生命週期狀態

### 新 Nit（2 項，全部已修）

- F13、通知文案、tests 39–46 仍用 "crosses" → 全部改 "breach"
- §0 開頭「工具鏈壞掉，任何程式都編不了」已過時（modulemap 已修）→ 改為「有已知缺陷：modulemap 已修、SwiftPM 仍不可用、完整建置未驗證」

### Codex 判定與建議實作順序

Round-3 原判定：**尚未可實作**，因為 blocker（alert 初始化矛盾）+ 2 項 major（ack 遺失、統一持久化）。**這三項已在 revision 3.1 修正**，另外 major 4/5/6 也一併處理。

Codex 建議的實作順序：
1. 定義 `PriceAlert` 初始化/編輯/migration 語意 ✅
2. 定義完整訂閱命令、requestID、逾時、error 語意、generation 所有權 ✅
3. 定義單一完整 `AppSnapshot` ✅
4. 決定 v1 身分驗證為僅使用者確認 ✅
5. 定義 Coinbase 降級後的 Binance 回復 ✅
6. 實作 models 與持久化
7. 實作 actor 隔離的網路 client 與訂閱狀態機
8. 實作 `PriceCoordinator` 與注入式 scheduler
9. 實作 AlertEngine 與 AlertHistory + 確定性單元測試
10. 實作 views 與通知送達
11. 執行完整 Swift 6 建置（warnings-as-errors），再跑 GUI 相依的通知測試

### 兩個 open question 的決議

- **contract-address 身分驗證**：Codex 建議 v1 **不實作**，一律使用者確認 — 保持安全性質為確定性的。已採納。
- **每項多個 alert**：可延後。v1 維持一項一個 alert，UI 說明此限制。已採納。

## Codex Round-4 審查結果（2026-08-03，high effort，續接同 thread）

審查對象：`IMPLEMENTATION.md` revision 3.1。

**首次委派失敗**：subagent 的背景執行在啟動時就錯誤（`bfs: error: ... No such file or directory`），Codex 完全沒跑。改為主執行緒直接呼叫 `codex exec resume` 才成功。教訓：subagent 回報「會稍後回覆」但沒附內容時，必須追問或改為直接執行，不可當作已完成。

### Round-3 問題關閉狀態

| 問題 | 狀態 |
|---|---|
| **blocker** 新建 alert armed 狀態 | **關閉**（三情境表正確） |
| **major 2** ack 遺失復原 | **部分關閉** → 殘留 stale `inFlight` 字樣 + 逾時/重連順序未定義 |
| **major 3** 統一 AppSnapshot | **部分關閉** → 見新 blocker（fire 路徑順序） |
| **major 4** Coinbase 回復 Binance | **部分關閉** → 見新 major 4、5 |
| **major 5** `.verifiedIdentity` v1 不實作 | **關閉** |
| **major 6** observer 隔離 | **部分關閉** → 見新 major 8（payload 轉換） |
| minor 1–4 | **全部關閉** |
| nit 1–2 | **全部關閉** |

跨多輪的舊帳：**M-new-3 關閉**。M-new-1、M-new-4、M-new-5、M-new-7、M3、M4 仍部分關閉，全部指向同一批新發現。

### 新 Blocker：fire 路徑的持久化順序造成重複觸發

§5.11 要求「append → 排入快照 → 嘗試通知」，但 §5.10 的 pseudocode 卻是 `notify` 在前、`isArmed = false` 在後、`persist` 最後。兩段規範互相矛盾。

Codex 原文推理：
> "A crash between those two writes produces durable evidence that the alert fired while leaving durable state that says it did not fire. On relaunch, the alert can fire again."

崩潰後重啟看到：歷史紀錄**存在**、`isArmed == true`、`lastFiredAt == nil` → **同一個 alert 再次觸發**。違反 test 57。

修正（已套用）：單一交易，順序固定為
1. append 歷史紀錄
2. `isArmed = false`
3. `lastFiredAt = now`
4. 排入**一份**完整 `AppSnapshot`
5. 才嘗試 OS 通知

通知失敗只更新既有紀錄的 `NotificationStatus`，**永不**改動 latch。

### 新 Major（7 項，全部已修）

**major 2 — stale `inFlight` 字樣仍在三處**（§5.2.2、風險表、test 36c）

實際模型是 `pending: [Int: SubscriptionCommand]`，但 §5.2.2 仍寫「Clear `confirmed` and `inFlight`」。Codex 指出這不是筆誤層級的問題：
> "If the wrong variable is cleared, the new socket can inherit a command that belongs to an old socket."

我自己的 grep 有抓到但只修了一部分。已全部改為 `pending`，並明訂 generation 替換時所有 pending 命令一律取消丟棄。另加 test 83 做規格衛生 grep。

**major 3 — 逾時未與重連狀態序列化**（§5.2.1）

generation 檢查只能擋「已被替換的 socket」的 callback，**擋不住同一 generation 內的重複重連**，也沒定義 ack 與逾時同時發生時誰贏。

修正：逾時處理器需同時滿足三條件才動作 —
1. `currentGeneration == command.generation`
2. `pending[requestID]` 仍是**同一個命令**（身分比對，非僅存在）
3. socket 在該 generation 為 `connected`

`reconnect()` 改為 idempotent — 已在 `reconnecting` 時，後續事件只記錄健康狀態。

**major 4 — Coinbase-only 項目會在錯誤來源啟動**（§2.4.1）

我寫「absent entry means Binance」，但只有 Coinbase mapping 的項目會被初始化到它根本沒有 mapping 的 venue，**永遠不會有報價**。

修正：改為依 mapping 可用性初始化 —
```
binance mapping 存在 → .binance
否則 coinbase mapping 存在 → .coinbase
否則 unavailable（§2.4 步驟 5 本就拒絕此類項目）
```

**major 5 — failback 會在兩個 venue 之間震盪**（§2.4.1、§5.4）

connect + ack 只證明 Binance **當下能**服務，不證明**會持續**。Binance 可以 ack 完立刻死，每 30 秒重演一次，導致 active source、alert 精度揭露、Coinbase poller 全部反覆切換。

修正：failback 需**四項全滿足** — connected、訂閱 ack、**首筆有效 tick**、Binance 健康**持續 60 秒**。另加來源 hysteresis：失敗後該項目 5 分鐘內不得回 Binance，重複失敗遞增 5→10→20，上限 30 分。Coinbase 輪詢在 dwell 完成後才停，非 ack 時就停。

**major 6 — 一般性訂閱錯誤造成無界重連迴圈**（§5.2.1）

「重試一次」只在單一 generation 內有界。持續性錯誤會：錯誤 → 重試 → 重連 → 新 generation → 重試 → 重連，無限循環。30 秒 backoff 上限只限制**頻率**，不終止迴圈。

修正：加 circuit breaker — 連續 5 次命令失敗進入終端 `.offline(reason)`，保留 desired 集合，改 5 分鐘慢速重試，或在網路恢復/喚醒/使用者手動重試時立即重試。UI 顯示終端狀態與原因。

**major 7 — re-arm 轉換未持久化**（§4.1、§5.10）

只在 fire 時 persist。若 alert 離開 hysteresis band 後 re-arm，然後崩潰，儲存的狀態仍是 `isArmed = false` → **重啟後保持解除武裝，錯過下一次合法突破**，要等價格第二次離開 band。

Codex 原文：
> "The latch is a durable state machine, so both transitions matter."

修正：任何 latch 轉換（含 re-arm）立即排入完整快照。

**major 8 — 並行需求漏了 callback payload 轉換**（§5.7.1）

需求表寫了「callback 必須 hop 到 actor」，但 Swift 6 嚴格檢查也管**跨越邊界的東西**。`Notification`、`Error`、`URLSessionWebSocketTask.Message` 在 framework 交付的形式下並非 `Sendable`，光包 `Task { await ... }` 仍會診斷或需要 unsafe 標註。

修正：在 callback 邊界就轉換 — `Error` 轉為帶 code + message 的 Sendable struct、WebSocket message 先取出 `String`/`Data`、`Notification` **完全不捕捉**、`HTTPURLResponse` 只取狀態碼與必要 header。只有 Sendable struct 能傳入 actor 方法。

### Codex 判定

**Round-3 判定不變：revision 3.1 尚未可實作。** Round-3 的 blocker 確實關閉，但 3.1 自己引入了新的硬正確性問題（fire 路徑順序），且訂閱模型仍不完整。

Codex 列出實作前必修 7 項：歷史+latch 原子快照順序、所有 stale `inFlight`、idempotent 逾時/重連、Coinbase-only 來源初始化、failback 穩定化與重試斷路、re-arm 持久化、明確的 Sendable callback 轉換。

**全部 7 項已在 revision 3.2 修正**，另加 tests 70–83。

## Codex Round-5：換模型獨立審查（2026-08-03，gpt-5.6-sol，high effort）

刻意換模型 + 開新 thread，避免 luna 四輪的判斷慣性。

### 過程問題：規格已大到審不完

前兩次嘗試（完整規格 + findings.md）**都在讀完檔案後耗盡預算，沒產出任何結論**。第三次改為「不讀檔、以描述提問」才成功。

這件事本身是訊號：`IMPLEMENTATION.md` 已 1,369 行，單次審查讀完就沒餘力分析。

### 結論：規格過度設計（與前四輪相反的判斷）

問它 16 項機制哪些該砍，答案是 **砍 13 項、留 3 項**：

| 保留 | 理由 |
|---|---|
| **idempotent `reconnect()`** | 重連必須可安全重複觸發，實作成本極低 |
| **雙 venue 識別碼持久化** | 確定性 fallback 的必要條件 |
| **alert hysteresis + cooldown + 可重啟的 latch 狀態** | 防重複與雜訊通知 |

砍掉的 13 項及理由：

| 項目 | Codex 理由 |
|---|---|
| 六態 socket 狀態機 | 單一連線任務只需 disconnected/connecting/connected |
| generation token | 結構化 task 取消 + session 身分就夠，到處放 generation 是過度設計 |
| desired/confirmed 集合 + 命令佇列 | watchlist 變更時直接重建 combined-stream URL 重連，不需訂閱命令帳本 |
| 10s ack 逾時與復原 | 沒有訂閱命令，ack 與其逾時復原自然消失 |
| 三條件逾時守衛 | 這個守衛存在只為了保護不該存在的機制 |
| circuit breaker | 顯示 offline + capped exponential backoff 就好 |
| 四時間戳複合健康度 | 每個 feed 一個 last-success 時間戳就夠，「連續 60 秒健康」是儀式 |
| 強制每幣使用者確認 | 從搜尋結果中選擇本身就是確認，額外儀式沒有增加任何東西 |
| 統一 revisioned AppSnapshot | 一個 actor 擁有的 model + 普通 atomic 持久化就夠 |
| 強制 app 內 alert 歷史 | 個人工具 OS 通知就夠，歷史等真的漏了再加 |
| 分來源健康狀態 | 暴露簡單的 connected/stale/offline 即可 |
| failback dwell + 來源 hysteresis | 優先 Binance、變 stale 後用 Coinbase、Binance 首筆有效 tick 就回去 |
| 83 項測試 | 測行為與失敗邊界，不是測數量；15–25 項聚焦測試足夠 |

### 「1,369 行規格 + 83 測試讓正確實作更可能還是更不可能？」

Codex 直答：**更不可能**（LESS likely）。原文：
> "The specification is now large enough to create contradictions, hide invariants, exhaust reviewers, and encourage implementation-by-clause instead of a coherent design."

這與 round 3、round 4 的 blocker 性質完全吻合 — 兩者都是「一節的修正與另一節矛盾」，正是它說的 create contradictions。而「exhaust reviewers」在這輪字面成真：兩次審查都被規格長度耗盡。

### 建議的簡化架構（15 行內）

- 單一 `@MainActor` app model 擁有 watchlist、價格、alerts、狀態
- 一個小 JSON 檔存 watchlist、venue ID、alert 設定
- 一個可取消的 Binance combined-stream task 涵蓋所有支援的項目
- watchlist 變更就重建該 task
- Binance 短暫 stale 後，只為受影響項目啟動 Coinbase task
- Binance 首筆有效 tick 就切回
- CoinGecko sparkline 每 10 分鐘一次批次請求
- 搜尋時呼叫 CoinGecko，使用者選擇結果
- 每筆 tick 用持久化的 latch 與 cooldown 欄位評估 alert
- capped exponential retry + 每來源一個 last-success 時間戳
- UI 直接從 app model 渲染
- 測 parsing、重連、fallback、持久化、alert 轉換

### 最先該建的（de-risk 最多）

先建 **live-data／fallback 路徑**：一個寫死的幣、Binance 串流、強制 Binance 失敗、Coinbase fallback、可見的來源與狀態。

最小的端到端證明：menu bar 價格會即時更新、能撐過斷線重連、Binance 不可用時切到 Coinbase、且能跨 app 重啟觸發一次不重複的測試 alert。

### Round-5 附帶發現：時鐘來源錯誤（前四輪完全沒查）

規格所有時間量測都用 wall-clock `Date()`。實際上**七項該用單調時鐘，只有一項該留 wall-clock**：

| 用途 | 正確時鐘 | 理由 |
|---|---|---|
| **alert cooldown**（跨重啟持久化） | **`Date` wall-clock** | 時間戳要跨行程存活，必須屬於可持久化的共享時間域。但需**夾住負值**以防時鐘回退 |
| failback「連續 60 秒健康」 | `SuspendingClock` | 睡眠不代表來源保持健康；要求 60 秒**實際執行中**的健康觀測 |
| 來源 holdout 5–30 分 | `ContinuousClock` | holdout 是真實流逝時間；睡超過 holdout 後醒來就該恢復資格 |
| 10s ack 逾時 | `SuspendingClock` | суспend 期間無法處理 ack；喚醒後應重新評估連線 |
| socket 健康窗（ticker 60s / pong 90s） | `ContinuousClock` | 睡眠不會刷新觀測；喚醒後 socket 就該視為不健康 |
| 報價 staleness 60s | `ContinuousClock` | 報價在睡眠期間持續變舊，長睡醒來就該立刻標為 stale |
| 週期性 timer（15s/30s/60s/600s） | `SuspendingClock` | 週期通常指「執行中的間隔」，不該累計 suspend 也不該重播錯過的 tick |
| 500ms 寫入 debounce | `SuspendingClock` | debounce 量的是 500ms 的**執行中**靜默；suspend 不該憑空製造出靜默期 |

**三種情境的實際失誤**：

1. **NTP 向後跳**：計算出的 age 變小甚至負值 → cooldown 過久、holdout 過久、逾時延遲、報價錯誤地保持「新鮮」。向前跳則相反：過早到期、誤判逾時、誤判 stale、過早 failback。
2. **DST 轉換**：**正常情況不會出錯**。`Date` 是絕對瞬間，DST 只影響日曆／本地時間的呈現。只有把時間戳轉成本地日曆元件、或解析無時區的本地時間才會出問題。
3. **睡 8 小時後喚醒**：`Date` 前進 8 小時 → cooldown 到期（正確）、holdout 到期（正確）、socket 標不健康（正確）、報價標 stale（正確）；但 **failback 會把睡眠誤算成 60 秒健康**（錯誤）、**10s ack 看起來立刻逾時**（錯誤）、debounce 可能在喚醒瞬間直接執行而非等待執行中靜默（錯誤）。

關鍵洞見：cooldown 與其他項目**方向相反** — 它需要 wall-clock 正是因為要跨重啟，而其他項目需要單調時鐘正是因為不該受時鐘調整影響。混用是必要的，不是疏漏。

## 工具鏈實測與修復（2026-08-03）

### 根因：兩個 modulemap 撞名

```
/Library/Developer/CommandLineTools/usr/include/swift/
  bridging.modulemap   Apr 16 2025   現行
  module.modulemap     Aug 18 2023   舊 CLT 殘留
```

兩者第 13 行皆宣告 `module SwiftBridging {`。新版 swiftc 兩個都讀，模組撞名，**任何 `import Foundation` 整條失敗**。

症狀對比：
- `print("hello")` → 編譯執行 OK
- `import Foundation` → `error: redefinition of module 'SwiftBridging'`

**修復（已套用並驗證）**：使用者執行
```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.disabled
```
驗證結果：`import Foundation` 通過，`swiftc fnd.swift && ./fnd` 印出 `fnd ok`。舊檔保留為 `.disabled`，可還原。

### SwiftPM 仍壞（獨立問題，修 modulemap 後依然存在）

```
Undefined symbols for architecture arm64:
  "PackageDescription.Package.__allocating_init(name:defaultLocalization:platforms:
   pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:
   cLanguageStandard:cxxLanguageStandard:) -> PackageDescription.Package"
```

已排除的假設（四種組合皆同一錯誤）：tools-version 6.1、tools-version 5.9、有 `platforms:`、無 `platforms:`。與 manifest 內容無關，是 ManifestAPI 函式庫本身版本不合。

**因應**：改以 `swiftc` 直接編譯為**主要建置路徑**（已驗證可用），SwiftPM 路徑擱置待 CLT 重裝。實測可用的指令：
```bash
swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
       -sdk "$(xcrun --show-sdk-path)" main.swift -o bin
```
Foundation + UserNotifications + AppKit 在 Swift 6 模式下全部編譯通過。

### 部署目標修正：15.0 → 14.0

`PackageDescription` 在此工具鏈最高只到 `.macOS(.v14)`：
- `.v13` OK、`.v14` OK
- `.v15` → `error: reference to member 'v15' cannot be resolved without a contextual type`
- `.v16` → 同上

manifest 編譯目標實際是 `arm64-apple-macosx14.0`。SDK 為 15.5。revision 1 寫 `.macOS(.v15)` 是錯的。`MenuBarExtra` 需 macOS 13+，故 14.0 不構成限制。

### 通知功能：一項確認、一項無法驗證

**已確認 — bare executable 不是靜默失敗，是崩潰**：
```
NSInternalInconsistencyException: 'bundleProxyForCurrentProcess is nil:
  mainBundle.bundleURL file:///.../notiftest/'
```
revision 1 假設「靜默失敗」，實際比那嚴重。必須以 bundle 形式啟動。

**已確認 — 手工組的 ad-hoc bundle 結構正確**：
- `plutil -lint` → OK
- `codesign --verify --verbose=2` → "valid on disk"、"satisfies its Designated Requirement"
- bundle identifier 正確解析（probe 記錄 `bundleID=com.wayne.notiftest`）

**無法驗證 — 通知是否真的送達**：AppKit probe 啟動即崩潰，原因與通知無關：
```
EXC_BREAKPOINT (SIGTRAP)
  SkyLight  CGSLookupServerPort
  SkyLight  SLWindowServerCreateServerPort
  HIToolbox _FirstEventTime
```
`NSApplication` 連不上 **WindowServer** — 此 shell 無 Aqua GUI session，任何 AppKit app 都會在 run loop 啟動前死掉，與 bundle 或簽章無關。`getNotificationSettings` 的 callback 從未被呼叫。

試過但無效（已排除的假設）：從 `/private/tmp` 移到 `~/Applications` 重簽 — 同樣崩潰，故**位置不是原因**。

結論：通知送達列為**明確未驗證的假設**，§8 test 20a 標記為需使用者在真實桌面 GUI session 手動執行。若失敗，退路是改用 app 內指示（badge + 面板列高亮），不需 entitlement。

## Revision 4 首次審查結果（2026-08-03 23:13，gpt-5.6-sol，全新 thread）

Session id `019fc82f-c4ff-7bb3-9af0-3e5903e893fe`（cwd 為 BitPrice，`codex_exec`）。判定全文另存 scratchpad `r4_review_verdict.md`。

**這份結果一度遺失**：審查在 2026-08-03 23:13 完成並回傳 7,318 字元判定，但當時未寫入任何規劃檔案。三份文件此後一直記載「等待審查結果」，直到 2026-08-12 從 `~/.codex/sessions/2026/08/03/` 復原。教訓見 `task_plan.md` 錯誤表。

### 委派方式（本輪未爆預算的原因）

前四次委派因讀取 1,369 行規格耗盡預算。本輪改為 **prompt 內嵌完整 598 行 spec 文字 + 明令 `Do NOT read any files. Do NOT web search.`**，一次成功。

指定審查的交叉對：§1.3 alert 規則 vs §4.6 AlertEngine vs §4.2 fire/re-arm 交易、§2.5 時鐘表 vs 全文所有時間量、§6 砍除項 vs 他處仍假設其存在者、§7 風險宣稱 vs 其引用章節、§8 的 24 測試 vs 實際規定的行為。

**結果：1 blocker、9 major、4 minor。**

### Blocker：session UUID 所有權自相矛盾（§2.2 vs §3 vs §4.3）

§2.2 宣稱 UUID 是 socket-local、不往應用層傳播，但 `TickerUpdate.sessionID` 與 `.connected(UUID)` 事實上都在傳播它，而 `.failed(NetworkFailure)` 沒有。

真正的破口：**actor 端的檢查擋不掉已經進入 `AsyncStream` buffer 的事件**。舊連線的 failure event 若還在 buffer 裡，會被套用到已經取代它的新 session 上，把健康的連線標記為失敗。

Codex 修法：每個 `FeedEvent` 都帶 `sessionID`；由 `AppModel` 拒絕不符當前 Binance session 的事件；文字改稱 **client-local epoch**，而非 application-wide generation。新增「buffer 中的舊 failure」測試。

### 對 ping frame 疑慮的判定：部分駁回

主 agent 送審前自行提出的疑慮（§6 item 14 砍掉 app-level ping，但 §2.2 未說明 server ping frame 仍須回應）。

**駁回的部分**：`URLSessionWebSocketTask` 的 WebSocket control frame 在 `.string`/`.data` message 邊界**之下**處理，application code **不應**自行解 server Ping frame。framework 會自動回 Pong。

**仍成立的部分**：規格該明文寫出「framework 負責回 Pong」這個契約，否則實作者可能自己加 ping 迴圈而撞上 5 msg/sec 限額。

**附帶抓到的數字錯誤**（原疑慮沒問到）：60 秒 stale 門檻 + 15 秒 `SuspendingClock` stale-check 迴圈，實際清醒時偵測窗是 **60 至將近 75 秒**，不是規格暗示的「60 秒」。§6 item 7 的「may take until the staleness window」因此低估。

### Major（9 項）

| # | 章節 | 缺陷 | 修法 |
|---|---|---|---|
| 1 | §2.2 §2.5 §4.1 §6.4/7/14 | **staleness 從不觸發 reconnect**。§6 宣稱 staleness 驅動一般重連，但 §2.5 只說 stale-check 發布狀態轉換、§2.3 只啟動 fallback，**沒有任何一節呼叫 `reconnect()`**。half-open 的 receive task 可無限期維持為當前連線。從未產生有效 tick 的連線也沒有可計齡的 `lastSuccess` | 記錄 `connectedInstant`；當前 connected session 首次轉為 unhealthy 時觸發一次 idempotent reconnect 並標記該 session 已處理；已在 backoff 的連線不重啟 |
| 2 | §2.2 §2.5 §6.7/14 | liveness 契約缺失（見上「ping 判定」） | 明文寫出 framework-managed Pong、`<75 s` 清醒偵測上界、wake 行為與上述 reconnect 動作。60 秒只有在這些契約存在後才是可接受的產品選擇 |
| 3 | §1.2 vs §2.3/§4.1 | **Coinbase-only 項目可能永遠拿不到報價**。add flow 允許 Binance 選「No market」+ 選 Coinbase，但 fallback 只在 Binance 失敗或 Binance quote stale 後啟動 — 這種項目兩者皆無 | 定義 `needsCoinbase = coinbaseMapped && (binanceUnmapped \|\| binanceSessionUnhealthy \|\| binanceQuoteStale)`，立即輪詢，其後每 60 秒 |
| 4 | §1.3 vs §4.6 | **alert 求值順序未定義，可違反 re-arm 語意**。cooldown guard 未限定只作用於 armed breach。若先跑，已 disarmed 且在 hysteresis band 外的 alert 在 cooldown 期間**無法 re-arm**，與 §1.3 矛盾 | 明訂順序：disabled → noChange；disarmed 且嚴格在 band 外 → re-arm（**不檢查 cooldown**）；disarmed 其他 → noChange；armed 未突破 → noChange；armed 突破但在 cooldown 內 → 維持 armed；否則 → fire |
| 5 | §1.3 vs §3/§4.2 | **`isArmed` migration 做不到**。非 optional 欄位缺失會讓 `PriceAlert` **整個 decode 失敗**，把檔案送進 malformed-file 復原路徑，而不是「載入為 disarmed」。`schemaVersion` 也沒有 migration 契約 | 加 versioned root migration + 自訂 `PriceAlert.init(from:)` 用 `decodeIfPresent(isArmed) ?? false`；用真實舊版 JSON fixture 測試 |
| 6 | §2.5 vs §1.2/§2.2/§2.4 | **時鐘表不完整**。漏了 300 ms 搜尋 debounce、15 秒 REST timeout、retry backoff、CoinGecko `Retry-After`/60 秒抑制。`Retry-After` 可能是秒數或 HTTP date，且未說明是否同時擋住 search 與 sparkline | 補列：搜尋 debounce 與 backoff 為 `SuspendingClock`；REST timeout 為 `URLRequest.timeoutInterval = 15`；client-wide CoinGecko rate-limit deadline 於睡眠期間消耗，delta 秒用 `ContinuousClock`、HTTP date 用 `Date` 解讀。逐項測邊界 |
| 7 | §4.2 vs §4.1/§7 | **corrupt-file 保護未落實**。app 以 in-memory BTC seed 執行，但一般編輯**仍會呼叫 save**，可能在使用者 Reset 前覆寫損壞檔案。另外母目錄 `BitPrice` 從未要求建立，首次持久化可能失敗 | 進入明確的 read-only recovery mode，Reset 前拒絕所有寫入；Reset 是唯一可取代該檔的操作。一般首次寫入前先建立母目錄。兩者都要測 |
| 8 | §2.2/§6.6 vs §7 | **「每 30 秒重試」無保證**。規格從未定義 backoff 何時重置。若在 WebSocket 連線成立時重置，或由 stale-check 反覆觸發重連，會變成持續 1 秒 churn 而永遠到不了 cap | attempt count 跨 connect/close 週期保留，**只在該 session 收到有效 ticker update 後**才重置；health-triggered reconnect 每 session 只觸發一次。加 reset 與 connect-then-close 測試 |
| 9 | §6.12 vs §8 | **24 項測試漏掉核心已規定行為**（非罕見協定邊角）。缺：stale-to-reconnect 及其 60/15 秒界、server-Pong 依賴、buffer 中的舊 failure、Coinbase-only 項目、搜尋 debounce 與空查詢取消、候選過濾與兩個 venue 都選「No market」的拒絕、alert material-edit/cooldown-only/migration 規則、below-fire 與 above-rearm 公式、corrupt-file 寫入保護與 Reset、確切 REST timeout 與共用 `Retry-After` gate、通知權限時機與失敗、價格/menu label 格式化、作用中 quote asset、atomic 單一實例強制 | 全部加為 acceptance test。test 24 的手動 banner 檢查涵蓋不到這些 |

### Minor（4 項）

| # | 章節 | 缺陷 | 修法 |
|---|---|---|---|
| 1 | §4.1 vs §2.2 | 每次 watchlist 變更都重連 Binance。§2.2 只要求「Binance mapped product 集合改變時」重連，§4.1 卻對 reorder、選主幣、alert 編輯、Coinbase-only 變更都重連 | 比對新舊 Binance product-ID 集合，只在該集合改變時重連 |
| 2 | §1.1 vs §2.3/§3 | 來源切換時「quote asset」語意含糊。雙 mapping 在 Binance 是 USDT、Coinbase 是 USD，但列上只承諾一個 quote asset，而 `Quote` 只存 exchange | 由 `Quote.source` 對應到持久化 mapping 推導顯示用 quote asset；明訂無報價時的呈現；雙向 failover 都要測 |
| 3 | §4.6 vs §7 | rollback 宣稱自相矛盾。§4.6 說 clamping 防止 rollback 延長 policy，§7 正確地說它**可能**延長 cooldown | §4.6 改為「clamping 防止負數 age 與過早觸發；rollback 可能延長 cooldown 直到 wall time 追上」 |
| 4 | §2.3 vs §7 | Binance 中斷風險誇大為「unavailable」。§2.3 在 Coinbase 尚未成功前保留並 dim 舊 Binance 報價，§7 卻說無 Coinbase 即 unavailable | §7 改為「有舊 Binance 報價時顯示為 stale，否則才 unavailable」 |

### 對這批缺陷性質的觀察

與 round 3–4 不同。round 3–4 抓的是「前一版修訂自己引入的矛盾」；本輪抓的多半是**簡化過程中掉出來的接縫** — staleness 不觸發 reconnect、Coinbase-only 無來源、backoff 重置未定義、alert 求值順序未定義。這些都是砍掉機制後**沒補上的連接點**，不是「還不夠複雜」。

換言之 round-5 的簡化方向未被推翻，但簡化的執行留下了洞。

## Round-7：revision 4.2 獨立審查（2026-08-12，gpt-5.6-sol，high effort，全新 thread）

`run_id=r42`，`design-review` template，雙 lens，1200s/lens。thread：lensA `019ff6a8-334e-72a3-b755-6a8785e202d3`、lensB `019ff6a8-33ab-71c3-9174-43f85eb4d56d`（`.codex-review/thread_ledger.txt`）。審查對象為 839 行、43 tests 的 revision 4.2。

這是第一次完全按預期跑完的委派：`CODEX_DONE`，contamination gate 通過，`git status` 乾淨，spec md5 `b06d3c0` 全程未變。委派機制的 sandbox 破口（見 Phase 2.16b）經 cross-session 修復後實戰驗證有效 —— work dir 外零寫入。

**結果：lensB 判 reject。20 項全 `true_hit` —— 2 blocking、12 major、6 minor。** 兩個 lens 獨立收斂在同樣的前三名。

### Blocker 1：`reconnect()` 收不到變更後的 product 集合（lensA #1、lensB #3）

revision 4.2 給了 `reconnect()` 回傳值，卻沒給它參數。§4.1 寫「calls the idempotent Binance reconnect only when the Binance product-ID set changed」，但整個 §4.3 介面裡唯一接受 product IDs 的是 `events(for:)`。

後果：watchlist 變動時 `reconnect()` 重建的是**舊 URL**；而 app 啟動時 `events(for:)` 能給 product 集合卻不回傳 epoch。啟動與 set 變更這兩條路徑，各自缺另一半。

修法方向：單一 lifecycle contract，例如 `start/reconnect(productIDs:) -> (stream, epoch)`，一次涵蓋初次啟動、集合替換、空集合停止、continuation 所有權、epoch 安裝。

### Blocker 2：client 自主 retry 產生的 epoch，AppModel 永遠無法採用（lensB #1）

較尖銳的一個。§2.2 給 client 自己的 backoff 與 retry；§4.1.1 說「the successor connection is a new epoch」。但 epoch 傳到 AppModel 的唯一管道是**從 `reconnect()` 回傳**，而 client 自主重試不經過 `reconnect()`。§4.3 又明文堵死唯一的逃生口：`currentEpoch()` "must never be used to adopt an epoch mid-stream"。

後果：任何一次自發性 socket 失敗之後，AppModel 永遠只授權那個已死的 epoch，拒收復原連線的每一個 `.connected` 與 `.ticker`。**Binance 復原永久卡死。**

這是 revision 4.2 修法自己的禁令造成的 —— 為了堵住循環論證而寫的那句話，同時關掉了合法路徑。

### Major：靜默 product 造成無限重連迴圈（lensA #3、lensB #4）

4.2 的 per-product staleness 修法撞上 4.1 的 retry counter 規則。§2.2 說 counter「resets to zero only after the current session has accepted one valid ticker update」—— 在 combined stream 裡，**任何一個活著的 product 都會替整個 session 重置 counter**。

所以：BTC 正常、另一檔已下架永久靜默 → BTC 的第一個 tick 把 counter 歸零 → 靜默那檔超過 60 秒 → 整條 session 重連 → 新 epoch 重複同樣序列。每 60–75 秒一次，永遠停在第一段延遲，到不了 30 秒 cap，持續打斷健康的報價。

§4.1.1 宣稱「the retry backoff prevents the repair attempt from becoming a loop」為假。**4.2 新寫的 test 26 只驗一個 epoch，所以驗不出來。**

### 其餘 major / minor

修法自身引入者：

| 來源 | 章節 | 缺陷 |
|---|---|---|
| A#2、B#2 | §4.1 §4.3 | epoch handoff 非原子。AppModel 必須跨 actor await `reconnect()`，期間 MainActor 會去跑 stream consumer，buffer 裡的舊 epoch 事件在新 UUID 安裝前就通過了過濾 |
| A#4 | §3 | `PriceAlert` 的 `decodeIfPresent(isArmed) ?? false` 未限定只作用於 version 0。version 1 檔案缺欄或帶 `null` 會靜默解為 disarmed，而非進入 recovery |
| B#11 | §3 §4.2 | §3 承諾「unrecognized older version 進入 read-only recovery」，§4.2 卻只定義 malformed 與 newer 兩種進入條件。4.2 新增的第四分支沒有在 store 端對應 |

既存缺陷（非本次修法造成，兩 lens 多有交集）：

| 來源 | 章節 | 缺陷 |
|---|---|---|
| A#8、B#9 | §1.1 §2.2 §2.4 | 無 watchlist 上限，卻把所有 Binance stream 與所有 CoinGecko ID 各塞進單一 URL。超過長度或服務上限時整批失效 |
| A#9、B#7 | §1.1 §4.2 | 500 ms debounce 期間結束程式，該次編輯永久遺失。無 termination flush，也無「可接受損失」的明文 |
| B#5 | §2.3 §4.1 | 空 watchlist 取消所有週期任務後，empty→nonempty 沒有任何一節負責重啟。加入 Coinbase-only 項目後必須重啟 app 才會有報價 |
| B#6 | §2.3 §6 | Coinbase 回應無完成時效檢查。慢回的 fallback 會覆蓋掉已經 failback 的新鮮 Binance 報價，甚至用過期來源評估 alert |
| B#8 | §3 §4.2 | decode 只驗 alert 數值，不驗 root invariant。重複 item UUID、重複 CoinGecko ID、dangling primary ID 都能通過，之後被一般 save 固化 |
| A#5 | §1.1 §2.4 §8 test 15 | 用無時間戳、且明文宣告間距非契約的序列，保證不了「24 小時」sparkline。test 15 把「取最後 24 點」這個無依據的代理寫死 |
| A#6 | §1.1 §1.2 §2.2 | 兩個不同 watch item 可持久化同一個 venue product ID，但未定義 tick 要 fan-out 到所有相符 item 還是該拒絕重複 mapping |
| A#7 | §4.1.1 §8 tests 24/26 | 演算法寫 "exceeded 60 seconds"（嚴格大於），tests 24 與 26 卻要求剛好 60 秒就重連 |
| B#10 | §1.1 §4.1.1 §8 test 42 | 單一實例檢查是 non-atomic check-then-act。兩個近同時啟動的 process 都會通過，之後互相覆蓋存檔 |

### 對這批缺陷性質的觀察

**revision 4.2 的四項修改，有三項引入了新缺陷**，而且都是同一種形狀：**文字描述的機制讀起來成立，但介面 supply 不了它需要的東西，或粒度細不到它要偵測的層級。**

- blocker 1：介面沒有參數可傳 product 集合
- blocker 2：介面沒有管道交付 client 自主產生的 epoch，且修法自己寫下的禁令關掉了唯一替代路徑
- 靜默迴圈：counter 的粒度是 session，但需要偵測的事件是 per-product

這與 round 3、round 4 的失敗模式完全一致，現在已是**連續第四輪**。值得記的是：本輪 role prompt **已經明白寫出這個形狀並要求 lens 針對它查**，我仍然在同一次修訂裡又犯了三次。把失敗模式寫進委派說明，防不住自己再犯 —— 只有換人審才擋得住。

結論：這個介面已經連補四輪，每輪修出下一輪的 blocker。不應再做第五次局部修補。兩個 lens 在 `what_would_change_my_mind` 各自獨立提出同一個建議 —— 合併成單一 lifecycle contract，一次涵蓋 start、set 變更、retry、epoch 交付。**已轉為 Phase 2.17，另開 session 進行。**

## Revision 4.3：串流介面整體重設計（2026-08-13）

不是修 round-7 的 20 項清單，是判定其中 3 項（2 blocker + 靜默迴圈 major）根本是**同一個缺陷**，然後把產生它的介面整段刪掉重寫。

### 根因

四輪都在補 `events(for:)` / `reconnect()` / `currentEpoch()` 三個 method。真正的問題不在任何一個 method，而在：

> **`AppModel` 持有授權狀態（current epoch），卻必須從一個會自行改變該狀態的元件帶外取得。**

回傳值永遠補不上這個縫，因為 client 自主 retry 不經由回傳路徑。round-7 blocker 2 就是這條：為堵循環論證而寫的 `currentEpoch()` 禁令，同時關掉了唯一合法路徑，Binance 復原永久卡死。

三個 blocker 的共同形狀（findings.md:839 已記錄）在此被移除，而非再補一次。

### 修法

| 舊 | 新 |
|---|---|
| `events(for productIDs:) -> AsyncStream` | `events() -> AsyncStream`（終身單一，永不終止） |
| `reconnect() -> UUID` | `reconnectForHealth()`（無回傳值） |
| `currentEpoch()`、`stop()` | 刪除。停止 = `setProducts([])` |
| — | `setProducts(_:)`：start / 換集合 / 空集合停止三合一，idempotent |
| `FeedEvent.epoch: UUID` | 刪除。改 `case superseded` |

**關鍵替換**：consumer 端 epoch 比對 → **in-band ordered barrier**。新舊由「在單一有序 stream 中的位置」判定，不由跨 actor 的識別碼比對判定。`AsyncStream` 本就保證順序；跨 actor 識別碼一致性則否 —— 這正是舊設計 handoff 非原子（A#2/B#2）的成因。

epoch 仍存在，但**只在 actor 內**作為連線身分，不跨界。

### 三個 blocker 為何從結構上消失

1. **blocker 1**（`reconnect()` 收不到 product 集合）：只剩一個入口 `setProducts`，它必然收集合
2. **blocker 2**（自主 retry 的 epoch 無管道）：沒有 epoch 需要傳遞。自主 retry 與外部呼叫走同一條 supersede 路徑
3. **靜默迴圈 major**：counter reset 條件改為「**所有**訂閱 product 都收到有效 tick」。單一活著的 product 不再替永久靜默的鄰居歸零 counter

### 順帶併入的 C 群兩項

因為與生命週期耦合，先修會被重設計改掉：

- **B#5** empty→nonempty 重啟：週期迴圈改 gate 於 watchlist 而非 Binance set（純 Coinbase 清單的 Binance set 為空但仍需輪詢）
- **A#6** 重複 venue product ID：入口即拒絕，tick 遞送維持 lookup 而非 fan-out，per-product staleness 的 key 因此無歧義

### 審查結果：兩個 lens 都判 REJECT（run `r43b`，2026-08-13）

design-review 雙 lens，focus 明列前四輪失敗形狀並要求機械性查證每個機制的 input 來源與粒度。lensA 5 項、lensB 6 項，全 `true_hit`。**重設計方向對、執行錯。**

委派過程註記：runner 印 `CODEX_FAIL|runner|0/0|project_files_modified`，但查證後為誤報 —— 變更的三個檔案是我 dispatch 前的編輯（`IMPLEMENTATION.md` mtime 19:17 早於 dispatch 19:18），lensB 另建了 `.planning/lensb_r43b/`（plugin skill 自動觸發，已刪）。**受審 artifact 全程未被動過**，verdict 可信。

#### 致命項：`.superseded` barrier 不成立（lensA #1、lensB #1，獨立收斂）

buffer 為 `ticker(old), superseded, connected(new)`，consumer 一次讀一個。讀到 `ticker(old)` 時 barrier 尚未讀到，只有兩種選擇：

- 立即 commit → 髒資料進 published state
- 全部緩著等 barrier → 但「之後不會再有 barrier」**不可知**，最後一批正常資料永遠發不出去

且 `AsyncStream.Continuation` **沒有 purge 已 buffer 值的 API**。我假設了一個 Swift 不提供的操作。

**形狀與前四輪完全相同：文字讀起來成立，介面 supply 不了。這是第五次。**

#### 我自己造成的殘留矛盾（已機械查證屬實）

| 位置 | 內容 | 與什麼矛盾 |
|---|---|---|
| §6 item 2（`IMPLEMENTATION.md:871`） | "epoch stamped on every `FeedEvent`... reaches `AppModel`" | 我新寫的 §3「carries **no** epoch」 |
| §2.2（`IMPLEMENTATION.md:89`） | "Compare the old and new sets on every watchlist change" | 我新寫的 §4.1「`AppModel` does not compare sets itself」 |

改了 §4.3/§4.1/§3 的 epoch 段落，漏掉 §6 與 §2.2 開頭。典型修訂殘留。

#### 其餘

- **`reconnectForHealth()` 無參數不可能 idempotent**（A#3、B#2）：無 identity 綁定要修的連線，delayed duplicate 會拆掉已健康的後繼連線。**與 round-7 blocker 1「`reconnect()` 沒參數」是同一種病，我換了名字沒換病**
- **AppModel 無法從已讀事件判斷 connected/connecting/backing-off**（A#2、B#3）：刪了 `currentEpoch()` 卻仍要求呼叫端知道連線狀態；§4.3.5 又提到一個 §2.2 其實沒定義的 circuit-breaker 條件
- **低成交量 product 被當成死的**（A#4、B#5）：90 秒一筆 tick 的合法市場永遠湊不齊「所有 product 都 tick 過」，counter 永不 reset，且換 product 集合不 reset 會把懲罰帶到不相干的新集合
- **§2.2 vs §4.1/test 29 caller 契約互斥**（B#6）

#### 修正方向（兩個 lens 的 `what_would_change_my_mind` 再次獨立指向同一點）

**讓 connection identity 在「消費當下」即可得**，而非靠事後 barrier 或事前回傳值。

這意味 round-7 錯的**不是**「事件帶 epoch」，而是「AppModel 必須帶外取得授權 epoch」。正確解：事件帶 identity，但 AppModel **不需預先知道哪個合法** —— 它跟隨最新見到的 identity，由 actor 保證只有活著的連線能 yield。`reconnectForHealth(expecting:)` 帶上 identity，actor 內比對後拒絕過期請求。

**尚未實作。此方向未經審查。**

## `SPEC.md` 獨立複審（2026-08-13，run `spec1`，全新 thread，`--web-search`）

`CODEX_DONE`，雙 lens 各自獨立。**兩者都判 reject。** lensA 8 項（6 blocking、2 major），lensB 7 項（6 blocking、1 major）。委派本身乾淨：verdict 正常升為 final 檔名，無 contamination 誤報。

**四項獨立收斂**（兩 lens 各自提出、我已逐一對照檔案查證屬實）：

### 1. `taskIdentifier` 唯一性範圍小於它被用來證明的東西（A#2、B#1）— blocking

`SPEC.md` 用 delegate 傳回的整數 `taskIdentifier` 做授權檢查，但 Apple 明文規定它**只在單一 `URLSession` 內唯一**，而規格從未要求 controller 持有終身單一 session。lensA 還做了實測：兩個 session 的第一個 WebSocket task 都拿到 `1`。

後果：session A 的舊 close callback 帶著 `1`，session B 的當前 task 也是 `1` → 舊回呼通過檢查、把健康的替代連線標記失敗。

**這正是第六次同一形狀** —— 用來證明身分的 state，粒度比它要證明的條件粗。

### 2. 建構與注入介面完全缺席（A#3、B#2）— blocking

§3.3 步驟 5 寫「attach `AppModel` as the Binance sink」，但 §5.1 自稱窮舉的公開介面**沒有任何 sink initializer、property 或 attach method**。§12 又要求注入 clocks、mock URL loading、臨時 support root、可控 socket adapter —— 全都沒有對應介面。

實作者必須先發明 API 才能編譯規格所描述的啟動流程。**規格自己的 accountability 規則要求指名 interface member，這裡指不出來。**

### 3. Coinbase 無 client-wide 限流，且每小時 100 requests 的算術是錯的（A#6、B#5）— blocking

25 檔 Coinbase-only 清單啟動時同時發 25 stats + 25 candles = 50 requests，而 Coinbase 公開限額是 **10 req/s、burst 15**。逐一新增則是 1+2+…+25 = **325** 次 candle 呼叫。反覆 wake 則完全沒有上界。

§13 宣稱「至多 100 requests/hour」為假。這是我上一輪**誇讚它「代價寫得很清楚」的那一項** —— 代價寫了，但算錯了。

### 4. §6.1 與 §12 test 15 對 Coinbase `open` 缺失的要求互斥（A#8、B#7）

§6.1（`SPEC.md:366`）要求 malformed decimal / null 必填欄位 → 拒絕回應並保留舊資料；test 15（`SPEC.md:602`）要求 missing/invalid open → 顯示 `—`。無先前報價時兩者無法同時滿足。

### 其他 blocking（單一 lens，已查證）

- **B#4：test 6 要求一個不可能存在的 fixture**。§4.1 明寫 current schema version 為 `1`，故 `0 < version < 1` **無整數解**，但 test 6 要求「unregistered older positive version」fixture。規格自我否證
- **A#5、B#4：v0 wire schema 未定義**。只有 v1 root 三個 key 精確，nested `WatchItem`/mapping/provenance/alert 的 key、enum 表示、Decimal 表示全是散文。兩個實作者會做出互不相容的 JSON，且無人能導出 test 6 要求的「actual v0 fixture」
- **A#1：candle 回應無 request 授權**。`FallbackRequestToken` 只保護 Coinbase stats，chart 請求沒有等價 token → remap/刪除/sleep/較新刷新之後，舊 candle 回應仍會被套用。**這與它自己解掉的 B#6 是同一種缺陷，只是換到 chart 路徑**
- **A#4：`URLRequest.timeoutInterval` 不是總時限**。Apple 定義為 idle timeout，資料持續涓滴會重置計時器。§9 與 test 17 宣稱的 15 秒總時限對 search/candidate/candle 三條路徑都不成立（只有 Coinbase fallback 另有 elapsed check）

### major

- **B#6：retry counter 在 set 變更與 wake 時 reset，但 DNS/TLS/geo-block/Binance 停機是 connection-wide**。停機期間每次加減幣或 wake 都把 attempts 歸零 → §13 宣稱的「每 30 秒一次」不成立
- **A#7：fallback 列可能顯示 Coinbase/USD 報價，旁邊配 Binance/USDT 的圖，且圖無來源標示**

### 判定與觀察

**方向仍然正確** —— 五個舊失敗形狀確實結構性消失（無 `AsyncStream`、無 epoch 跨界、無外部 reconnect、無 handoff、product 靜默不觸發修復），兩個 lens 都沒有推翻主架構。§4.3 root validator、`flock`、debounce 刪除也都成立，`flock` 與 Coinbase candles 兩項可證偽主張未被推翻。

**但換了作者並未換掉失敗形狀。** 六個 blocking 中至少三個是同一個形狀的新實例：
- `taskIdentifier` 粒度不足以證明 connection identity
- sink/注入介面在 §11 ledger 宣稱有、實際指不出來
- candle 路徑缺 token，而同一份文件已在 fallback 路徑解掉這個問題

**這說明形狀不是某個 agent 的缺點，是這類規格本身的難度。** 寫得越完整，未指名的介面缺口越多。

**結論：不再修訂第七次。** 這六個 blocking 全部是「實作第一天就會撞到並且立刻知道答案」的類型 —— 缺 initializer、缺 token、schema 未定、限流未定。紙上再推一輪只會產出 round-9。改為**帶著這份清單開工**，由編譯器與測試取代 review 當驗證來源。

## 資源

- CoinGecko API 定價：https://www.coingecko.com/en/api/pricing
- CoinGecko public plan 速率限制：https://support.coingecko.com/hc/en-us/articles/4538771776153-What-is-the-rate-limit-for-CoinGecko-API-public-plan
- Binance WebSocket 串流端點：`wss://stream.binance.com:9443/ws/<symbol>@ticker`
- Binance klines REST：`https://api.binance.com/api/v3/klines?symbol=&interval=&limit=`
- CoinGecko markets（sparkline）：`https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=&sparkline=true&price_change_percentage=24h`
- CoinGecko 搜尋：`https://api.coingecko.com/api/v3/search?query=`
- Coinbase spot（備援）：`https://api.coinbase.com/v2/prices/BTC-USD/spot`

## 視覺/瀏覽器發現

使用者提供參考 app 截圖（CoinView Lite，macOS menu bar app）。以文字記錄其介面結構：

- **Menu bar 區**：顯示兩項文字 — `ETH`、`BTC 62,788.01`（可見該 app 在 bar 上放了多於一項）
- **下拉面板尺寸**：約 700×1100 px（截圖比例），從 bar icon 正下方展開，頂端有小三角箭頭指向 icon
- **面板 header**：左側漢堡選單 icon（☰）、中央標題「CoinView Lite」（青綠色 #4ECDC4 系）、右側加號（＋）用於新增幣種
- **清單列結構**：每列高度約 100px（截圖），左側為幣種符號大字（`BTC`）+ 交易對小字灰色（`/USDT`），右側為綠色向上三角 + 漲跌百分比（`▲ 12.32%`）
- **列上未顯示價格數字** — 只有百分比。使用者決定 BitPrice 要多加價格
- **列分隔線**：淺灰細線，滿版寬度
- **選中/hover 態**：第一列（BTC）底色略淺灰，其餘白底
- **右側捲軸**：清單可滾動，捲軸細長置右
- **底部推廣橫幅**：「Try new CoinView for macOS / Price Alert, News, Portfolio」+ 青綠色圓角「Details ≫」按鈕 + 右上關閉叉（✕）+ 顯示器插圖。BitPrice 不需此區
- **清單範例內容**：BTC/USDT、ETH/USDT、ETH/BTC、DOGE/USDT、SOL/USDT、BNB/USDT、ONDO/USDT、SAND/USDT（8 檔可見）
- **注意**：`ETH /BTC` 存在 — 該 app 支援非 USDT 計價的交叉交易對

從截圖得到的設計啟示：BitPrice 沿用「符號大字 + 交易對小灰字 + 右側漲跌」的列骨架，但**加入 sparkline 與價格數字**，並移除底部推廣橫幅。

---
*每 2 次查看/瀏覽器/搜尋操作後更新此檔案*
