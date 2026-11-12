+++
title = "Overview"
slug = "overview"
weight = 50
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Overview相关学习笔记与实践要点。"
+++
The situation that fits middleware

- Tracking agent behavior with logging, analytics, and debugging.
- Transforming prompts, [tool selection](https://docs.langchain.com/oss/python/langchain/middleware/built-in#llm-tool-selector), and output formatting.
- Adding [retries](https://docs.langchain.com/oss/python/langchain/middleware/built-in#tool-retry), [fallbacks](https://docs.langchain.com/oss/python/langchain/middleware/built-in#model-fallback), and early termination logic.
- Applying [rate limits](https://docs.langchain.com/oss/python/langchain/middleware/built-in#model-call-limit), guardrails, and [PII detection](https://docs.langchain.com/oss/python/langchain/middleware/built-in#pii-detection).

# The agent loop

the core agent loop involves calling a model ,letting it choose tools to execute,and then finishing when it calls no more tools
![Core agent loop diagram](https://mintcdn.com/langchain-5e9cc07a/Tazq8zGc0yYUYrDl/oss/images/core_agent_loop.png?fit=max&auto=format&n=Tazq8zGc0yYUYrDl&q=85&s=ac72e48317a9ced68fd1be64e89ec063)

Middleware在其中的作用:
exposes hooks before and after each of these steps

![Middleware flow diagram](https://mintcdn.com/langchain-5e9cc07a/RAP6mjwE5G00xYsA/oss/images/middleware_final.png?fit=max&auto=format&n=RAP6mjwE5G00xYsA&q=85&s=eb4404b137edec6f6f0c8ccb8323eaf1)

# Use middleware inside a LangGraph workflow

将整个agent作为更大的StateGraph的子图或者节点
适用场景:
当拓扑结构不再是简单的循环直到结束时
例如:路由到多个agents之一并且对输入进行分类,并发工作,或者通过确定性步骤将agent调用串联起来

`HumanInTheLoopMiddleware`通过 tool's `name`匹配
`@tool`修饰符从函数名获取器名称
