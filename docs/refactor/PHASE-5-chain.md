# Phase 5 — Chain 重写：显式状态机 + Hook 通知

## 1. 现状问题

`helixel-chain.el` 是项目里最脆弱的状态机：

1. 用 **7 个 buffer-local** 表达录制状态：
   `--repeat-chaining` / `--repeat-chain-init-ctx` / `--repeat-chain-init-bounds` /
   `--chain-move-keys` / `--chain-edit-keys` / `--chain-in-edit-phase` /
   `--chain-last-event-snapshot`
2. **"第一次 edit 发生了"** 靠 `post-command-hook` 比较
   `(eq helixel--last-edit helixel--chain-last-event-snapshot)` 探测。
   一旦中间穿插一个改 `--last-event` 但其实不是 edit 的命令（很容易遗漏）就出错。
3. 探测后还要**回溯**：`(push (car helixel--chain-move-keys) helixel--chain-edit-keys)`
   把已经收进 move 桶的那一键挪到 edit 桶——典型异步状态机反模式。
4. chain-end 用 advice 通知 mc（`helixel-mc--chain-end-advice`），
   是 phase 0 原则 "禁止 helixel-自己 advice 自己" 的最大违反者。
5. chain runner 用 `execute-kbd-macro` 重放 edit-keys，这条路依赖 prompt 被
   非 interactive 模式自动吞掉——phase 3 完成后正好可以彻底改成
   "顺序 dispatch 子 edits"，更稳。

## 2. 目标设计

```elisp
(cl-defstruct helixel-chain-session
  start-sel       ;; helixel-edit's sel at start
  start-bounds    ;; (beg-marker . end-marker)
  phase           ;; 'move | 'edit
  move-keys       ;; vector
  child-edits)    ;; (list helixel-edit) — phase 3 后存子 edit, 不再存 keys

(defvar-local helixel--chain-session nil
  "Single buffer-local container, or nil when not recording.")
```

**关键变化**：phase 3 完成后，每个子 edit 都已被 `helixel--record-edit`
单独 commit 成 `helixel-edit`。chain 不必录键，**直接收集子 edits**：

```elisp
(defun helixel--record-edit (op &rest extra)
  (let ((edit (helixel--make-edit op ...)))
    (when helixel--chain-session
      ;; first edit: switch phase
      (setf (helixel-chain-session-phase helixel--chain-session) 'edit)
      (push edit (helixel-chain-session-child-edits helixel--chain-session)))
    (unless (helixel-replaying-p)
      (helixel--commit-as-last edit))
    edit))
```

这样：
- **不再需要 post-command-hook 探测**——是不是 edit，`record-edit` 自己最清楚。
- **不再需要 move/edit-key 回溯**——move-keys 在 pre-command-hook 里只收 phase=='move 时的键。
- chain replay 变成：先 replay move-keys（一次），然后顺序调用每个子 edit 的 runner。

## 3. mc 通信改成 hook

```elisp
(defvar helixel-chain-recorded-functions nil
  "Abnormal hook run with one arg, the new chain `helixel-edit'.
Run synchronously inside `helixel-repeat-chain-end' AFTER the
chain is committed to `helixel--last-edit'.")

;; chain-end 末尾:
(run-hook-with-args 'helixel-chain-recorded-functions chain-edit)
```

mc-integrate.el 改为：

```elisp
(add-hook 'helixel-chain-recorded-functions
          #'helixel-mc--broadcast-chain-edit)
```

`helixel-mc--chain-end-advice` 删除，`advice-add 'helixel-repeat-chain-end`
删除。

## 4. 状态压缩

| 旧 | 新 |
|----|----|
| 7 个 buffer-local                | 1 个 buffer-local（session struct） |
| `--chain-pre-cmd` 收 move/edit 两桶 | `--chain-pre-cmd` 只收 move-keys |
| `--chain-post-cmd` 探测第一次 edit | 删除，由 `record-edit` 切相 |
| `--chain-last-event-snapshot`     | 删除 |
| `execute-kbd-macro edit-keys`     | 顺序 dispatch 子 edits |

## 5. preview & repeat 协议

phase 4 完成后：
- chain 通过 `cl-defmethod helixel-replay-apply ((kind t) (op (eql chain)) ...)`
  显式表达 apply = "apply each child-edit"。
- advance = sel 的 kind advance + replay move-keys。
- dry-run = 只 recreate selection、不 dispatch children。

## 6. 文件改动

| 文件 | 改动 |
|------|------|
| `helixel-chain.el` | 重写，行数从 ~360 减到 ~200 |
| `helixel-mc-integrate.el` | 删除 advice + advice 函数（≈ 50 行减少） |
| `helixel-repeat-chain.el`（phase 4） | 实现 chain method |

## 7. 验收

- [ ] `grep -n "advice-add 'helixel-repeat-chain"` 输出为空
- [ ] `grep -n "helixel--chain-" helixel-chain.el | wc -l` ≤ 8（当前 ~25）
- [ ] `grep -n "execute-kbd-macro" *.el` 仅出现在 register macro 实现处
- [ ] AGENTS.md "Multi-cursor + `.` / `q` integration" Pitfall 改写为
      "chain 通过 child-edit 列表替放，不依赖 kmacro"
- [ ] `test/helixel-test-chain.el` 全部通过

## 8. 步骤

1. 引入 `helixel-chain-session` struct，并行存在于旧 var 之上（不破坏）
2. 改 `record-edit` 在 chain 期间 push 子 edit + 切 phase
3. 改 chain runner 用子 edits dispatch；保留 kmacro fallback 一周
4. 验证测试通过后，**删除所有旧 buffer-local + kmacro fallback**
5. 新增 `helixel-chain-recorded-functions` hook；mc 改 hook
6. 删除 chain-end advice
