# Phase 6 — Multi-Cursor 彻底瘦身

## 1. 现状问题

`helixel-mc-integrate.el` 是 25KB 的"胶水代码黑洞"，主要做 4 件事：

1. **per-cursor 状态注册**：手工维护 `helixel-mc-cursor-vars` 列表，新增任何
   buffer-local 都隐式增加 mc 的复杂度（AGENTS.md 专门告诫 `mark-active`
   绝不能加进去）。
2. **prompt 命令的 advice 网**：见 phase 3，每个 prompt 命令配一条 advice
   从 real cursor 偷决策→广播给 fake。phase 3 消除大半。
3. **chain-end advice + repeat-edit 钩子函数 `helixel-repeat-edit-function`**：
   phase 4/5 完成后这两个都可以删。
4. **visual state 同步**（`helixel-mc--sync-visual-state`）+ insert prepos
   函数（`helixel-mc--prepos-region-begin` 等 6 个）+ 各种 substitute alist。
   phase 3 把 insert 也 decide/execute 化后，prepos 完全消失。

## 2. 目标

### 2.1 per-cursor 状态：cl-struct 化

```elisp
(cl-defstruct helixel-cursor
  point mark mark-active                 ;; position
  kill-ring kill-ring-yank-pointer       ;; clipboard
  last-edit live-edit pending-sel        ;; replay
  active-search                          ;; search
  action-pos event-ring                  ;; ; cycling
  replay-permanent-flip)                 ;; - .
```

- fake-cursor overlay 上挂一个 `helixel-cursor` 实例（property `'state`）。
- `helixel-mc--enter-cursor` / `--leave-cursor` 用一对宏 swap struct 字段
  与 buffer-local 变量：
  ```elisp
  (cl-defmacro helixel-mc-with-cursor (cursor &rest body)
    `(let ((state (overlay-get ,cursor 'state)))
       (cl-letf* (...每个 cursor 字段 ↔ buffer-local var...)
         ,@body)
       (helixel-mc--save-state-back ,cursor)))
  ```
- 新增 buffer-local 不再需要登记——只要加进 struct 即可。

### 2.2 policy 反转

| 现在 | 新 |
|------|----|
| 默认 `all`，用 `mapatoms` 在 helixel.el 末尾把所有 `helixel-*` 命令打 `'multiple-cursors` 标记 | 默认 `real-only`，命令必须在 `define-command` 时 `:mc-policy 'all` 显式声明 |

好处：调试时一眼看出"哪个命令会广播"。`helixel-mc--whitelist-helixel-commands`
（mapatoms 扫描）整段删除。

### 2.3 dispatcher 单一职责

```elisp
(defun helixel-mc--post-command ()
  ;; 不再考虑 substitute / prepos / advice 协调
  ;; 只做一件事：对每个 fake，重放 this-command 决策
  (when (helixel-mc--should-broadcast this-command)
    (let ((edit helixel--last-edit))   ;; phase 3 后必非 nil
      (undo-amalgamate-change-group
        (dolist (fake (helixel-mc-all-cursors))
          (helixel-mc-with-cursor fake
            (helixel-with-replay 'mc-fake edit
              (helixel--execute-edit edit))))))))
```

### 2.4 mc 整体文件结构

| 文件 | 行数（目标） |
|------|-------------|
| `helixel-mc-core.el`     | ≤ 400（cursor struct + overlay 管理 + dispatcher） |
| `helixel-mc-spawn.el`    | ≤ 600（spawn 命令：add-here / edit-lines / mark-next） |
| `helixel-mc-integrate.el`| ≤ 200（只剩 hook 注册和 cleanup） |
| 删除 `helixel-mc-targets.el` | 合并进 spawn |

总规模从 ~120KB 降到 ~50KB。

## 3. 删除清单

- `helixel-mc--inhibit`（phase 2 已处理）
- `helixel-mc-executing-command-for-fake-cursor`（phase 2 已处理）
- `helixel-mc--fake-substitute-alist`（phase 3 处理）
- `helixel-mc--last-replace-char` / `--last-surround-pair`（phase 3 处理）
- 全部 `helixel-mc--*-advice` 函数 + advice-add（phase 3/5 处理）
- `helixel-mc--prepos-*` 6 个函数（phase 3 处理）
- `helixel-mc--sync-visual-state` + `helixel--prev-state` —— 改成
  visual-enter/exit 命令 `:mc-policy 'real`，用 `:after` hook 调
  `helixel-mc--mirror-mark-active`
- `helixel-mc-cursor-vars` + `helixel-mc-register-cursor-var` + 文档
- `helixel-mc--whitelist-helixel-commands`（mapatoms 扫描）
- `helixel-repeat-edit-function`（phase 4 用 method 取代）

## 4. 验收

- [ ] `helixel-mc-integrate.el` ≤ 10KB
- [ ] `grep -n "advice-add" helixel-mc-*.el` 输出为空
- [ ] `grep -n "helixel-mc-register-cursor-var" *.el` 输出为空
- [ ] `grep -n "mapatoms" *.el` 输出为空（或仅注释）
- [ ] `helixel-cursor` struct 是唯一的 fake state 入口
- [ ] AGENTS.md 中 Multi-cursor 相关 Pitfall 段：
  - "Multi-cursor (mc) — fake cursor model" 重写
  - "`mark-active` must NOT be in helixel-mc-cursor-vars" Pitfall 删除
  - "Multi-cursor + `.` / `q` integration" 改写为基于 method
- [ ] 所有 `test/helixel-test-mc*.el` 测试通过

## 5. 步骤

> 严格按顺序，phase 3/4/5 必须先完成。

1. 引入 `helixel-cursor` struct，并行于旧 cursor-vars 系统
2. 改 dispatcher 走 struct + `helixel-mc-with-cursor` 宏
3. 删除 `helixel-mc-cursor-vars` 注册体系
4. policy 反转：`define-command/operator` 增加 `:mc-policy`，默认 real-only
5. 删除 mapatoms 白名单
6. 合并 `helixel-mc-targets.el` → `helixel-mc-spawn.el`
7. 清理 integrate.el，只保留 hook 注册（chain-recorded-functions、
   state-change、cleanup-on-mode-off）
