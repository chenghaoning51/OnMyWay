+++
title = "Retrieval"
slug = "retrieval"
weight = 70
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Retrieval相关学习笔记与实践要点。"
+++
Two limitations of LLM:

1. finite context
2. Static Knowledge

RAG(检索增强生成)

# Building a knowledge base

A repository of documents of structured data
使用LangChain's document loaders and vector stores 来建立你自己的知识库
如果你已经有知识库,你不需要重建,你只需要

- Connect it as a tool for agent in agentic RAG
- Query it and supply the retrieved content as context to the LLM [(2-Step RAG)](https://docs.langchain.com/oss/python/deepagents/retrieval#2-step-rag)

## From retrieval to RAG

## Retrieval pipeline

![image-20260922210616005](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260922210616005.png)

Document loaders,text splitters,Embedding models,vector stores,retrievers

# RAG architectures

| Architecture    | Description                                                  | Control  | Flexibility | Latency    | Example Use Case                                  |
| :-------------- | :----------------------------------------------------------- | :------- | :---------- | :--------- | :------------------------------------------------ |
| **2-Step RAG**  | Retrieval always happens before generation. Simple and predictable | ✅ High   | ❌ Low       | ⚡ Fast     | FAQs, documentation bots                          |
| **Agentic RAG** | An LLM-powered agent decides *when* and *how* to retrieve during reasoning | ❌ Low    | ✅ High      | ⏳ Variable | Research assistants with access to multiple tools |
| **Hybrid**      | Combines characteristics of both approaches with validation steps | ⚖️ Medium | ⚖️ Medium    | ⏳ Variable | Domain-specific Q&A with quality validation       |

## 2-step RAG

![image-20260922210932476](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260922210932476.png)

## Agentic RAG

![image-20260922211016040](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260922211016040.png)

由LLM来决定是否需要检索和如何检索信息

```py
import requests
from langchain.tools import tool
from langchain.chat_models import init_chat_model
from langchain.agents import create_agent


@tool
def fetch_url(url: str) -> str:
    """Fetch text content from a URL"""
    response = requests.get(url, timeout=10.0)
    response.raise_for_status()
    return response.text

system_prompt = """\
Use fetch_url when you need to fetch information from a web-page; quote relevant snippets.
"""

agent = create_agent(
    model="claude-sonnet-4-6",
    tools=[fetch_url], # A tool for retrieval
    system_prompt=system_prompt,
)
```

## Hybrid RAG

![image-20260922211229661](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260922211229661.png)


结合了前两者的优点,核心组件包括:

查询增强:修改question来提高检索质量,这可能包括重写不清晰的查询、生成多个变体，或使用其他上下文扩展查询。

检索验证:评估检索到的资料是否充足

答案验证:检查生成的答案准确性,完整性和于源文件的一致性

此架构适用于

- 存在模糊或描述不详的查询的应用场景
- 需要验证或质量控制步骤的系统
- 涉及多个数据源或迭代优化的工作流