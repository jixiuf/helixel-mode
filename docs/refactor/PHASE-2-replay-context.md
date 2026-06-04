# Phase 2 — 统一 Replay Context，删除散落的 Inhibit Flag

## 1. 现状问题

现在有 **6 个互相重叠的开关**，控制"我们到底在 replay 还是在录制"：

| 变量 | 位置 | 作用 |
|------|------|------|
| `helixel--in-replay`               | core.el     | dot-repeat / chain replay 期间 t |
| `helixel--inhibit-repeat-record`   | (隐式)      | 阻止 record-edit 把 replay 视为新 edit |
| `helixel--inhibit-action-track`    | (隐式)      | 阻止 replay 期间往 ring push |
| `helixel-mc--inhibit`              | mc-core.el  | mc 自己 dispatch 时不要再递归 dispatch |
| `helixel-mc-executing-command-for-fake-cursor` | mc-core.el | fake-cursor 上下文标志 |
| `helixel--search-advance-done`     | repeat.el   | recreate-search 跳过内部搜索 |

外加 3 个 search 防自旋全局：

| 变量 | 用途 |
|------|------|
| `helixel--advance-search-last-pos`    | 检测零宽匹配死循环 |
| `helixel--advance-search-edge-seen`   | buffer 边缘零宽匹配标志 |
| `helixel--repeat-permanent-flip`      | `-.` 永久反向 |

每个调用方都要自己 reset 这些变量，协议靠注释维护，是 bug 源头。

## 2. 目标

引入 **一个** 显式上下文 struct，所有 replay 状态都活在里面：

```elisp
(cl-defstruct helixel-replay-ctx
  origin         ;; 'dot | 'comma | 'chain | 'mc-fake | 'action-cycle
  fake-cursor    ;; overlay or nil
  edit           ;; helixel-edit being replayed
  reverse-p      ;; bool — direction flipped this call
  ;; --- internal search-advance scratch (lexical, not global) ---
  search-last-pos
  search-edge-seen)

(defvar helixel--replay-ctx nil
  "Non-nil only inside `helixel-with-replay'.")

(defmacro helixel-with-replay (origin edit &rest body)
  "Bind `helixel--replay-ctx', execute BODY.
Any code that needs to know `am I replaying?' checks
`helixel--replay-ctx'.  Search-advance scratch lives on the ctx, not
in globals.")
```

## 3. API 收口

替换映射：

| 旧 | 新 |
|----|----|
| `(let ((helixel--in-replay t)) ...)`                  | `(helixel-with-replay 'dot edit ...)` |
| `helixel-with-replay-context` (旧 macro)              | 删除 / 改用新版 |
| 检查 `helixel--in-replay`                              | `(helixel-replaying-p)` |
| 检查 `helixel--inhibit-action-track`                   | `(helixel-replaying-p)` 一次判定 |
| `helixel--inhibit-repeat-record`                       | `(helixel-replaying-p)` |
| `helixel-mc--inhibit`                                  | `(eq (helixel-replay-origin) 'mc-fake)` |
| `helixel-mc-executing-command-for-fake-cursor`         | `(helixel-replay-fake-cursor)` |
| `helixel--search-advance-done`                         | ctx 字段，闭包内访问 |
| `helixel--advance-search-last-pos`                     | ctx 字段 |
| `helixel--advance-search-edge-seen`                    | ctx 字段 |

`helixel--repeat-permanent-flip` 保留为独立 buffer-local（它跨 replay 持久）。

## 4. record-edit 守门

```elisp
(defun helixel--record-edit (op &rest extra)
  (when (helixel-replaying-p)
    (cl-return-from helixel--record-edit nil))   ; 一行替代两个 inhibit
  ...)
```

action-tracking / history-push / jump-log-push 同理：所有
"replay 期间应跳过" 的逻辑用同一个判定。

## 5. 文件改动

| 改动 | 文件 |
|------|------|
| 新增 | `helixel-replay.el`（≈ 60 行：struct + macro + 谓词） |
| 删除 | `helixel--in-replay` 定义 + 旧 `helixel-with-replay-context` |
| 改 | `helixel-core.el` / `helixel-ring.el` / `helixel-repeat.el` / `helixel-search.el` / `helixel-mc-core.el` / `helixel-chain.el`（全部 inhibit 检查） |

依赖图：`helixel-replay` 只依赖 `helixel-edit`（phase 1 产物），
所有用到 replay 上下文的模块改为 `(require 'helixel-replay)`。

## 6. 验收

- [ ] `grep -E "helixel--(in-replay|inhibit-|search-advance-done|advance-search-(last-pos|edge-seen))"` 结果为空
- [ ] `grep "helixel-mc--inhibit"` 结果为空
- [ ] `grep "helixel-mc-executing-command-for-fake-cursor"` 结果为空
- [ ] AGENTS.md 中
  - "Zero-width search patterns ($, ^) and infinite loops" 段落删除
  - "Strategy all-buffer-fn recursion" 段落删除
  - 相关 Pitfall ≥ 3 条被消除
- [ ] 所有 repeat / chain / mc 测试通过
- [ ] 新增测试：`test/helixel-test-replay.el` 验证嵌套 replay / search 自旋检测

## 7. 步骤

1. 写 `helixel-replay.el` + 测试，确认 nested `helixel-with-replay` 正确
2. 替换 `--in-replay` 检查（最简单一批）
3. 替换 mc 两个 inhibit flag
4. search 自旋 3 个 global → ctx 字段（同时改 `recreate-search` 闭包签名）
5. 删除所有死代码 + 旧 macro
6. 跑测试
