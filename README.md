# On My Way · 学习笔记博客

战个未来吧 · 学习过程的整理与记录：Python 基础、LeetCode HOT100、Agent、RAG、Prompt Engineering。

- **站点**：https://tuanzi-wow.cn （境内 ECS 自托管：Hugo 静态站 + FastAPI 检索统计）
- **内容**：`content/` 下的 Markdown，分类见 `config.toml` 的 `taxonomies` 与各分区 `_index.md`
- **写新笔记**：`hugo new content/python/xxx.md`（archetypes 模板已强制 front matter）
- **架构与运维**：`deploy/` 为服务器安装与部署脚本，`scripts/` 为各服务源码；`docs/plan.md` 记技术路线与约束，`docs/runbook.md` 记回滚/重建/备份还原（本地留存）
- **更新链路**：push 后 60s 内自动构建发布（轮询兜底），新增内容秒级可搜
