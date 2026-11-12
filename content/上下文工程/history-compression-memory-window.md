+++
title = '上下文工程：历史压缩、记忆管理、上下文窗口规划（2.1）'
slug = "history-compression-memory-window"
date = 2026-09-14T00:00:00+08:00
lastmod = 2026-09-14T00:00:00+08:00
weight = 8
categories = ['上下文工程']
tags = ['Context Engineering', 'Compaction', 'Memory', 'Context Window']
description = '历史压缩、记忆管理、上下文窗口规划相关学习材料与阅读顺序整理。'
+++

# 上下文工程：历史压缩、记忆管理、上下文窗口规划（2.1）

下列材料覆盖「历史压缩 / 记忆管理 / 上下文窗口规划」。

## 系统教程（三块都覆盖）

| 材料 | 链接 | 覆盖点 |
|---|---|---|
| 大模型上下文工程权威指南（yeasy） | https://yeasy.gitbook.io/context_engineering_guide/ | 第 4 章记忆架构；第 6 章压缩与窗口 |
| 6.3 对话历史管理 | https://yeasy.gitbook.io/context_engineering_guide/di-er-bu-fen-he-xin-ji-shu-yu-ce-le/06_compress/6.3_conversation_history | 滑动窗口、对话压缩、分层管理 |
| 6.4 上下文窗口优化策略 | https://yeasy.gitbook.io/context_engineering_guide/di-er-bu-fen-he-xin-ji-shu-yu-ce-le/06_compress/6.4_window_optimization | Compaction、记忆刷写、检查点 |
| 指南目录（GitHub） | https://github.com/yeasy/context_engineering_guide/blob/main/SUMMARY.md | 全书目录 |
| 第 3 章 上下文工程 | https://juejin.cn/post/7677865735721975817 | 3.1 Token 预算；3.2 历史管理；3.4 记忆分层 |
| 上下文工程生产落地指南 | https://juejin.cn/post/7633633244708438050 | 3.1 窗口容量规划；压缩摘要代码 |
| M09 Context Engineering（李文周） | https://liwenzhou.com/courses/ai-agent/09-context-engineering/ | Token 预算门控、历史压缩、结构化笔记 |

## 官方与白皮书

| 材料 | 链接 | 覆盖点 |
|---|---|---|
| Anthropic · Effective context engineering for AI agents | https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents | compaction、structured note-taking、sub-agent |
| Claude · Compaction | https://platform.claude.com/docs/en/build-with-claude/compaction | 服务端自动压缩 API |
| Google · Context Engineering: Sessions & Memory | https://www.kaggle.com/whitepaper-context-engineering-sessions-and-memory | Session 压缩、记忆生命周期、历史裁剪 |
| Google ADK · Context Compaction | https://google.github.io/adk-docs/context/compaction/ | 滑动窗口摘要、interval / overlap |
| Lance Martin · Context Engineering for Agents | http://rlancemartin.github.io/2025/06/23/context_engineering/ | Write / Select / Compress / Isolate |
| 上下文工程（LangChain 博客中文整理） | https://juejin.cn/post/7602850166731292681 | 四大策略中文版 |
| 上下文工程（lidaxia 译文） | https://blog.lidaxia.io/2025/07/07/context-engineering-from-langchain/ | LangChain 原文翻译 |

## 历史压缩

| 材料 | 链接 |
|---|---|
| 历史压缩的艺术 | https://juejin.cn/post/7669646561668284450 |
| 第 7 章：上下文压缩与优化技术 | https://juejin.cn/post/7667537840745709610 |
| 第 7 章：上下文工程（Write / Select / Compress / Isolate） | https://waylandz.com/ai-agent-book/%E7%AC%AC07%E7%AB%A0-%E4%B8%8A%E4%B8%8B%E6%96%87%E5%B7%A5%E7%A8%8B/ |
| 6.1 信息密度与压缩原理 | https://yeasy.gitbook.io/context_engineering_guide/di-er-bu-fen-he-xin-ji-shu-yu-ce-le/06_compress/6.1_compression_principles |
| Codex：从 Compaction 到硬切窗口 | https://juejin.cn/post/7680581898923491370 |

## 记忆管理

| 材料 | 链接 |
|---|---|
| LLM 记忆管理三剑客：截断、总结、检索 | https://juejin.cn/post/7680552737289715731 |
| 走进 AI Agent 第三篇：让 Agent 记住你 | https://juejin.cn/post/7682394398210932763 |
| 智能体 AI 权威指南 · 3.2 短期记忆管理 | https://yeasy.gitbook.io/agentic_ai_guide/di-yi-bu-fen-dan-ti-zhi-neng-jia-gou/03_memory/3.2_short_term_memory |
| 3.6 上下文工程（记忆与调度） | https://yeasy.gitbook.io/zhi-neng-ti-ai-quan-wei-zhi-nan-agenticaiguide/di-yi-bu-fen-dan-ti-zhi-neng-jia-gou/03_memory/3.6_context_engineering |
| Agent 上下文爆炸：从全量塞入到智能记忆管理 | https://openeuler.csdn.net/6a1c2e6210ee7a33f2768a96.html |

## 上下文窗口规划

| 材料 | 链接 |
|---|---|
| 从零开始理解大模型（八）：上下文窗口 | https://bbs.huaweicloud.com/blogs/476789 |
| 有效的 Context 工程（少数派） | https://sspai.com/post/103243 |
| 上下文工程是什么？ | https://juejin.cn/post/7674095753217572900 |
| 上下文越大，AI 越容易忘事 | https://juejin.cn/post/7679716885453815818 |

## 带代码的实现材料

| 材料 | 链接 | 覆盖点 |
|---|---|---|
| baby-agent 第 5 章 | https://github.com/baby-llm/baby-agent/blob/main/ch05/README.md | Truncate / Offload / Summarize；含 2.1 截断策略 |
| HelloAgents 上下文工程指南 | https://github.com/jjyaoao/HelloAgents/blob/main/docs/context-engineering-guide.md | HistoryManager、压缩阈值、保留最近 N 轮 |
| 原生 NodeJS 维护 Agent Memory | https://juejin.cn/post/7681142626944761910 | 滑动窗口 + 摘要压缩双阈值 |
| how-claude-code-works · 五级压缩管线 | https://github.com/Windy3f3f3f3f/how-claude-code-works/blob/main/en/docs/03-context-engineering.md | Tool Result 裁剪 → Autocompact |
| Claude Code vs OpenCode · 四种记忆策略 | https://github.com/0xtresser/Claude-Code-VS-OpenCode/blob/main/ZH/%E7%AC%AC20%E7%AB%A0_%E4%B8%8A%E4%B8%8B%E6%96%87%E5%B7%A5%E7%A8%8B/20.2_%E5%9B%9B%E7%A7%8D%E8%AE%B0%E5%BF%86%E7%AD%96%E7%95%A5.md | JIT / compaction / notes / sub-agents |

## 建议阅读顺序

1. Anthropic 长文（原理）
2. yeasy 指南第 4 / 6 章（系统）
3. 掘金第 3 章（窗口预算数字）
4. baby-agent ch05 或李文周 M09（实现）
