# 个人价值投资系统

英文名：Personal Value Investing System  
仓库名：`personal-value-investing-system`

这是一个面向个人长期投资学习的研究与决策系统。它把公司研究、估值、市场隐含预期、五年情景、决策冻结和复盘串成一条可解释、可质疑、可重放的链路。

主流程：

`证据 → 本人临时判断 → 公司与模型路由 → 三情景估值 → 五年预期收益 → 冻结决策卡 → 事件／季度复盘`

## 当前阶段

本轮是从零重建的工程底座，不沿用旧仓库代码。当前已经建立：

- 置顶聊天的结构化迁移稿；
- 产品需求、架构、模型路由和历史时点回测契约；
- 公司研究、本人临时判断、冻结决策卡和复盘模板；
- 一个只使用标准库的确定性计算内核，可计算现金流内部收益率、目标买入价格、情景结果、最大回撤和时点数据资格；
- 自动化测试和持续集成入口。

当前状态与下一步只以 [Plan.md](Plan.md) 为准。

## 十分钟开始

1. 阅读 [PRD.md](PRD.md)，确认系统目标和不做事项。
2. 阅读 [docs/sources/chatgpt-business-pinned-chat.md](docs/sources/chatgpt-business-pinned-chat.md)，了解置顶聊天迁移范围。
3. 运行示例：

   ```bash
   PYTHONPATH=src python3 -m pvis analyze examples/demo-case.json
   ```

4. 运行测试：

   ```bash
   PYTHONPATH=src python3 -m unittest discover -s tests -v
   ```

## 目录

- `AGENTS.md`：项目级智能体规则。
- `Plan.md`：唯一状态权威、阶段计划和证据闭环。
- `STATUS.md`：便于快速查看的状态摘要。
- `PRD.md`：稳定产品需求与验收边界。
- `docs/`：来源迁移、架构、模型路由、回测契约和决策记录。
- `templates/`：研究、判断、决策和复盘模板。
- `src/pvis/`：确定性计算内核。
- `examples/`：不含真实投资结论的示例输入。
- `tests/`：自动化验证。

## 安全边界

- 不是荐股、自动交易或收益承诺系统。
- 不连接券商账户，不保存账户、完整持仓、资金金额或交易流水。
- 当前价格、财报、政策、税费、汇率等时效信息必须重新核实。
- 输出必须区分事实、计算、推断、个人偏好和待确认事项。
- 十五个百分点的长期目标收益仅是研究门槛之一，不能单独触发行动。

