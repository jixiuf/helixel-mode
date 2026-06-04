# Phase 4 — Repeat Strategy 用 cl-defgeneric 重写

## 1. 现状问题

- 多态调度分散在 **两张 plist 表**（kind registry + op registry）+
  `:repeat-advance` 三态字段（`nil` / `'line` / fn）+ 一堆 `(eq kind 'line)` / `(eq op 'chain)` 散落 if 分支。
- `helixel--repeat-line-pass` 内部还有一套二级解释（"op 是否移动了 point" 决定 bol/eol 处理），
  与 `:repeat-advance` 的语义耦合不清。
- preview 路径几乎是 strategy 的拷贝（`helixel--chain-preview-strategy` vs
  `helixel--chain-strategy-builder` 只差 `:apply` 改 `ignore`）。
- `helixel-repeat-prefix` struct + `helixel-repeat-strategy` struct + 4 个调度分支
  （`n-times` / `all-buffer` / `all-dir` / `preview`）实际是 2 个维度
  （范围、是否 dry-run）。

## 2. 目标

把整个 repeat 引擎重写成一个干净的 generic-dispatch + 单一调度循环：

```elisp
;; 单一 generic, dispatch on (kind, op).
(cl-defgeneric helixel-replay-advance (kind op edit ctx)
  "Move point to next target.  Return non-nil if advanced.")
(cl-defgeneric helixel-replay-apply   (kind op edit ctx)
  "Execute EDIT at point.")
(cl-defgeneric helixel-replay-scan    (kind op edit ctx scope)
  "Iterate advance+apply over SCOPE (:n N | :all-dir | :all-buffer).
Default method walks (advance, apply) until advance returns nil.")
```

- `kind` / `op` 用 `&context` specializer 派发（emacs `cl-generic` 内置能力）。
- line / search / chain 用专门方法覆盖默认实现，**不再有 plist 字段
  `:all-buffer-fn` / `:all-dir-fn` / `:strategy-builder`**。
- preview 不再是单独路径——`helixel-replay-apply` 内部判 `(helixel-replay-ctx-dry-run-p ctx)`，
  dry-run 时只 recreate selection、不执行 runner。

## 3. 新接口

```elisp
;; Public entry:
(defun helixel-repeat-edit (&optional prefix) ...)   ;; `.'
(defun helixel-repeat-selection (&optional prefix) ...) ;; `,'

;; 两者共用：
(defun helixel--repeat-dispatch (edit scope reverse-p dry-run-p)
  (helixel-with-replay 'dot edit
    :reverse-p reverse-p :dry-run-p dry-run-p
    (let ((kind (helixel-edit-kind edit))
          (op   (helixel-edit-op   edit)))
      (helixel-replay-scan kind op edit helixel--replay-ctx scope))))
```

`scope` ∈ `:once | (:n N) | :all-dir | :all-buffer`，
由 `helixel--decode-prefix` 从前缀算出。

## 4. 删除清单

| 删除 | 原因 |
|------|------|
| `helixel-repeat-strategy` struct + `make-/copy-/p`              | 由 generic + ctx 取代 |
| `helixel--build-strategy` / `--default-strategy-builder`        | 取代 |
| `helixel--repeat-all-buffer` / `--repeat-all-dir` / `--repeat-n` | 合成 `--repeat-dispatch` |
| `:repeat-advance` op 字段（nil/'line/fn）                       | 由 method 覆盖表达 |
| `:all-buffer-fn` / `:all-dir-fn` kind 字段                      | 由 method 覆盖表达 |
| `:strategy-builder` op 字段                                     | chain 用 method 覆盖 |
| `helixel--chain-preview-strategy`                               | dry-run flag 取代 |
| `helixel-repeat-edit-function` 钩子                             | mc 用 method 覆盖（phase 6） |

## 5. 新增 / 重写

| 文件 | 行数估算 |
|------|---------|
| `helixel-replay.el`（phase 2 已建）增加 generic + scan |
| `helixel-repeat.el` 重写为 thin entry point (≤ 200 行) |
| `helixel-repeat-line.el` line-kind 方法 (≤ 150 行) |
| `helixel-repeat-search.el` search-kind 方法 + 自旋检测 (≤ 150 行) |
| `helixel-repeat-chain.el` chain-op 方法 (≤ 100 行)（chain runtime 仍在 helixel-chain.el） |
| 删除 `helixel-repeat-strategy.el` |

## 6. 测试影响

- `test/helixel-test-repeat.el` 不变（黑盒测 `.` 行为）
- `test/helixel-test-chain.el` 不变
- 新增 `test/helixel-test-replay-method.el`：直接调 `helixel-replay-advance`
  验证派发正确

## 7. 验收

- [ ] `grep -n "helixel-repeat-strategy" *.el` 输出为空
- [ ] `grep -n "repeat-advance" *.el` 输出仅在文档/注释
- [ ] AGENTS.md "Design notes" 段重写：移除 `:repeat-advance` 三态描述
- [ ] AGENTS.md "Strategy all-buffer-fn recursion" Pitfall 删除
- [ ] kind registry 只剩 `:recreate` / `:display` / `:flip-dir-fn` 三个字段
- [ ] op registry 只剩 `:display` / `:runner` 两个字段

## 8. 步骤

1. 定义 generic + 默认 method，原 strategy 路径并存
2. line 方法迁移
3. search 方法迁移（顺带把 phase 2 的 ctx 字段用上）
4. chain method 迁移
5. dot/comma 入口改为新 dispatch；旧 strategy 路径删除
6. 删 `helixel-repeat-strategy.el`，更新 require 图
