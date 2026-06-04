# Phase 1 — 切分 Event Struct，抽出 Grouped Ring

## 1. 现状问题

- `helixel-edit` 一个 struct 同时扮演 3 个角色：
  - **edit 描述**（op + sel + payload + runner）—— `helixel--last-edit` / `--live-event`
  - **history entry**（display + category + subcat + mark-region + timestamp + buffer）—— `helixel--event-ring`
  - **jump mark**（pos + buffer + group-key）—— `helixel--global-jump-log`
- 文档自己都困扰：`AGENTS.md` 把 `helixel-edit` 列了两次（"Three Structs"）。
- `helixel-edit-create` 的 keyword 处理是隐式特例（`:runner` / `:display` 特殊，
  其它进 payload），需要专门写一节 Pitfall。
- `--last-event` vs `--last-tx` 同义异名残留。
- 同一份 grouped-ring 查询逻辑（`group-start` / `group-newest` /
  `visible-index` / `visible-count` / `find`）服务两个 ring，但没独立成模块。

## 2. 目标

- 拆成 **3 个 struct**：
  - `helixel-edit`   — 纯描述：要执行什么（kind+ctx+op+payload+runner）
  - `helixel-history-entry` — ring 条目：display/category/subcat/mark-region/timestamp/buffer + `:edit` 字段引用 edit
  - `helixel-jump-mark` — 跳转节点：pos-marker + buffer + group-key + 可选 `:edit` 引用
- 抽出 `helixel-ring.el` → `helixel-grouped-ring.el`（纯数据结构，零 helixel 依赖）。
- `helixel-history.el`（旧 ring.el 的剩余部分）只剩 history + jump-log 的 commit / dedup 逻辑。
- 删除 `--last-tx` 残留，统一为 `--last-edit`。

## 3. 新结构

```elisp
;; helixel-edit.el  (从 core 拆出, 纯数据)
(cl-defstruct helixel-edit
  kind          ; symbol  — selection kind (line / rect / textobj / ...)
  ctx           ; plist   — selection context
  op            ; symbol  — operator id (kill / change / insert-text / ...)
  payload       ; plist   — decision data (chars, register, kmacro, ...)
  runner        ; fn(edit)  — replay closure (captured at record-time)
  mark-region)  ; (beg-marker . end-marker)  — selection bounds at record

;; helixel-history.el
(cl-defstruct helixel-history-entry
  edit          ; helixel-edit  — what was done
  category      ; symbol  — display group: edit/select/move/search...
  subcat        ; symbol  — finer group: kill/change/word/...
  display       ; string | fn(entry) → string
  timestamp     ; float-time
  buffer)       ; buffer (weak ref)

(cl-defstruct helixel-jump-mark
  pos           ; marker
  buffer        ; buffer
  category subcat
  edit)         ; optional ref into helixel-edit (for re-replay from jump)

;; helixel-grouped-ring.el  (零 helixel 依赖)
(cl-defstruct helixel-gr ring cap dedup-fn same-group-fn visible-fn)
(helixel-gr-push gr entry)
(helixel-gr-group-start gr pos)
(helixel-gr-group-newest gr pos)
(helixel-gr-find gr pos direction)
(helixel-gr-visible-count gr)
(helixel-gr-visible-index gr pos)
```

## 4. 文件改动

| 改动 | 文件 |
|------|------|
| 新增 | `helixel-edit.el`           (≈ 80 行) |
| 新增 | `helixel-grouped-ring.el`   (≈ 120 行) |
| 新增 | `helixel-history.el`        (从 ring.el 抽出 commit/dedup) |
| 重写 | `helixel-core.el`           (删 event struct，保留 sel + registries + delimiter) |
| 删除 | `helixel-ring.el`           (内容并入 history + grouped-ring) |
| 改 | 所有 `helixel-edit-*` 调用 → `helixel-edit-*` / `helixel-history-entry-*` |
| 改 | `helixel--last-edit` → `helixel--last-edit`；`--live-event` → `--live-edit` |
| 删 | `helixel-edit-create` 的隐式 keyword 切分；用 `make-helixel-edit` 显式构造 |

## 5. 兼容性

不维护。所有引用旧 struct 的代码（≈ 200 处）一次性 grep-rename。
`AGENTS.md` 中 "helixel-edit-create keyword handling" Pitfall 直接删除。

## 6. 验收

- [ ] `(symbol-value 'helixel--last-tx)` 任何残留全部清除
- [ ] `grep -rn "helixel-edit-" *.el` 输出为空
- [ ] `helixel-grouped-ring.el` 零 helixel 依赖（只 `require 'cl-lib`）
- [ ] 所有 ring/jump 测试通过（`test/helixel-test-ring.el` / `helixel-test-jump.el`
      可能需要少量改名，行为不变）
- [ ] `make depgraph` 显示新依赖图：
  ```
  helixel-grouped-ring (cl-lib only)
  helixel-edit (cl-lib only)
  helixel-core (→ edit)
  helixel-history (→ edit + grouped-ring)
  ```

## 7. 步骤

1. 写 `helixel-grouped-ring.el` + 单元测试（脱离 helixel 跑通）
2. 写 `helixel-edit.el`（纯 cl-defstruct）
3. 把 `helixel-edit` 的 history 字段挪到 `helixel-history-entry`，
   ring.el 改名 history.el，用 grouped-ring 实例
4. grep-rename `helixel--last-edit` → `helixel--last-edit`
5. grep-rename `helixel-edit-*` → 对应新名
6. 编译 + 测试 + 改 AGENTS.md
