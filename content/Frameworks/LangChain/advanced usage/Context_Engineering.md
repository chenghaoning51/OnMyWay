+++
title = "Context Engineering"
slug = "context-engineering"
weight = 30
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Context Engineering相关学习笔记与实践要点。"
+++
# Overview

构建agent的难点在于使他们足够可靠
即时他们在原型阶段往往会表现得很好

## Why do agent fails

LLM调用采取了错误的措施或者没有按照预期执行,原因:

1. LLM能力不够
2. 正确的context没有传递给LLM

更多情况是后者

## The agent loop

two main step2:

1. Model call: calls the LLM with a prompt and available tools, returns either a  response or a request to execute tools
2. Tool execution: execute the tools that LLM requested,returns tool results

![Core agent loop diagram](https://mintcdn.com/langchain-5e9cc07a/Tazq8zGc0yYUYrDl/oss/images/core_agent_loop.png?fit=max&auto=format&n=Tazq8zGc0yYUYrDl&q=85&s=ac72e48317a9ced68fd1be64e89ec063)

What can you control:


| Context Type                                                 | What You Control                                             | Transient or Persistent |
| :----------------------------------------------------------- | :----------------------------------------------------------- | :---------------------- |
| **[Model Context](https://docs.langchain.com/oss/python/langchain/context-engineering#model-context)** | What goes into model calls (instructions, message history, tools, response format) | Transient               |
| **[Tool Context](https://docs.langchain.com/oss/python/langchain/context-engineering#tool-context)** | What tools can access and produce (reads/writes to state, store, runtime context) | Persistent              |
| **[Life-cycle Context](https://docs.langchain.com/oss/python/langchain/context-engineering#life-cycle-context)** | What happens between model and tool calls (summarization, guardrails, logging, etc.) | Persistent              |

## Data sources

| Data Source         | Also Known As        | Scope               | Examples                                                     |
| :------------------ | :------------------- | :------------------ | :----------------------------------------------------------- |
| **Runtime Context** | Static configuration | Conversation-scoped | User ID, API keys, database connections, permissions, environment settings |
| **State**           | Short-term memory    | Conversation-scoped | Current messages, uploaded files, authentication status, tool results |
| **Store**           | Long-term memory     | Cross-conversation  | User preferences, extracted insights, memories, historical data |

## How it works

Using middleware:

- update context
- Jump to a different step in the agent lifecycle



# Model context

Instructions,available tools,which model to use,output format.

- System prompt
- Messages:conversation history
- Tools
- Model
- Response format

## System prompt

Successful agents draw on memories, preferences, and configuration to provide the right instructions for the current state of the conversation.

- Access message count or conversation context from state
- Access user preferences from long-term memory
- Access user ID or configuration from Runtime Context

## Message

Make up the prompt that is sent to the LLM

分为state,store,Runtime context

## Tools

### Defining tools

name,description(docstring),argument name, argument description

```py
from langchain.tools import tool

@tool(parse_docstring=True)
def search_orders(
    user_id: str,
    status: str,
    limit: int = 10
) -> str:
    """Search for user orders by status.

    Use this when the user asks about order history or wants to check
    order status. Always filter by the provided status.

    Args:
        user_id: Unique identifier for the user
        status: Order status: 'pending', 'shipped', or 'delivered'
        limit: Maximum number of results to return
    """
    # Implementation here
    pass
```

### Selecting tools

从分为从三个数据源来组织上下文

## Model

根据三种数据源中的各种数据来选择合适的模型



## Response format

### defining formats

Schema definitions guide the model. Field names, types, and descriptions specify exactly what format the output should adhere to.

```
from pydantic import BaseModel, Field

class CustomerSupportTicket(BaseModel):
    """Structured ticket information extracted from customer message."""

    category: str = Field(
        description="Issue category: 'billing', 'technical', 'account', or 'product'"
    )
    priority: str = Field(
        description="Urgency level: 'low', 'medium', 'high', or 'critical'"
    )
    summary: str = Field(
        description="One-sentence summary of the customer's issue"
    )
    customer_sentiment: str = Field(
        description="Customer's emotional tone: 'frustrated', 'neutral', or 'satisfied'"
    )
```

### selecting format



# Tool context

Both read and write context

## Reads

大多数的工具不只是需要LLM传入的参数,需要从其他的数据源获得,主要是state,store,Runtime context

## Writes

update the memory

- Write to State to track session-specific information using Command:
- Write to Store to persist data across sessions:

# Life-cycle context

控制核心agent步骤之间发生的情况:拦截数据流以实现总结,安全护栏,日志记录等横切关注点

使用middleware:

- update context:修改state和存储以持久化更改,更新对话历史或者保存insights
- Jump in the lifecycle:根据上下文移动到Agent loop中的不同步骤(例如如果满足条件就跳过工具执行,或使用修改后的上下文重复model call)

## Example: Summarization

automatically condensing conversation history

LangChain offers built-in middleware for this:

```
from langchain.agents import create_agent
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="gpt-5.5",
    tools=[...],
    middleware=[
        SummarizationMiddleware(
            model="gpt-5.4-mini",
            trigger={"tokens": 4000},
            keep=("messages", 20),
        ),
    ],
)
```

When the conversation exceeds the token limit, `SummarizationMiddleware` automatically:

1. Summarizes older messages using a separate LLM call
2. Replaces them with a summary message in State (permanently)
3. Keeps recent messages intact for context