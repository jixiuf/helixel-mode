# Phase 7 — 命名、文件粒度、文档收尾

## 1. 术语表（强制统一）

| 概念 | 唯一名 | 禁止使用 |
|------|--------|---------|
| 一次可重放的编辑描述              | `edit` (struct: `helixel-edit`)        | `tx`, `transaction`, `event` |
| ring/jump-log 的条目              | `entry` (`helixel-history-entry`)      | `event` |
| 跳转节点                          | `jump-mark`                            | `jump-entry`, `jump-event` |
| 录制中的"当前事件"                 | `helixel--live-edit`                   | `--live-event` |
| 最近一次已提交的 edit              | `helixel--last-edit`                   | `--last-event`, `--last-tx` |
| selection 描述                    | `sel` (`helixel-sel`)                  | 不变 |
| ring                              | `helixel-gr` (`helixel-grouped-ring`)  | `helixel--*-ring`（裸 list） |
| dot-repeat 调度上下文              | `helixel-replay-ctx`                   | "strategy" |
| chain 录制中的会话                | `helixel-chain-session`                | 7 个散变量 |
| fake-cursor 状态                  | `helixel-cursor`                       | "cursor-vars" |

## 2. 文件粒度调整

合并：

| 合并方向 | 理由 |
|---------|------|
| `helixel-textobj-engine.el` + `pair.el` + `block.el` + `marks.el` + `textobj.el` → `helixel-textobj.el`（约 2500 行） | 内部 5 文件互相 forward decl 过多，公开 API 走一个 facade 更清晰 |
| `helixel-mc-targets.el` → `helixel-mc-spawn.el`                  | targets 仅服务 spawn |
| `helixel-repeat-strategy.el` 删除（phase 4）                      | 内容并入 `helixel-repeat.el` 和各 kind 的 method 文件 |
| `helixel-insert-record.el` → `helixel-editing.el`（或保留独立但 ≤ 80 行） | 仅 1 个用途，文件过小 |

新增：

| 文件 | 行数 |
|------|------|
| `helixel-replay.el`         | 60 |
| `helixel-edit.el`           | 80 |
| `helixel-grouped-ring.el`   | 120 |
| `helixel-history.el`        | 150 |
| `helixel-repeat-line.el`    | 150 |
| `helixel-repeat-search.el`  | 150 |
| `helixel-repeat-chain.el`   | 100 |

最终文件数：当前 28 → 目标 22。

## 3. AGENTS.md / docs/ 收尾

需要重写 / 删除的章节：

- AGENTS.md
  - `File Map` 表整张重写
  - `Deps` 图重画
  - `Key Structs` 改成新 3 struct
  - `Key APIs` 改为新 API
  - **Pitfalls 段砍掉以下条目**（已被重构消除）：
    - "helixel--last-edit is buffer-local"（依然 buffer-local，但命名歧义没了）
    - "helixel-edit-create keyword handling"（phase 1）
    - "Never set defining-kbd-macro to t in long-lived insert recording"（kmacro 路径删除）
    - "Zero-width search patterns and infinite loops"（phase 2，移入 ctx）
    - "Strategy all-buffer-fn recursion"（phase 4）
    - "Multi-cursor (mc) — fake cursor model" 改写为新 struct 模型
    - "ctx-lint keys"（plist accessor 重新清点）
  - `Design notes` 整段重写

- `docs/ARCHITECTURE.md`
  - 与新 phase 结构同步
  - 添加新依赖图

- `docs/MACROS.md`
  - 增加 `:decide` / `:execute` / `:mc-policy` 说明
  - 删除"自动注入 helixel--tracking-open"的旧注释（如果有）

- `docs/DEPGRAPH.md`
  - `make depgraph` 自动重生成

- 新增 `docs/refactor/HISTORY.md`：每 phase 完成后写一段总结
  （什么删了、什么新增、什么测试加了），供未来 review。

## 4. ctx-lint 与代码风格

- ctx-lint 重新跑：phase 3 后 payload 字段全统一，新增 lint：
  - 禁止 `(plist-get (helixel-edit-payload edit) :foo)`，必须走访问器
    `(helixel-edit-payload-get edit :foo)`
  - 禁止裸 `defvar-local`，必须挂 session struct（phase 5/6 已做）

## 5. 验收（最终总验收）

- [ ] AGENTS.md File Map 与实际文件一致
- [ ] `make compile && make test && make lint` 全绿
- [ ] `make depgraph` 显示新依赖图，无循环
- [ ] 总行数 ≤ 10500（当前 14166，目标减 28%）
- [ ] `defvar(-local)` 总数 ≤ 25
- [ ] `advice-add` 总数 ≤ 8 且仅在 shims / state
- [ ] `*-hook` 注册点 ≤ 8
- [ ] 总览 README 中所有验收清单打勾

## 6. 步骤

1. grep-rename 全项目术语（一次性 PR）
2. 文件合并
3. 重写 AGENTS.md / ARCHITECTURE.md / MACROS.md
4. 跑 `make lint` 全绿
5. 写 `HISTORY.md` 总结
