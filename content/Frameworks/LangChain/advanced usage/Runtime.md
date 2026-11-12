+++
title = "Runtime"
slug = "runtime"
weight = 80
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Runtime相关学习笔记与实践要点。"
+++
LangChain's `create_agent`的底层运行在LangGraph's runtime
LangGraph暴露一个Runtime object,提供以下的信息:
1.context:静态信息:user id,数据库连接和其他的依赖
2.Store:用于长期记忆的BaseStore实例
3.Stream writer:通过"custom"流式传输模式来硫化信息的object
4.Execution info: identity and retry information for the current execution(thread ID, run ID ,attmpt number)
5.Server info:在 LangGraph Server 上运行时的特定于服务器的元数据(assistant ID,graph ID, authenticated user
)
You can access the runtime information within tools and middleware

# Access

当创建agent with `create_agent`时,可以传入一个context_schema来定义存储在agent的`Runtime`中的context的结构

当调用agent是,则可以传入`context` with 相关的参数

```
from dataclasses import dataclass

from langchain.agents import create_agent


@dataclass
class Context:
    user_name: str

agent = create_agent(
    model="gpt-5-nano",
    tools=[...],
    context_schema=Context  
)

agent.invoke(
    {"messages": [{"role": "user", "content": "What's my name?"}]},
    context=Context(user_name="John Smith")
)
```

## Inside tools

你可以在tool中访问runtime来:

- Access the context
- Read or write long-term memory
- Wtrie tp the custom stream

通过`ToolRuntime`参数来访问`Runtime`对象:

```
from dataclasses import dataclass
from langchain.tools import tool, ToolRuntime  

@dataclass
class Context:
    user_id: str

@tool
def fetch_user_email_preferences(runtime: ToolRuntime[Context]) -> str:
    """Fetch the user's email preferences from the store."""
    user_id = runtime.context.user_id  

    preferences: str = "The user prefers you to write a brief and polite email."
    if runtime.store:
        if memory := runtime.store.get(("users",), user_id):
            preferences = memory.value["preferences"]

    return preferences
```

## Execution info and server info inside tools

Access execution identity (thread ID, run ID) via `runtime.execution_info`, and server-specific metadata (assistant ID, authenticated user) via `runtime.server_info` when running on LangGraph Server

```
from langchain.tools import tool, ToolRuntime

@tool
def context_aware_tool(runtime: ToolRuntime) -> str:
    """A tool that uses execution and server info."""
    # Access thread and run IDs
    info = runtime.execution_info
    print(f"Thread: {info.thread_id}, Run: {info.run_id}")

    # Access server info (only available on LangGraph Server)
    server = runtime.server_info
    if server is not None:
        print(f"Assistant: {server.assistant_id}")
        if server.user is not None:
            print(f"User: {server.user.identity}")

    return "done"
```

## Inside middleware

通过middleware访问runtime来:创建动态prompt,修改messages,根据上下文控制agent的行为


Use the `Runtime` parameter to access the [`Runtime`](https://reference.langchain.com/python/langgraph/runtime/Runtime) object inside [node-style hooks](https://docs.langchain.com/oss/python/langchain/middleware/custom#node-style-hooks). For [wrap-style hooks](https://docs.langchain.com/oss/python/langchain/middleware/custom#wrap-style-hooks), the `Runtime` object is available inside the [`ModelRequest`](https://reference.langchain.com/python/langchain/agents/middleware/types/ModelRequest) parameter.

```
from dataclasses import dataclass

from langchain.messages import AnyMessage
from langchain.agents import create_agent, AgentState
from langchain.agents.middleware import dynamic_prompt, ModelRequest, before_model, after_model
from langgraph.runtime import Runtime


@dataclass
class Context:
    user_name: str

# Dynamic prompts
@dynamic_prompt
def dynamic_system_prompt(request: ModelRequest) -> str:
    user_name = request.runtime.context.user_name  
    system_prompt = f"You are a helpful assistant. Address the user as {user_name}."
    return system_prompt

# Before model hook
@before_model
def log_before_model(state: AgentState, runtime: Runtime[Context]) -> dict | None:
    print(f"Processing request for user: {runtime.context.user_name}")
    return None

# After model hook
@after_model
def log_after_model(state: AgentState, runtime: Runtime[Context]) -> dict | None:
    print(f"Completed request for user: {runtime.context.user_name}")
    return None

agent = create_agent(
    model="gpt-5-nano",
    tools=[...],
    middleware=[dynamic_system_prompt, log_before_model, log_after_model],
    context_schema=Context
)

agent.invoke(
    {"messages": [{"role": "user", "content": "What's my name?"}]},
    context=Context(user_name="John Smith")
)
```

## Execution info and server info inside middleware

Middleware hooks can also access `runtime.execution_info` and `runtime.server_info`:

```
from langchain.agents import AgentState
from langchain.agents.middleware import before_model
from langgraph.runtime import Runtime


@before_model
def auth_gate(state: AgentState, runtime: Runtime) -> dict | None:
    """Block unauthenticated users when running on LangGraph Server."""
    server = runtime.server_info
    if server is not None and server.user is None:
        raise ValueError("Authentication required")
    print(f"Thread: {runtime.execution_info.thread_id}")
    return None
```

