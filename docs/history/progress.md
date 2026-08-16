# 進度日誌 — BitPrice

## 會話：2026-08-03 → 08-04

### Phase 1: 需求與探索
- **狀態:** complete
- **開始:** 2026-08-03 18:02
- 執行動作:
  - 實測本機環境：`sw_vers`（macOS 15.6.1 / 24G90）、`swift --version`（6.1.2，arm64-apple-macosx15.0）、`xcodebuild -version`（**無輸出 → Xcode 未安裝**）
  - curl 實測 5 家公開幣價 API：CoinGecko ping 200、CoinGecko simple/price、CoinGecko search、Binance ticker/24hr、Kraken Ticker、Coinbase spot、OKX market/ticker — 全部 200 OK 且免 auth
  - WebSearch 查證 CoinGecko 免費層速率限制與月配額（Demo key 100 calls/min、10,000 calls/月）
  - curl 實測 sparkline 資料來源：Binance klines（24 根 1h OK、weight header 4）、Binance 多 symbol 批次（**失敗 -1102**）、CoinGecko market_chart（288 點）、CoinGecko markets sparkline=true（**3 幣 1 call，各 168 點，成功**）
  - 檢視使用者提供的參考 app 截圖（CoinView Lite），逐項記錄介面結構為文字
  - 向使用者確認 4 項規格決策（建置方式、bar 顯示、列內容、走勢範圍）
- 建立/修改檔案:
  - `Sources/BitPrice/`、`Resources/`、`scripts/`（空資料夾，使用者喊停前建立）
  - `findings.md`（建立）

### Phase 2: 規劃與架構
- **狀態:** complete
- **開始:** 2026-08-03 18:20
- 執行動作:
  - 驗算 CoinGecko 配額 vs 各輪詢間隔，確認 REST 輪詢不可行（15s/30s/60s 各超上限 17/8/4 倍）
  - 定案三層資料架構：Binance WebSocket（價格即時 push）/ CoinGecko markets（sparkline 10 分鐘）/ CoinGecko search（使用者觸發）
  - 確認建置路徑：原定 SwiftPM + 手工 `.app` bundle；Phase 2.6 實測後修正為 `swiftc` 直接編譯 + 手工 bundle，零第三方依賴
  - 依使用者選擇定案 UI 規格：bar 單一主幣、列含四元素、走勢 24h
  - 建立三份規劃檔案
- 建立/修改檔案:
  - `findings.md`（建立）
  - `task_plan.md`（建立）
  - `progress.md`（建立）
  - `IMPLEMENTATION.md`（建立，9 節完整實作規格）
- **狀態變更:** complete（2026-08-03 18:52）

### Phase 2.5: 規格修訂（Codex 審查後新增）
- **狀態:** complete
- 執行動作:
  - 確認 Codex CLI 可用（`codex-cli 0.144.4`，路徑 `/Users/wayne/.nvm/versions/node/v24.15.0/bin/codex`）
  - 委派 codex-rescue subagent 進行 design review（fresh thread，prompt 全英文依全域規則）
  - 自查發現並修正 build script 的 `Contents/Contents` 路徑錯誤與多餘的 `--deep`（在送審前修掉）
  - 收到 Codex 審查：2 blocker、8 major、7 minor、3 nit；架構獲認可
  - 審查全文結構化記入 `findings.md`
  - 依審查結果在 `task_plan.md` 新增 Phase 2.5 清單，B1/B2、socket lifecycle、健康狀態、HTTP/sparkline 防護、minor 與 bundle 驗證均在 revision 2 處理
  - 此階段採用的動態 `SUBSCRIBE`/`UNSUBSCRIBE`、六態 socket、application-wide generation、四時間戳健康狀態等機制，後於 revision 4 依 `IMPLEMENTATION.md` §6 明確簡化或撤回
  - 續接 Codex thread `019fc726-637f-74b2-aff1-3c344477d7ee` 進行 round-2 複審
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（修正 build script；revision 2 於 Phase 2.7 完成）
  - `findings.md`（新增 Codex 審查章節）
  - `task_plan.md`（新增並完成 Phase 2.5、更新錯誤表）
  - `progress.md`（本檔案）

### Phase 2.6: 工具鏈修復
- **狀態:** complete
- 執行動作:
  - 診斷 `import Foundation` 失敗為兩個 modulemap 同名宣告 `module SwiftBridging`；使用者停用舊 `module.modulemap` 後驗證通過（`fnd ok`）
  - 確認 SwiftPM 是獨立故障：修正 modulemap 後四種 manifest 組合仍失敗
  - 驗證 `swiftc` 直接編譯 Swift 6 + Foundation/UserNotifications/AppKit 可用
  - 確認 deployment target 必須降至 macOS 14.0，因 `.macOS(.v15)` 不存在於此工具鏈
  - 確認 bare executable 會以 `bundleProxyForCurrentProcess is nil` 崩潰；手工 ad-hoc-signed bundle 通過 `plutil -lint` 與 `codesign --verify`
  - 保留兩項限制：SwiftPM 需 CLT 重裝；通知送達因無 GUI session 無法驗證
- 建立/修改檔案:
  - 系統工具鏈舊 `module.modulemap` → `.disabled`（由使用者執行）；未建立專案原始碼

### Phase 2.7: revision 2 規格與複審
- **狀態:** complete
- 執行動作:
  - 依 round-1 全面改寫 `IMPLEMENTATION.md` revision 2，加入 changelog、price alert、BTC-only seed、合法空清單與工具鏈實測結果
  - 驗證計畫擴充至 48 項 + 4 項前置條件，test 20a 標為手動
  - 續接原 thread 送 round-2；首次回報內容不完整，重新索取後取得完整 findings
  - round-2 結果為 7 項關閉、3 項部分關閉、2 新 blocker、8 新 major
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 2）
  - `findings.md`（round-2 findings）
  - `task_plan.md`、`progress.md`（階段與狀態紀錄）

### Phase 2.8: revision 3 規格修訂（round-2 後新增，Phase 3 仍 gated）
- **狀態:** complete
- 執行動作:
  - 處理雙 venue mapping、ticker 僅作候選、confirmed subscription/ack、alert validation/persistence、Swift 6 actor boundary、alert history 與測試缺口等 14 項
  - 續接同 thread 以 high effort 進行 round-3 複審
  - revision 3 當時完成的 desired/confirmed subscription、async snapshot、alert history/rich health 等機制，後於 revision 4 依 §6 明確撤回或簡化
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 3）
  - `task_plan.md`、`progress.md`（階段與狀態紀錄）

### Phase 2.9: revision 3.1（round-3 後修正）
- **狀態:** complete
- 執行動作:
  - round-3 關閉 9/14，並發現 revision 3 新增 alert `isArmed` 初始化 blocker
  - 定義新建/migration/編輯三種 latch 初始化，加入 typed subscription command + 10 秒 ack timeout、單一 `AppSnapshot`、Coinbase failback、v1 一律 `.userConfirmed`
  - 補齊 observer callback isolation、build script null-delimited、notification `.scheduled` 用字與 tests 36g–36p、61–69
  - 兩個 open question 定案：v1 不做 contract-address auto-accept，多 alert 延後
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 3.1）
  - `task_plan.md`、`progress.md`（階段與狀態紀錄）

### Phase 2.10: Round-4 複審與 revision 3.2
- **狀態:** complete
- 執行動作:
  - 首次 subagent 委派因 `bfs: error: No such file or directory` 未啟動，改由主執行緒 `codex exec resume` 完成 round-4
  - round-4 關閉前輪 blocker，但找到 revision 3.1 新 blocker + 7 major
  - 修正 alert fire transaction 順序、re-arm durability、stale `inFlight`、ack timeout serialization、circuit breaker、failback dwell/source holdout、Coinbase-only initialization 與 Sendable callback payload
  - 新增 tests 70–83，並自查移除 `Codable WatchItem` 中不應持久化的 `activeExchange`
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 3.2）
  - `task_plan.md`、`progress.md`（round-4 與修訂紀錄）

### Phase 2.11: Round-5（換模型 gpt-5.6-sol，high effort，新 thread）
- **狀態:** complete
- 執行動作:
  - 將 Codex 預設模型切換為 `gpt-5.6-sol` + high 並備份原設定
  - 以 read-only sandbox 送 round-5；前兩次因 1,369 行規格耗盡預算，改成不讀檔、依描述提問後取得結論
  - 新模型判定規格過度設計：16 項機制建議砍 13 留 3，並直答 1,369 行 + 83 tests 讓正確實作更不可能
  - 發現前四輪漏掉的 clock-source 錯誤：8 項時間量測中 7 項應用 monotonic clock
  - 自查修正 §5.4「one socket for the whole app lifetime」與 §5.2「at most one at a time」矛盾
- 建立/修改檔案:
  - `~/.codex/config.toml`、`~/.codex/config.toml.bak`
  - `IMPLEMENTATION.md`（修正 socket 敘述）
  - `task_plan.md`、`progress.md`（round-5 結果）

### Phase 2.12: 決定路線
- **狀態:** complete
- 執行動作:
  - 比較 revision 4 簡化、直接依 revision 3.2 開工、保留風險清單但簡化實作三條路線
  - 使用者選擇接受 round-5 結論，改寫 revision 4；保留每幣使用者確認
- 建立/修改檔案:
  - `task_plan.md`、`progress.md`（路線決策）

### Phase 2.13: revision 4 草稿
- **狀態:** complete
- 執行動作:
  - 將 1,369 行 revision 3.2 保存為 `IMPLEMENTATION_r32.md`
  - 委派 Codex 寫 `IMPLEMENTATION_v4_draft.md`；當時因讀完整規格耗盡預算而判定未產檔，遂依三次失敗協定改由主 agent 撰寫
  - 主 agent 產出 555 行、32 tests 草稿；此版本後於 Phase 2.14 被 Codex 的 598 行、24 tests 版本覆寫
  - 驗證 Coinbase change、CoinGecko identity、alert latch、clock sources 與工具鏈事實均保留
- 建立/修改檔案:
  - `IMPLEMENTATION_r32.md`（revision 3.2 歷史保存）
  - `IMPLEMENTATION_v4_draft.md`（主 agent 的 555 行草稿，後被覆寫）

### Phase 2.14: 定案 revision 4
- **狀態:** complete
- 執行動作:
  - 修正背景委派失敗的誤判：Codex 檔案寫入晚於單次 `ls`，其 598 行版本覆寫主 agent 的 555 行版本
  - 完整驗證 Codex 版保留四大硬問題與所有工具鏈事實
  - 確認其補強 built-in BTC mapping、UUID `primaryItemID`、stream 排序、connection UUID、`schemaVersion` 與 corrupt-file Reset
  - 將 `IMPLEMENTATION_v4_draft.md` 定案為 598 行 `IMPLEMENTATION.md`，刪除草稿；保留 1,369 行 `IMPLEMENTATION_r32.md`
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 4，598 行、24 tests）
  - `IMPLEMENTATION_v4_draft.md`（定案後刪除）
  - `IMPLEMENTATION_r32.md`（保留）

### Phase 2.15: Revision 4 首次審查
- **狀態:** complete
- 執行動作:
  - 委派 `gpt-5.6-sol`、全新 thread、read-only sandbox，避免由撰寫者自審
  - 明確禁止讀取 `IMPLEMENTATION_r32.md` 與完整 `findings.md`
  - 委派方式改為 prompt 內嵌完整 598 行 spec + 明令 `Do NOT read any files. Do NOT web search.`，一次成功，未如前四次爆預算
  - 指定五組交叉審查對：alert 三節、時鐘表 vs 全文時間量、§6 砍除項 vs 他處假設、§7 風險 vs 引用章節、§8 測試 vs 實際行為
  - 自查提出的 ping 疑慮獲部分駁回：`URLSessionWebSocketTask` 在 message 邊界下自動處理 control frame，app 不應自解 server Ping；但規格仍須明文寫出此契約，且附帶抓到清醒偵測窗實為 60–75 秒而非 60 秒
  - 取得結果：**1 blocker、9 major、4 minor**
- 建立/修改檔案:
  - `task_plan.md`、`progress.md`（委派狀態與審查重點）

### Phase 2.15b: 審查結果復原與收錄（2026-08-12）
- **狀態:** complete
- 執行動作:
  - 發現三份規劃文件皆記載「等待 revision-4 審查結果」，但結果不在任何檔案中，無法判斷是未回或回了沒記
  - 掃描 `~/.codex/sessions/2026/08/{03,04}/`，依 `cwd` 過濾出 13 個 BitPrice session，比對時間序定位到 `019fc82f-c4ff-7bb3-9af0-3e5903e893fe`（23:13:21，緊接在 `IMPLEMENTATION.md` 23:11 定案之後）
  - 確認該 session 已於 2026-08-03 23:13 回傳 7,318 字元判定，**當時未寫入任何檔案，遺失九天**
  - 判定全文另存 scratchpad `r4_review_verdict.md`
  - 結果結構化寫入 `findings.md`；`task_plan.md` 關閉 Phase 2.15、新增 Phase 2.16、錯誤表新增一列
- 建立/修改檔案:
  - `findings.md`（新增「Revision 4 首次審查結果」章節）
  - `task_plan.md`（Phase 2.15 結案、新增 Phase 2.16、更新目前階段與錯誤表）
  - `progress.md`（本節）

### Phase 2.16: revision 4.1 規格修訂（2026-08-12）
- **狀態:** complete（14 項全修；待決定是否送 round-7）
- 執行動作:
  - 由主 agent 直接修訂，未委派 — 14 項缺陷的修法在審查判定中已明確，屬規格編輯而非判斷題；第二意見留給修訂後的 round-7
  - 修訂前備份 `IMPLEMENTATION.md` 為 scratchpad `IMPLEMENTATION_r4.before.md`
  - **blocker**：`FeedEvent` 由 enum 改為帶 `epoch: UUID` 的 struct + 巢狀 `Kind`，使任何 case 都無法遺漏 epoch；`TickerUpdate` 移除自身的 `sessionID`；§2.2、§3、§4.3、§6 item 2 用字全部統一為 client-local epoch
  - **major 1**：新增 §4.1.1「Staleness drives reconnect」— `connectedInstant`、每 epoch 至多一次 health reconnect、backoff 中不重啟。這是修訂中唯一新增的機制
  - **major 2**：新增 §2.2.1「Liveness and half-open detection」— framework 自動回 Pong、禁止 app 自解 control frame 與自建 ping 迴圈、清醒偵測窗 60–75 秒
  - **major 3**：§2.3 加入 `needsCoinbase` 條件式，`binanceUnmapped` 納入觸發條件
  - **major 4**：§4.6 明訂六步求值順序，cooldown 僅 gate 步驟 5
  - **major 5**：§3 加入自訂 `PriceAlert.init(from:)` 與 `schemaVersion` 三分支 migration 契約
  - **major 6**：§2.5 時鐘表由 5 列擴為 9 列，新增 `Retry-After` 雙形式與 client-wide 作用範圍說明
  - **major 7**：§4.2 加入 read-only recovery mode（所有寫入拒絕，Reset 為唯一例外）與母目錄建立
  - **major 8**：§2.2 明訂 attempt counter 跨 connect/close 保留、僅在有效 tick 後歸零
  - **major 9**：§8 由 24 項擴為 41 項，新增 tests 24–40 涵蓋 14 類遺漏行為
  - 4 項 minor 全修（§2.2 重連範圍、§1.1 quote asset 依來源推導、§4.6 rollback 用字、§7 Binance 中斷描述）
  - 自查發現並修正兩處新引入的矛盾：§2.4 原「skip the request and wait 60 seconds」與新的 client-wide deadline 衝突；§4.3 仍留「local session UUID」舊用字
  - 自查補上兩項連帶後果：recovery mode 期間 alert 不觸發（§4.2 + §7）、新版本寫入的檔案不被舊版降級（§7）
  - 結果：`IMPLEMENTATION.md` 598 → **787 行**，測試 24 → **41 項**。仍遠低於 r32 的 1,369 行
  - 驗證 scope：`IMPLEMENTATION_r32.md` md5 未變，未動其他檔案
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 4.1，787 行）
  - `task_plan.md`、`progress.md`（Phase 2.16 結案）

### Phase 2.16b: round-7 事故與 revision 4.2（2026-08-12）
- **狀態:** complete
- 執行動作:
  - 以更新後的 `codex-delegate` skill 送出 round-7（review mode、`gpt-5.6-sol`、effort high、design-review template、全新 thread、背景執行）
  - **中止**：兩個 lens 開場即讀取 `~/.agents/skills/planning-with-files-zht/SKILL.md`，並依該 skill 開始把自己的審查筆記寫進本專案的 `task_plan.md`、`findings.md`、`progress.md`，共 13 次寫入。lens B 甚至把「目前階段」改寫為描述它自己的審查
  - `pkill` 中止，`CODEX_FAIL|lensA|143/143`（SIGTERM），無 verdict 產出。`IMPLEMENTATION.md` md5 全程未變
  - 污染為附加式、邊界清楚，逐檔手工移除；移除前先將兩個 lens 的工作筆記搶救至 scratchpad `r41_partial_findings.md`
  - 根因：review mode 以 `workspace-write` 派工（verdict 必須可寫），等於開放整個 workspace；且 lens prompt 從未禁止修改專案檔案。已寫成事故報告送交另一 session 評估修法，明確要求等使用者批准才動 skill
  - 專案納入 git，baseline commit `448cc3f`，`.gitignore` 排除 `.codex-review/`。日後委派前先 commit，出事即 `git checkout`
  - 查證搶救筆記中的 3 項缺陷主張，**全部成立**並修正為 revision 4.2（見 `task_plan.md` Phase 2.16b）
  - 787 → 839 行，41 → 43 tests
- 建立/修改檔案:
  - `IMPLEMENTATION.md`（revision 4.2）
  - `.gitignore`（新建）
  - `task_plan.md`、`progress.md`（本節與 Phase 2.16b）
  - `findings.md`（移除污染，回復為 810 行）

### Phase 2.17: round-7 複審完成 — 判 reject（2026-08-12）
- **狀態:** in progress（短項已補；兩個 FLAG 另開 session）
- 執行動作:
  - 以修復後的 `codex-delegate` 重跑 round-7：`run_id=r42`、`gpt-5.6-sol`、effort high、design-review、雙 lens、1200s/lens
  - **委派本身首次完全按預期完成**：`CODEX_DONE`、contamination gate 通過、`git status` 乾淨、spec md5 `b06d3c0` 全程未變、work dir 外零寫入。sibling session 的 sandbox 修法（`cwd=WORK_DIR` + `disk-full-read-access` + 前後 hash 比對）實戰有效
  - 另於 role prompt 自行加上 fix B（明文禁止寫入 verdict 以外的檔案、禁止使用任何 planning skill）—— 結構性修法已足夠，但這是事故的實際觸發點，成本為零
  - 結果 **20 項全 `true_hit`：2 blocking、12 major、6 minor**，lensB 判 reject。全文收錄至 `findings.md`
  - 查證兩個 blocker 屬實：`reconnect()` 有回傳值無參數（watchlist 變動重連舊 URL）；client 自主 retry 的 epoch 無管道到達 `AppModel`，且 §4.3 自己的禁令關掉唯一替代路徑，Binance 斷線後永久卡死
  - 補短項四則：test 24/26 的 60 秒改為嚴格大於、`isArmed` fallback 限定 schemaVersion 0、§4.2 補上「未定義 migration 的較舊版本」進入 recovery、test 37 擴充涵蓋該分支
  - **兩個 FLAG 未動**：串流介面整體重設計、其餘既存 major/minor。均另開 session
- 建立/修改檔案:
  - `findings.md`（新增 Round-7 節）
  - `task_plan.md`（新增 Phase 2.17 與 FLAG）
  - `IMPLEMENTATION.md`（四則短修正，839 → 850 行）
  - `progress.md`（本節）
- **教訓**：revision 4.2 的四項修改有三項引入新缺陷，且都是同一形狀 —— 文字描述的機制讀起來成立，但介面 supply 不了它需要的東西，或粒度細不到它要偵測的層級。這已是連續第四輪。本輪 role prompt **已明白寫出這個形狀並要求 lens 針對它查**，我仍在同一次修訂中又犯三次。把失敗模式寫進委派說明防不住自己再犯，只有換人審才擋得住

### Phase 2.18–2.20: 串流重設計、`SPEC.md` 與其複審（2026-08-12 → 08-13）
- **狀態:** complete（詳見 `task_plan.md` Phase 2.18–2.20）
- 執行動作:
  - Phase 2.18 由主 agent 重寫 §4.3 契約 → 審查判 **reject**（`.superseded` barrier 假設 `AsyncStream.Continuation` 有 purge 能力，該操作不存在）
  - Phase 2.19 改委派 Codex 從零重新設計（`run_id=rd1`），產出 **`SPEC.md`（638 行）**，`IMPLEMENTATION.md` 降為歷史
  - Phase 2.20 全新 thread 雙 lens 獨立複審 `SPEC.md`（`run_id=spec1`）→ 判 **reject**，15 項缺陷（6 blocking），四項兩 lens 獨立收斂
  - 判定：主架構未被推翻，但六個 blocking 中至少三個是同一失敗形狀的新實例 —— **換作者未換掉形狀**
  - 決定**不再修訂第七次**。理由：這六項全屬「實作第一天就會撞到並且立刻知道答案」的類型，紙上再推一輪只會產出 round-9
- 建立/修改檔案:
  - `SPEC.md`（新建，638 行，取代 `IMPLEMENTATION.md` 成為建置藍圖）
  - `.planning/redesign/{task_plan,findings,progress}.md`（Codex 自身推理紀錄）
  - `findings.md`、`task_plan.md`、`progress.md`

### Phase 3–4: 實作（委派 Codex，`run_id=impl1`，2026-08-13）
- **狀態:** complete
- 執行動作:
  - 15 項複審缺陷**前置為建置需求**而非事後待辦，修法逐項取自兩個 lens 的 `what_would_change_my_mind`
  - Codex 一次交付可編譯、可測試的完整實作
  - **我獨立驗收**（非採信 Codex 報告）：乾淨樹 `rm -rf build && bash scripts/build-app.sh` exit 0；`bash scripts/run-tests.sh` 25 passed / 0 failed / 2 skipped（skip 皆印出理由）；`codesign --verify --strict`、`plutil -lint`、`file` 全通過（Mach-O arm64）；`LSUIElement=true`、`LSMinimumSystemVersion=14.0`；grep 確認無 `swift build`／`Package.swift`；受保護四檔 mtime 全部早於 dispatch 21:04
  - 讀碼抽查三項缺陷修法：`makeLifetimeSession` 終身重用且 `didOpen`/`didClose` 皆帶 `connectionID: UUID`；`actor TokenBucketPacer` Coinbase 10 req/s burst 15 與官方文件一致；v0/v1 JSON fixture 真實存在
  - **未能驗證**：無 Aqua GUI session → 無法啟動 app、無法驗證通知呈現、無 live network smoke test
- 建立/修改檔案:
  - `Sources/BitPrice/` 11 個檔案（2,841 行）、`Resources/Info.plist`
  - `scripts/build-app.sh`、`scripts/run-tests.sh`
  - `Tests/TestMain.swift`（578 行）、`Tests/Fixtures/watchlist-v0.json`、`watchlist-v1.json`
  - `.planning/impl/{task_plan,findings,progress}.md`
- **commit:** `21b4961 feat: implement BitPrice from a ground-up respecified architecture`

### Phase 5: 實跑驗證 — 六項缺陷（2026-08-13）
- **狀態:** complete
- 執行動作:
  - 使用者於真實桌面首次啟動 app。**七輪規格複審、43 項規定測試、25 項實作測試全數放行的六個缺陷，在數分鐘內全部浮現**
  - 逐項定位與修正（詳見 `findings.md`「實跑驗證發現」節與 commit `e5634ed`）：alert 觸發崩潰、面板每次互動即消失、無退出途徑、存 alert 導致退出、漲跌%取整、hysteresis 不可見
  - **崩潰修正曾誤報一次**：首次只移除 `NotificationService` 的 `@MainActor` 即宣告修好，使用者回報仍崩。以 binary 複製時間（22:24:24）對照崩潰時間（22:25:59）確認使用者拿的確實是新版，重讀 crash report 為同一 stack。真因是 `withCheckedContinuation` 繼承**呼叫端**隔離，而 `AppModel` 從 `Task { @MainActor }` 呼叫。二次修正後改以 symbol 層級（`YbcfU_` 無 MainActor 標註）加 md5 比對才回報
  - 使用者實測確認：通知橫幅送達；關閉 Wi-Fi 轉 stale、開啟即回 live（不需等 90 秒）。**此復原路徑正是四輪紙上複審都沒改對的那條**
  - 使用者環境問題釐清：`ls: Operation not permitted` 與 `open` 失敗為 TCC 阻擋終端存取 `~/Documents`，非 bundle 損壞（已驗證 `APPL` 與 executable 完好）
- 建立/修改檔案:
  - `Sources/BitPrice/NotificationService.swift`、`Views.swift`、`AppModel.swift`
  - `Tests/TestMain.swift`（test 22 加 decimal 回歸斷言）
- **commit:** `e5634ed fix: six defects found by running the app for the first time`

### Phase 5.1: UI 三輪重整（委派 Codex，`run_id=ui1/ui2/ui3`，2026-08-13 → 08-14）
- **狀態:** complete
- 執行動作:
  - **ui1**（4 項）：app 無圖示、bar 只有小 icon 看不到價格、文字過小、版面需改為一列一幣 + 底部走勢圖
    - 根因之一為 API 誤用：`MenuBarExtra(_:systemImage:)` **只渲染圖片並靜默丟棄標題**，`menuBarTitle` 一直正確產出 `"BTC 63,928.65"` 卻從未顯示。改用 `label:` 形式
    - 圖示以 `scripts/make-icon.swift` 程式繪製，`make-icon.sh` 產生 10 個尺寸的 iconset 後 `iconutil` 打包，build 時嵌入。無第三方素材、無 binary 進版控
    - 列重構為單行（star / symbol / quote / price / change% / Alert）；sparkline、mapping IDs、排序鍵移入底部詳細區
  - **ui2**（2 項）：退出鍵移至標題左側並改為確認式（新增 `PanelRoute.confirmQuit`）；Add coin 搜尋列改固定寬度前導欄以對齊
  - **ui3**（4 項）：走勢圖補 X/Y 座標軸、文字再放大、星號存廢、圖示未見
    - **兩項使用者前提經查證不成立**，未照單全收：星號**確實有作用**（設定 `primaryItemID`，驅動 `menuBarTitle`）；圖示**已正確產生**（10 尺寸、256px 為 60 KB 非空白），Finder 顯示的是舊快取。以 AskUserQuestion 交回使用者裁決，選擇為「保留星號但加強說明」與「先只清快取」
    - `ChartAxisCalculator` 取真實 min/max 與真實時間戳，三個退化情況（flat / 單點 / 空序列）皆處理並以 test 22b 斷言，涵蓋 63,824 與 0.33 兩種價格尺度
  - 三輪皆以硬約束派工：禁 `.sheet`/`.popover`/`.alert`/`.confirmationDialog`/`NSAlert`/menu-style `Picker`（`MenuBarExtra(.window)` 失去 key window 即關閉）、禁 `.keyboardShortcut`、禁動 `NotificationService.swift`、禁 `@preconcurrency`/`@unchecked Sendable`/`Task.detached`、禁 SwiftPM、禁造假資料。每條約束都來自一個已發生的崩潰或缺陷
  - 驗收：乾淨樹建置 exit 0（zero warnings）、`26 passed / 0 failed / 2 skipped`、bundle 檢查全過且含 `AppIcon.icns`、grep 自身 diff 確認無禁用 API 復活
- 建立/修改檔案:
  - `Sources/BitPrice/Views.swift`（主要）、`BitPriceApp.swift`
  - `scripts/make-icon.sh`、`scripts/make-icon.swift`、`scripts/build-app.sh`
  - `Tests/TestMain.swift`（新增 test 22b）
  - `.planning/ui/{task_plan,findings,progress}.md`
- **commit:** `22150b8 feat: rework the panel UI around a compact row list and a detail area`
- **未驗證（本機無 Aqua GUI session）**：版面比例、字級是否足夠、座標軸標籤是否擁擠、圖示清快取後外觀 —— 只有桌面前的人能判斷

### Phase 6: 交付
- **狀態:** in progress
- 執行動作:
  - 四個 commit 就緒：`7fe35df`（規格）→ `21b4961`（實作）→ `e5634ed`（實跑修正）→ `22150b8`（UI 重整）
  - 已提供安裝與清快取步驟（複製至 `~/Applications` 以繞開 TCC 對 `~/Documents` 的阻擋）
  - **待辦**：使用者回報 ui3 視覺結果；撰寫使用說明
- 建立/修改檔案:
  - （待）

## 測試結果

API 可用性實測（2026-08-03，Phase 1）：

| 測試 | 輸入 | 預期 | 實際 | 狀態 |
|------|------|------|------|------|
| CoinGecko ping | `GET /api/v3/ping` | 200 | 200 | ✓ |
| CoinGecko 多幣多法幣報價 | `simple/price?ids=bitcoin,ethereum&vs_currencies=usd,twd&include_24hr_change=true` | 價格 + 24h 漲跌 | BTC $62,725 / NT$2,036,528、ETH $1,849.32，含 24h change | ✓ |
| CoinGecko 幣種搜尋 | `search?query=sol` | 相關幣種列表 | Solana（rank 7）、Solstice… 含 thumb/large 圖示 URL | ✓ |
| Binance 批次報價 | `ticker/24hr?symbols=["BTCUSDT","ETHUSDT"]` | 兩檔報價 | lastPrice 62794.13、priceChangePercent -0.659 | ✓ |
| Kraken 報價 | `Ticker?pair=XBTUSD` | BTC 報價 | XXBTZUSD last 62713.80 | ✓ |
| Coinbase spot | `prices/BTC-USD/spot` | BTC 現價 | 62723.915 | ✓ |
| OKX 報價 | `market/ticker?instId=BTC-USDT` | BTC 報價 | last 62792.3，含 open24h/high24h/low24h | ✓ |
| Binance klines 24×1h | `klines?symbol=BTCUSDT&interval=1h&limit=24` | 24 根 K 線 | 24 bars，closes 63031.99… | ✓ |
| Binance klines weight 成本 | 同上，檢查 response header | 低 weight | `x-mbx-used-weight-1m: 4` | ✓ |
| Binance klines 多 symbol 批次 | `klines?symbols=["BTCUSDT"]&interval=1h` | 批次 K 線 | `-1102 Mandatory parameter 'symbol' was not sent` | ✗ 不支援 |
| CoinGecko market_chart | `coins/bitcoin/market_chart?vs_currency=usd&days=1` | 1 日價格點 | 288 點 | ✓ |
| CoinGecko markets 批次 sparkline | `coins/markets?ids=bitcoin,ethereum,solana&sparkline=true&price_change_percentage=24h` | 多幣價格 + 漲跌 + 走勢 | btc/eth/sol 各 168 點 sparkline + 價格 + 24h% | ✓ |

## 錯誤日誌

| 時間 | 錯誤 | 嘗試 | 解決 |
|------|------|------|------|
| 2026-08-03 18:02 | `xcodebuild -version` 無輸出，Xcode 未安裝 | 1 | 原定 SwiftPM；Phase 2.6 證實其不可用後，最終改走 `swiftc` 直接編譯 + 手工 `.app` bundle |
| 2026-08-03 18:25 | Binance klines `symbols=` 回 `{"code":-1102,"msg":"Mandatory parameter 'symbol' was not sent, was empty/null, or malformed."}` | 1 | 該端點無批次能力；sparkline 改用 CoinGecko `coins/markets?sparkline=true` |
| 2026-08-03 18:22 | CoinGecko 免費配額不足支撐即時輪詢（驗算 60s 間隔即超上限 4 倍） | 1 | 價格層改 Binance WebSocket，CoinGecko 降為 10 分鐘 sparkline + 使用者觸發搜尋 |
| 2026-08-03 18:45 | build script 路徑錯誤 `"$APP/Contents/Contents/Info.plist"`（`Contents` 重複） | 1 | 送審前自查發現，改單層 `Contents/Info.plist`；同時移除多餘 `codesign --deep`。Codex 複核確認 bundle 結構與簽章方式正確 |
| 2026-08-03 18:52 | Codex：Coinbase `/v2/prices/{pair}/spot` 只回 amount/base/currency，**無 24h 漲跌** → fallback 幣種湊不出列的顯示契約 | 1 | 列 B1，Phase 2.5 重寫 fallback 契約（`Quote.changeUnavailable` + product ID 獨立解析） |
| 2026-08-03 18:52 | Codex：`uppercase(symbol) + quoteAsset` 經 exchangeInfo 驗證只證明交易對存在，不證明與 CoinGecko id 同一項目（symbol 不唯一，可能是 wrapped/bridged 代幣） | 1 | 列 B2，改 `MarketMapping{coinGeckoID, exchange, productID, baseAsset, quoteAsset}` 一級產物 |
| 2026-08-03 18:52 | Codex：socket 有 5 個來源可各自轉換狀態（watchlist 變更/23h 重連/backoff/receive 失敗/睡眠喚醒），互相競態 | 1 | revision 2 曾改用動態 SUBSCRIBE/UNSUBSCRIBE；revision 4 撤回後以單一 owned task、local session UUID 與 combined URL rebuild 簡化 |
| 2026-08-03 18:52 | Codex：app 層 `sendPing` **不能取代**回應 server 發起的 ping frame；5 msg/sec 限額涵蓋所有控制流量 | 1 | 列 M1，修正 §2.1 描述 |
| 2026-08-13 22:25 | 觸發 alert 時 app 整個崩潰，`dispatch_assert_queue` trap | 2 | 第一次只移除 `NotificationService` 的 `@MainActor`，**我宣告修好但實際仍崩**。真因：`withCheckedContinuation` 繼承**呼叫端**隔離，`AppModel` 從 `Task { @MainActor }` 呼叫。改為每個 continuation body 明標 `@Sendable`，非 Sendable 的 `UNNotificationRequest` 在 closure 內建構。未用 `@preconcurrency` 或 `@unchecked Sendable` |
| 2026-08-13 22:30 | 點任何按鈕或下拉選單，面板整個消失 | 1 | `MenuBarExtra(.window)` 失去 key window 即關閉，而 `.sheet` 與 menu-style `Picker` 正好造成此事。編輯器改由 `PanelRoute` enum 就地替換面板內容；venue 改 inline radio、direction 改 `.segmented` |
| 2026-08-13 22:35 | 存 alert 按 Save 後 app 自動退出 | 1 | 我自己加的退出鍵造成的回歸：Save 帶 `.defaultAction`、quit 帶 `⌘Q`，`close()` 回到清單後同一個鍵盤事件抵達 quit。兩個 shortcut 全移除，quit 改兩段式 |
| 2026-08-13 22:40 | 漲跌% 顯示 `+0%`／`+1%`，看似解析失敗 | 1 | `NSDecimalNumber.rounding(nil)` 取整。改 `NumberFormatter` 固定兩位小數 + `positivePrefix = "+"`。原 test 22 只斷言正負號故一路通過，已補小數回歸斷言 |
| 2026-08-13 22:42 | alert 只跳一次，之後需重設才會再觸發 | 1 | 引擎正確、UI 從未揭露規則：1% hysteresis 在 63,966 門檻上等於要跌 640 才 re-arm。編輯器改為明寫觸發價與計算後的 re-arm 價，並在目前 disarmed 時明說 |
| 2026-08-13 23:50 | 使用者 `ls: Operation not permitted`、`open build/BitPrice.app` 回 `kLSApplicationNotFoundErr` | 1 | 非 bundle 損壞（已驗證 `APPL` 與 executable 完好）。TCC 阻擋終端存取 `~/Documents`；改複製至 `~/Applications` |
| 2026-08-14 00:00 | 使用者回報「星號無作用」「沒有圖示」 | 1 | **兩項前提查證後皆不成立**：星號確實設定 `primaryItemID` 並驅動 `menuBarTitle`；圖示已正確產生（10 尺寸、256px 60 KB 非空白），Finder 顯示舊快取。未照單修改，改以 AskUserQuestion 交回使用者裁決 |

## 五問重啟檢查

| 問題 | 答案 |
|------|------|
| 我在哪裡？ | Phase 6 進行中 — app 已實作、實跑修正、UI 三輪重整完畢，四個 commit 就緒（`7fe35df` → `21b4961` → `e5634ed` → `22150b8`）。建置與測試全綠（26 passed / 0 failed / 2 skipped）。**等使用者回報 ui3 的視覺結果** |
| 我要去哪裡？ | 使用者確認 UI → 依回報微調 → 撰寫使用說明 → 交付。實作期風險清單（round-7 C 群 6 項）依實際遇到再處理 |
| 目標是什麼？ | macOS menu bar app：bar 顯示單一主幣即時價，點擊展開自訂清單（符號 + 24h sparkline + 價格 + 漲跌%），支援搜尋、持久化與 alerts；免 Xcode，以 `scripts/build-app.sh` 直接驅動 `swiftc` 並手工組裝 ad-hoc-signed `.app` bundle |
| 我學到了什麼？ | (1) CoinGecko 免費配額撐不住即時價格，Binance klines 無批次；(2) SwiftPM 在此工具鏈因 `PackageDescription.Package.__allocating_init` undefined symbol 無法使用，deployment target 必須降至 macOS 14.0；(3) bare executable 會以 `bundleProxyForCurrentProcess is nil` 崩潰；(4) round 1–2 找到真實設計缺口，round 3–4 多半找到前版修訂自行引入的矛盾，round 5 換模型後判定整體過度設計，round 6 抓到的是簡化時斷掉的連接點；(5) 前四輪都漏掉 clock-source 錯誤，8 項時間量測中 7 項應使用 monotonic clock；(6) 委派回傳後若未當場寫入檔案，結果會遺失 — revision 4 的審查結果就這樣消失九天；(7) 同一失敗形狀連續出現五次（介面 supply 不了機制所需、粒度不夠細、假設不存在的平台操作），把失敗模式寫進 role prompt 防不住自己再犯，換人審才擋得住 —— 但 Phase 2.20 證明**換作者也換不掉形狀**，`SPEC.md` 六個 blocking 中三個仍是同一形狀；(8) **紙上複審有其上限**。七輪複審 + 43 項規定測試 + 25 項實作測試全數放行的六個缺陷，在真實桌面啟動後數分鐘內全部浮現。測試跑的是注入的 fake，複審讀的是文件 —— 文件不能被點擊；(9) 使用者回報的缺陷前提**必須先查證**。三項 UI 主張中有兩項不成立（星號有作用、圖示已產生），照單全收會刪掉正確功能；(10) 宣告修好前要驗到 symbol 層級。alert 崩潰第一次我看原始碼就宣告修好，實際仍崩 |
| 我做了什麼？ | 實測環境、5 家 API 與兩種走勢來源；建立規劃與規格；修復 modulemap 工具鏈問題並驗證 `swiftc`/bundle 路徑；完成 revisions 2–4.3 與七輪 Codex review；round 5 換模型後接受過度設計結論，規格由 1,369 行/83 tests 簡化為 598 行/24 tests；round 7 判 reject 後放棄第七次紙上修訂，委派 Codex 從零重寫為 `SPEC.md`；獨立複審再判 reject 後**帶著 15 項清單開工**，由編譯器與測試取代 review 當驗證來源。實作一次交付即通過乾淨樹嚴格建置與全部測試；實跑抓到六個缺陷並修正；UI 三輪重整完成。四個 commit 已入版控 |

---
*每階段完成或遇到錯誤後更新*

