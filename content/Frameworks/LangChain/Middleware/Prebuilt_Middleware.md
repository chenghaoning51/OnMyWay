+++
title = "Prebuilt Middleware"
slug = "prebuilt-middleware"
weight = 60
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Prebuilt Middleware相关学习笔记与实践要点。"
+++
# Tool error

捕获工具异常,并且转化为`ToolMessage`,模型收到信息并且从中修复
**API reference:** [`ToolErrorMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/tool_error/ToolErrorMiddleware)

```
from langchain.agents import create_agent
from langchain.agents.middleware import ToolErrorMiddleware, ToolRetryMiddleware


def on_error(exc: Exception, request: ToolCallRequest) -> str | None:
    # Surface ValueError to the model so it can correct the input
    if isinstance(exc, ValueError):
        return f"`{request.tool_call['name']}` failed: {type(exc).__name__}. Fix the input and retry."
    # Let all other exceptions propagate (halts the run)
    return None


# Async-only usage
async def aon_error(exc: Exception, request: ToolCallRequest) -> str | None:
    if isinstance(exc, ConnectionError):
        return f"Tool `{request.tool_call['name']}` encountered a connection error."
    return None


agent = create_agent(
    model="gpt-5.5",
    tools=[search_tool, database_tool],
    middleware=[
        # Place retry inner so exceptions reach ToolErrorMiddleware after retries are exhausted
        ToolRetryMiddleware(max_retries=3, on_failure="error"),
        ToolErrorMiddleware(on_error=on_error, tools=["search_tool"]),
    ],
)

# Async-only: pass aon_error alone (do not pass on_error)
async_agent = create_agent(
    model="gpt-5.5",
    tools=[api_tool],
    middleware=[ToolErrorMiddleware(aon_error=aon_error)],
)
```

# Tool retry

通过可配置的指数避退机制来自动重试失败tool calls

**API reference:** [`ToolRetryMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/tool_retry/ToolRetryMiddleware)

# Model retry

通过可配置的指数避退机制来自动重试失败的model calls
常见:API错误,网络问题

**API reference:** [`ModelRetryMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/model_retry/ModelRetryMiddleware)

# Model fallback

当主模型失败时,回退到备用模型
**API reference:** [`ModelFallbackMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/model_fallback/ModelFallbackMiddleware)

# Summarization

当接近token limit自动触发对话历史的压缩,保留最近几轮对话,摘要旧的上下文

**API reference:** [`SummarizationMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/summarization/SummarizationMiddleware)

摘要是针对文本,对于多模态的信息会仅有生成的文本摘要来表示


# Human-in-the-loop

在工具运行之前,需要人工的同意,编辑或者拒绝时


**API reference:** [`HumanInTheLoopMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/human_in_the_loop/HumanInTheLoopMiddleware)

# Model call limit

限制model call的数量来防止无限的loop和过度的费用
**API reference:** [`ModelCallLimitMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/model_call_limit/ModelCallLimitMiddleware)

# Tool call limit

限制工具调用的次数(可以全局控制,也可以对于单一的工具进行限制)
**API reference:** [`ToolCallLimitMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/tool_call_limit/ToolCallLimitMiddleware)

# PII detection

使用可配置的策略来检测并处理个人认证信息

**API reference:** [`PIIMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/pii/PIIMiddleware)

# Custom PII types

使用`detector`参数来自定义PII types

**Three ways to create custom detectors:**

1. **Regex pattern string** - Simple pattern matching
2. **Custom function** - Complex detection logic with validation
3. **Custom detector function signature:**

# To-do list

使得模型有对于复杂任务的planning和track能力


**API reference:** [`TodoListMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/todo/TodoListMiddleware)

# LLM tool selector

顾名思义

**API reference:** [`LLMToolSelectorMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/tool_selection/LLMToolSelectorMiddleware)
向模型提供结构化的结果输出

# Provider tool search

适用于按需暴露tool的场景,通过将selected的tool放置在server-side tool search之后

**API reference:** [`ProviderToolSearchMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/provider_tool_search/ProviderToolSearchMiddleware)



# Shell tool

向agent提供持久的shell会话来执行命令,目前的shell会话暂时不支持中断(人机交互)
选择恰当的策略来匹配你的安全策略(HostExecutionPolicy`, `DockerExecutionPolicy`, or `CodexSandboxExecutionPolicy)

# FileSystem middleware

提供agent同时与长期记忆和短期记忆互动的能力


- `ls`: List the files in the filesystem
- `read_file`: Read an entire file or a certain number of lines from a file
- `write_file`: Write a new file to the filesystem
- `edit_file`: Edit an existing file in the filesystem

##  短期与长期文件系统

默认情况下，这些工具写入您图状态（graph state）中的本地“文件系统”。要启用跨线程的持久存储，请配置一个 `CompositeBackend`，将特定路径（如 `/memories/`）路由到 `StoreBackend`。

```
from langchain.agents import create_agent
from deepagents.middleware import FilesystemMiddleware
from deepagents.backends import CompositeBackend, StateBackend, StoreBackend
from langgraph.store.memory import InMemoryStore

store = InMemoryStore()

agent = create_agent(
    model="claude-sonnet-4-6",
    store=store,
    middleware=[
        FilesystemMiddleware(
            backend=CompositeBackend(
                default=StateBackend(),
                routes={"/memories/": StoreBackend()}
            ),
            custom_tool_descriptions={
                "ls": "Use the ls tool when...",
                "read_file": "Use the read_file tool to..."
            }  # Optional: Custom descriptions for filesystem tools
        ),
    ],
)
```

当您为 `/memories/` 配置了带有 `StoreBackend` 的 `CompositeBackend` 时，任何以 **/memories/** 为前缀的文件都将保存到持久存储中，并在不同的线程之间保持存在。没有此前缀的文件将保留在暂存的状态存储中。

# Subagent

上下文独立,并且保持主agent的上下文干净
允许你通过`task`来创建subagents

A subagent is defined with a **name**, **description**, **system prompt**, and **tools**. You can also provide a subagent with a custom **model**, or with additional **middleware**. 

对于更复杂的情景,你需要提供预编译的LangGraph graph作为subagent

# Rubric grading

某些任务有明确的“完成”定义，智能体在第一次尝试时可能无法可靠地达到。`RubricMiddleware` 允许您将*“完成”的具体标准*声明为量规（rubric），让智能体自我评估并不断迭代，直到满足该标准或达到最大迭代次数限制。

**API reference:** [`RubricMiddleware`](https://reference.langchain.com/python/deepagents/middleware/rubric/RubricMiddleware)

# File search

提供Glob和Grep能力来访问文件系统

**API reference:** [`FilesystemFileSearchMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/file_search/FilesystemFileSearchMiddleware)

# Context editing

上下文管理

**API reference:** [`ContextEditingMiddleware`](https://reference.langchain.com/python/langchain/agents/middleware/context_editing/ContextEditingMiddleware), [`ClearToolUsesEdit`](https://reference.langchain.com/python/langchain/agents/middleware/context_editing/ClearToolUsesEdit)

# LLM tool emulator

将实际的工具相应更换为AI生成的response,通常是为了测试目的



