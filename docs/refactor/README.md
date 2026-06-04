# helixel-mode 大重构总览

> 目标：彻底降低概念数量、消除隐式状态、把 multi-cursor / chain / repeat /
> action 这四套子系统的复杂度压到一半以下。
> **不维护向后兼容**——老 API 直接删除，调用方一并改完。

---

## 0. 总原则

每一个 phase 都必须遵守以下规则，违反任何一条都不能合入：

1. **可单独执行 / 单独回滚**
   每个 phase 自成一个 PR，自带新增/重写的测试。
   完工时 `rm -f *.elc && make compile && make test && make lint` 必须全绿。

2. **状态只减不增**
   每个 phase 必须减少 `defvar` / `defvar-local` 总数（或不变）。
   新增 buffer-local 必须挂在已有的 session struct 上，不允许散落。

3. **advice 黑名单**
   `advice-add` 只允许出现在两个文件：
   - `helixel-shims.el`（第三方模式集成）
   - `helixel-state.el`（劫持 `keyboard-quit`，且仅此一处）

   helixel 自己的命令之间禁止用 advice 互相耦合。
   原 `helixel-mc-integrate.el` 中的全部 `advice-add` 必须被改写成
   显式 hook 通知（`run-hook-with-args`）。

4. **隐式状态机黑名单**
   禁止用 `post-command-hook` / `pre-command-hook` "探测"调用方发生了什么。
   调用方必须主动 `run-hook-with-args` 或直接调用 API。
   现有的 6 处 hook 探测，phase 2~5 会逐一消除。

5. **decide / execute 分离**
   凡是会 prompt 用户、读 register、读 char 的命令，必须把"决策结果"
   显式写进 `helixel-edit.payload`。replay 阶段（`.`、`,`、mc fake-cursor）
   只读 payload，从不重新 prompt。

6. **命名一致**
   `event` / `transaction` / `tx` / `edit` / `entry` 必须只用一个词指代同一概念。
   见 phase 7 的术语表。

---

## 1. Phase 总览（依赖 + 顺序）

```
Phase 1 ── 切分 event struct，抽出 grouped-ring
     │
     ├─→ Phase 2 ── 统一 replay context / 删除 6 个 inhibit flag
     │       │
     │       └─→ Phase 3 ── decide/execute 分离（所有 prompt 命令）
     │              │
     │              ├─→ Phase 4 ── repeat strategy 用 cl-defgeneric 重写
     │              │
     │              ├─→ Phase 5 ── chain 改成显式 state struct + hook
     │              │
     │              └─→ Phase 6 ── multi-cursor 彻底瘦身（删 25KB 胶水）
     │
     └─→ Phase 7 ── 命名 / 文件粒度 / 文档收尾
```

Phase 1、2 可并行；Phase 3 是 4/5/6 的前置（因为 mc 瘦身依赖 payload 通道）；
Phase 7 是收尾，不改语义。

预计删除量（估算，按当前 14k 行算）：

| Phase | 净减少行数 | 删除/重写文件 |
|-------|-----------|--------------|
| 1     | -300      | `helixel-ring.el` 拆分 |
| 2     | -400      | `helixel-core.el` / `helixel-repeat.el` / `helixel-search.el` |
| 3     | -600      | `helixel-editing.el` / `helixel-surround.el` / `helixel-search.el` |
| 4     | -500      | `helixel-repeat*.el` 合并并重写 |
| 5     | -400      | `helixel-chain.el` 重写 |
| 6     | -1500     | `helixel-mc-integrate.el` 大幅瘦身 |
| 7     | -200      | 文档 + 改名 |
| **合计** | **≈ -3900 行（≈ 28%）** | |

---

## 2. Phase 文档索引

- [PHASE-1-events-and-rings.md](PHASE-1-events-and-rings.md)
- [PHASE-2-replay-context.md](PHASE-2-replay-context.md)
- [PHASE-3-decision-payload.md](PHASE-3-decision-payload.md)
- [PHASE-4-repeat-strategy.md](PHASE-4-repeat-strategy.md)
- [PHASE-5-chain.md](PHASE-5-chain.md)
- [PHASE-6-multicursor.md](PHASE-6-multicursor.md)
- [PHASE-7-naming-cleanup.md](PHASE-7-naming-cleanup.md)

---

## 3. 验收清单（全部 phase 完工后）

- [ ] `defvar` / `defvar-local` 总数 ≤ 25（当前 ≈ 50）
- [ ] `advice-add` 调用点 ≤ 8（当前 19，且只在 shims / state 出现）
- [ ] `*-hook` 注册点 ≤ 8（当前 ≥ 12）
- [ ] `helixel-mc-integrate.el` ≤ 10KB（当前 25KB）
- [ ] 不再出现 `--last-event` vs `--last-tx` 同义异名
- [ ] AGENTS.md 的 "Pitfalls" 一节砍掉至少 5 条（因为坑被消除）
- [ ] 测试数量 ≥ 当前数量（≥ 817），所有原行为通过新测试覆盖
