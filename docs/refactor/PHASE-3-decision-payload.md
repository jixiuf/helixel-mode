# Phase 3 — Decide / Execute 分离，所有决策入 payload

## 1. 现状问题

许多 helixel 命令在执行时通过 `read-char` / `read-string` /
`(interactive "c")` / `register-read-with-preview` 从用户取数据，
**然后立刻把数据用掉**——但没有显式把"用了什么数据"写进 edit payload。

后果：
1. `.` (dot-repeat) 必须依靠 hook 在 record 时偷偷把数据塞 payload，
   靠不同命令各自约定（一些塞 `:char`、一些塞 `:tag`、一些塞 `:kmacro`），
   schema 不统一。
2. multi-cursor 必须为**每一个 prompt 命令写一条 advice**，从 real cursor
   "事后偷"决策结果，再广播给 fake cursors。这正是
   `helixel-mc-integrate.el` 25KB 的主要来源：
   - `helixel-mc--replace-char-advice`
   - `helixel-mc--surround-add-advice`
   - `helixel-mc--surround-delete-advice`
   - `helixel-mc--surround-replace-advice`
   - find-char substitute alist（`helixel-find-next-char` → `helixel-find-repeat`）

3. chain 录制时只能录"用户按下的键"，把 prompt 也录进去，replay 时
   `execute-kbd-macro` 再次触发 prompt——靠 macro replay 的"non-interactive 模式"
   碰巧吞掉 prompt 才能工作。这条路一旦碰到非 self-insert 的 prompt 就崩。

## 2. 设计原则

**每个会读用户输入的命令必须分成两步**：

```elisp
(helixel-define-operator NAME ()
  :decide  (lambda () PLIST)      ;; 只读输入，不修改 buffer
  :execute (lambda (edit) ...)    ;; 用 edit.payload 修改 buffer
  ...)
```

- macro 自动生成的命令函数体大致是：
  ```elisp
  (let* ((decisions (funcall DECIDE))
         (edit (helixel--build-edit OP SEL :payload decisions)))
    (helixel--commit-edit edit)      ;; record + history push
    (funcall EXECUTE edit))
  ```
- replay (`.`) 只调 `EXECUTE`，从不调 `DECIDE`。
- mc fake-cursor 也只调 `EXECUTE`，**无需任何 advice**。
- chain 录制时一次走 DECIDE + EXECUTE，把 payload 累积进 chain edit；
  replay 时 chain runner 直接 dispatch 子 edit 的 EXECUTE，绕开 kmacro。

## 3. 受影响命令清单

| 命令 | 当前 prompt 方式 | 新 :decide payload key |
|------|-----------------|----------------------|
| `helixel-replace-char`       | `read-char`                | `:char` |
| `helixel-surround-add`       | `read-char` → delimiter   | `:delimiter` |
| `helixel-surround-add-tag`   | `read-string`             | `:tag-name` |
| `helixel-surround-delete`    | inferred from sel         | `:delimiter` |
| `helixel-surround-replace`   | `read-char` / tag prompt  | `:new-delimiter` / `:new-tag` |
| `helixel-find-next-char`     | `read-char`               | `:char :type next :dir +1` |
| `helixel-find-prev-char`     | 同上                       | `:dir -1` |
| `helixel-find-till-char`     | 同上                       | `:type till` |
| `helixel-find-prev-till-char`| 同上                       | `:type till :dir -1` |
| `helixel-yank-from-register` | `read-char` register name | `:register` |
| `helixel-paste-from-register`| 同上                       | `:register` |
| `helixel-execute-macro`      | `read-char` register      | `:register` |
| `helixel-search-forward`     | `read-string`              | `:pattern :dir +1` |
| `helixel-search-backward`    | 同上                       | `:dir -1` |

## 4. 受益代码（可删）

完成 phase 3 后，以下整段代码 **直接删除**：

- `helixel-mc-integrate.el` 中：
  - `helixel-mc--replace-char-advice` 及 advice-add
  - `helixel-mc--surround-add-advice` 及 advice-add
  - `helixel-mc--surround-delete-advice` 及 advice-add
  - `helixel-mc--surround-replace-advice` 及 advice-add
  - `helixel-mc--fake-substitute-alist`（find-char 不再需要 substitute，
    因为 fake 上跑同一个 EXECUTE 即可，char 已在 payload 里）
  - `helixel-mc--last-replace-char` / `--last-surround-pair` 等"事后偷数据"
    的 buffer-local（≈ 12 个变量）

预计：`helixel-mc-integrate.el` 从 25KB 缩到 ≤ 12KB。

## 5. macro 改动

`helixel-define-operator` / `helixel-define-command` 增加 `:decide` / `:execute`
两个 keyword，文档放进 `docs/MACROS.md`（更新原 Phase 3 已有的章节）。

旧的"直接写命令体 + 隐式 record-edit"模式 **全部废弃**。强制走
decide/execute 双闭包。

## 6. fake-cursor dispatcher 简化

新版 dispatch：

```elisp
(defun helixel-mc--post-command ()
  (when (helixel-mc--should-broadcast this-command)
    (let ((edit (helixel--last-committed-edit)))
      (helixel-mc--for-each-fake
        (helixel--execute-edit-payload edit)))))
```

不再需要：
- `(interactive "c")` substitute
- 任何 advice
- prepos 函数（`helixel-mc--prepos-region-begin` 等）—— `helixel-insert*`
  也走 decide/execute 模式，:decide 返回"开始位置应该是 region-begin"
  这种语义，:execute 把光标移到那里再进 insert state；fake 跑同样的
  execute 即可

## 7. 验收

- [ ] `grep -nE "advice-add" helixel-mc-integrate.el` 输出为空
- [ ] `grep -nE "interactive .c." helixel-*.el`（除 helixel-state.el 中的 i/a 之外）
  全部消失
- [ ] `helixel-mc-integrate.el` 行数减半
- [ ] 新增 ERT：
  - replace-char 不 prompt 时 replay
  - surround-add 在 mc 下不 prompt fake
  - find-next-char 在 mc 下不 prompt fake
- [ ] 旧测试全绿

## 8. 步骤

1. `helixel-define-operator` 增加 `:decide` / `:execute` keyword
   （旧的 body-style 暂时仍支持，让迁移可分批）
2. 转换 5 个最痛的命令：replace-char / surround-add / surround-delete /
   surround-replace / find-*-char
3. 在 mc-integrate.el 中删除对应 advice + 配套 buffer-local
4. 转换剩余 prompt 命令（register / search）
5. 删除旧 body-style 路径，强制 decide/execute
6. 更新 `docs/MACROS.md`
