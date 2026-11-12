+++
title = "学习顺序"
slug = "learning-order"
weight = 10
categories = ["Learning"]
tags = ["Learning Path"]
description = "学习顺序相关学习笔记与实践要点。"
+++
1.Prompt Engineering

1. CoT
2. few-shot
3. zero-shot

2.Context Engineering:

1. 写入策略

2. 检索:主要是RAG相关
               建立索引:

   1. 文档解析(转化为纯文本)
   2. chunking
   3. Embedding
   4. 存入向量数据库

   ​            生成:前部分类似于上面,
   多路召回
   重排序
   GraphRAG和LightRAG

   

3. 压缩策略
   借鉴Claude Code的五层压缩机制

4. 隔离策略



3.Agent

1. Function calling/Tool calling/Tool use
2. 记忆系统
3. 几种工作范式:React,Plan-and-Execute,Reflection
4. MCP: Host,Client,Server
5. Skills
6. A2A

4.Harness:

1. 上下文精细化
2. 工具系统的可控调用
3. 任务执行的全局编排
4. 记忆与状态的分层管理
5. 独立的评估和观测系统
6. 约束校验和失败恢复机制

5.Loop Engineering:

1. 自动化(Trigger)
2. worktree
3. Skill
4. Connector
5. Skill
6. Sub-agent

6.框架

1. LangChain
2. LangGraph
3. AutoGen
4. 等等