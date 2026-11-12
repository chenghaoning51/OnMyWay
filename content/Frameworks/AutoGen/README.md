+++
title = "README"
slug = "readme"
weight = 31
categories = ["Frameworks", "AutoGen"]
tags = ["AutoGen", "Agent"]
description = "README相关学习笔记与实践要点。"
+++
# AutoGen 知识库与全景总结

本目录存放了关于 **AutoGen（多智能体对话协作框架）** 的全面知识总结、架构解析与工程落地实践指南。

## 核心文档索引

- 📄 **[AutoGen学习文档.md](./AutoGen学习文档.md)**（完整全景知识总结报告）
  - **第 1 章**：框架背景与发展演变（起源、AG2 与微软官方 v0.4+ 的历史分流）
  - **第 2 章**：核心设计范式（对话即计算 vs 现代化 Actor 模型与事件驱动）
  - **第 3 章**：AutoGen v0.4 分层架构深度剖析（`autogen-core`, `autogen-agentchat`, `autogen-ext`）
  - **第 4 章**：核心构件与关键抽象（Agents, Teams, TerminationConditions）
  - **第 5 章**：多智能体编排与协作拓扑模式（轮询、动态选择器 Selector、蜂群 Swarm、层级式）
  - **第 6 章**：旗舰级通用系统 Magentic-One 架构（双层推理循环 Ledgers 与专家矩阵）
  - **第 7 章**：关键机制（代码沙箱安全隔离、人机协同 HITL、工具调用）
  - **第 8 章**：可视化中枢 AutoGen Studio 原理与实战
  - **第 9 章**：横向对比（AutoGen vs LangGraph vs CrewAI 全维度矩阵）
  - **第 10 章**：工业级代码实战样例（RoundRobin、Selector+代码沙箱、经典 v0.2/AG2 存照）
  - **第 11 章**：生产落地避坑指南与最佳实践
