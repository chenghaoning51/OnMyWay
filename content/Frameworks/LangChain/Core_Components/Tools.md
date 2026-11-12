+++
title = "Tools"
slug = "tools"
weight = 100
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Tools相关学习笔记与实践要点。"
+++
# Tools

Extend what agents can do!

# Create tools

## Basic tool definition

The easiest way to create a tool is to use the **`@tool` decorator**
In this way the **docstring** will become the description of the tool 

```
from langchain.tools import tool

@tool
def search_database(query: str, limit: int = 10) -> str:
    """Search the customer database for records matching the query.

    Args:
        query: Search terms to look for
        limit: Maximum number of results to return
    """
    return f"Found {limit} results for '{query}'"
```

docstring:'''
		  ada
		  '''
的部分
docstring应该内容丰富且简明扼要
参数的type hints是必须的,因为他们定义了工具的输入参数

## Customize tool properties

### Custom tool name

by default,the tool name is the function name. But you can override it.

```
@tool("web_search")  # Custom name
def search(query: str) -> str:
    """Search the web for information."""
    return f"Results for: {query}"

print(search.name)  # web_search
```

### Custom tool description

Override the auto-generated tool description(refer to the docstring) for clearer model guidance

```
@tool("calculator", description="Performs arithmetic calculations. Use this for any math problems.")
def calc(expression: str) -> str:
    """Evaluate mathematical expressions."""
    return str(eval(expression))
```

## Advanced schema definition

Define complex inputs with Pydantic models or JSON schemas

```
from pydantic import BaseModel, Field
from typing import Literal

class WeatherInput(BaseModel):
    """Input for weather queries."""
    location: str = Field(description="City name or coordinates")
    units: Literal["celsius", "fahrenheit"] = Field(
        default="celsius",
        description="Temperature unit preference"
    )
    include_forecast: bool = Field(
        default=False,
        description="Include 5-day forecast"
    )

@tool(args_schema=WeatherInput)
def get_weather(location: str, units: str = "celsius", include_forecast: bool = False) -> str:
    """Get current weather and optional forecast."""
    temp = 22 if units == "celsius" else 72
    result = f"Current weather in {location}: {temp} degrees {units[0].upper()}"
    if include_forecast:
        result += "\nNext 5 days: Sunny"
    return result
```

## Reserved argument names

Those can not be used as parameters' name which will cause runtime errors
config: reserved for  RunnableConfig
runtime: reserved for ToolRuntime

# Access context

How to access and update this information(conversation history,user data,persistent memory)

How!
By the `ToolRuntime` parameter

| Component          | Description                                                  | Use case                                                    |
| :----------------- | :----------------------------------------------------------- | :---------------------------------------------------------- |
| **State**          | Short-term memory - mutable data that exists for the current conversation (messages, counters, custom fields) | Access conversation history, track tool call counts         |
| **Context**        | Immutable configuration passed at invocation time (user IDs, session info) | Personalize responses based on user identity                |
| **Store**          | Long-term memory - persistent data that survives across conversations | Save user preferences, maintain knowledge base              |
| **Stream Writer**  | Emit real-time updates during tool execution                 | Show progress for long-running operations                   |
| **Execution Info** | Identity and retry information for the current execution (thread ID, run ID, attempt number) | Access thread/run IDs, adjust behavior based on retry state |
| **Server Info**    | Server-specific metadata when running on LangGraph Server (assistant ID, graph ID, authenticated user) | Access assistant ID, graph ID, or authenticated user info   |
| **Config**         | [`RunnableConfig`](https://reference.langchain.com/python/langchain-core/runnables/config/RunnableConfig) for the execution | Access callbacks, tags, and metadata                        |
| **Tool Call ID**   | Unique identifier for the current tool invocation            | Correlate tool calls for logs and model invocations         |

![image-20260919214843362](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260919214843362.png)

## Short-term memory(State)

Include the message history and any custom field you define in your graph state.

### Access state

Use `runtime: ToolRuntime` to your signature to access state
在调用的时候,`ToolNode`会自动地注入value,但是这个参数不会出现在发送给model地schema上
你需要通过`runtime.state`才能访问到当前对话的state

```
from langchain.tools import tool, ToolRuntime
from langchain.messages import HumanMessage

@tool
def get_last_user_message(runtime: ToolRuntime) -> str:
    """Get the most recent message from the user."""
    messages = runtime.state["messages"]

    # Find the last human message
    for message in reversed(messages):
        if isinstance(message, HumanMessage):
            return message.content

    return "No user messages found"

# Access custom state fields
@tool
def get_user_preference(
    pref_name: str,
    runtime: ToolRuntime
) -> str:
    """Get a user preference value."""
    preferences = runtime.state.get("user_preferences", {})
    return preferences.get(pref_name, "Not set")
```

The `runtime` parameter is hidden from the model. For the example above, the model only sees `pref_name` in the tool schema.(上面说过了,结合例子更好理解)

### Update state

Use `Command` to update the agent's state.
Useful to update custom state field.
Include a `ToolMessage` in the update so the model can see the result of this tool call

```
from langchain.agents import AgentState
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command


class CustomState(AgentState):
    user_name: str


@tool
def set_user_name(new_name: str, runtime: ToolRuntime[None, CustomState]) -> Command:
    """Set the user's name in the conversation state."""
    return Command(
        update={
            "user_name": new_name,
            "messages": [
                ToolMessage(
                    content=f"User name set to {new_name}.",
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )
```

When tools update state variables, consider defining a [reducer](https://docs.langchain.com/oss/python/langgraph/graph-api#reducers) for those fields. Since LLMs can call multiple tools in parallel, a reducer determines how to resolve conflicts when the same state field is updated by concurrent tool calls.
(创建reducer来应对并发修改同一个state值)

## Context

Provides immutable configuration at invocation time
Including user IDs,session details,application-specific settings

Access context through `runtime.context`.
Pass it alongside a `thread_id` so the conversation is persisted across turns.

```
from dataclasses import dataclass

from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime
from langchain_core.utils.uuid import uuid7
from langchain_openai import ChatOpenAI


USER_DATABASE = {
    "user123": {
        "name": "Alice Johnson",
        "account_type": "Premium",
        "balance": 5000,
        "email": "alice@example.com",
    },
    "user456": {
        "name": "Bob Smith",
        "account_type": "Standard",
        "balance": 1200,
        "email": "bob@example.com",
    },
}


@dataclass
class UserContext:
    user_id: str


@tool
def get_account_info(runtime: ToolRuntime[UserContext]) -> str:
    """Get the current user's account information."""
    user_id = runtime.context.user_id

    if user_id in USER_DATABASE:
        user = USER_DATABASE[user_id]
        return (
            f"Account holder: {user['name']}\n"
            f"Type: {user['account_type']}\n"
            f"Balance: ${user['balance']}"
        )
    return "User not found"


model = ChatOpenAI(model="gpt-5.5")
agent = create_agent(
    model,
    tools=[get_account_info],
    context_schema=UserContext,
    system_prompt="You are a financial assistant.",
)

result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's my current balance?"}]},
    config={"configurable": {"thread_id": str(uuid7())}},
    context=UserContext(user_id="user123"),
)
```

## Long-term memory(Store)

The [`BaseStore`](https://reference.langchain.com/python/langchain-core/stores/BaseStore) provides persistent storage that survives across conversations. 
Access store through `runtime.store`. The store uses a namespace/key pattern to organize data

```
from langgraph.store.memory import InMemoryStore
from langchain.agents import create_agent
from langchain.tools import tool, ToolRuntime
from langchain_openai import ChatOpenAI

# Access memory
@tool
def get_user_info(user_id: str, runtime: ToolRuntime) -> str:
    """Look up user info."""
    store = runtime.store
    user_info = store.get(("users",), user_id)
    return str(user_info.value) if user_info else "Unknown user"

# Update memory
@tool
def save_user_info(user_id: str, name: str, age: int, email: str, runtime: ToolRuntime) -> str:
    """Save user info."""
    store = runtime.store
    store.put(("users",), user_id, {"name": name, "age": age, "email": email})
    return "Successfully saved user info."

model = ChatOpenAI(model="gpt-5.5")

store = InMemoryStore()
agent = create_agent(
    model,
    tools=[get_user_info, save_user_info],
    store=store
)

# First session: save user info
agent.invoke({
    "messages": [{"role": "user", "content": "Save the following user: userid: abc123, name: Foo, age: 25, email: foo@langchain.dev"}]
})

# Second session: get user info
agent.invoke({
    "messages": [{"role": "user", "content": "Get user info for user with id 'abc123'"}]
})
# Here is the user info for user with ID "abc123":
# - Name: Foo
# - Age: 25
# - Email: foo@langchain.dev
```

## Streaming writer

Stream real-time updates from tools during execution.
Useful for providing progress feedback
Use `runtime.stream_Writer` to emit custom updates

```
from langchain.tools import tool, ToolRuntime

@tool
def get_weather(city: str, runtime: ToolRuntime) -> str:
    """Get weather for a given city."""
    writer = runtime.stream_writer

    # Stream custom updates as the tool executes
    writer(f"Looking up data for city: {city}")
    writer(f"Acquired data for city: {city}")

    return f"It's always sunny in {city}!"
```

## Execution info

Access thread ID,run ID,and retry state from within a tool via `runtime.execution_info`

```
from langchain.tools import tool, ToolRuntime

@tool
def log_execution_context(runtime: ToolRuntime) -> str:
    """Log execution identity information."""
    info = runtime.execution_info
    print(f"Thread: {info.thread_id}, Run: {info.run_id}")
    print(f"Attempt: {info.node_attempt}")
    return "done"
```

## Server info

When your tool runs on LangGraph Server , access assistant ID,graph ID,and authenticated user via `runtime.server_info`

```
from langchain.tools import tool, ToolRuntime

@tool
def get_assistant_scoped_data(runtime: ToolRuntime) -> str:
    """Fetch data scoped to the current assistant."""
    server = runtime.server_info
    if server is not None:
        print(f"Assistant: {server.assistant_id}, Graph: {server.graph_id}")
        if server.user is not None:
            print(f"User: {server.user.identity}")
    return "done"
```

`server_info` is `None` when the tool is not running on LangGraph Server

# Tool execution

Tool: used by agent
Tool error handing is configured by middleware

## Tool return values

a `string` for human-readable results;an `object` for structured results;a `Command` with optional message when you need to update the state

### Return a string

when tool should provide plain text for the model to read and use in its next response

```
from langchain.tools import tool


@tool
def get_weather(city: str) -> str:
    """Get weather for a city."""
    return f"It is currently sunny in {city}."
```

The return value is converted to a `ToolMessage`

### Return an object

when your tool produces structured data that the model should inspect

```
from langchain.tools import tool


@tool
def get_weather_data(city: str) -> dict:
    """Get structured weather data for a city."""
    return {
        "city": city,
        "temperature_c": 22,
        "conditions": "sunny",
    }
```

- The object is serialized and sent back as tool output.
- The model can read specific fields and reason over them.
- Like string returns, this does not directly update graph state.

### Return multimodal content

For multimodal content ,use **standard content blocks** so the model receives multimodal resources

```
from langchain.tools import tool


@tool
def capture_screenshot() -> list[dict]:
    """Capture a screenshot of the current page."""
    return [
        {"type": "text", "text": "Screenshot of the current page:"},
        {"type": "image", "url": "https://example.com/page.png"},
    ]
```

- The return value is converted to a `ToolMessage` with multimodal `content`.
- Use `message.content_blocks` to read the normalized block list after the tool runs.
- The model must support the modalities you return. Check your [model’s capabilities](https://docs.langchain.com/oss/python/integrations/chat) before returning images, audio, or video.

### Return a Command

when the tool need to update graph state(or example, setting user preferences or app state)

 When the `Command` targets the current graph, include a `ToolMessage` in the update whose tool call ID matches the current tool call. Every tool call in the message history must have a corresponding `ToolMessage`.
返回的一个Command的Command.update中必须包含一个对应的ToolMessage.对应是指tool_call_id对应

Use `runtime.tool_call_id` for the `tool_call_id` parameter. `ToolNode` enforces this requirement: if the update has no `ToolMessage` matching the tool call, it raises a `ValueError`.
否则会返回一个ValueError

### Return directly from a tool

设置return_direct来使得agent-loop短路,这样工具输出不会传回给模型而是直接传给caller

```
from langchain.agents import create_agent
from langchain.tools import tool
from langchain_openai import ChatOpenAI


@tool(return_direct=True)
def fetch_order_status(order_id: str) -> str:
    """Fetch the current status of a customer order."""
    # In production, query your order management system here
    return f"Order {order_id} is shipped and will arrive in 2 days."


agent = create_agent(
    ChatOpenAI(model="gpt-4o-mini"),
    tools=[fetch_order_status],
)

result = agent.invoke({
    "messages": [{"role": "user", "content": "What is the status of order #12345?"}]
})
# The agent returns the tool output directly without another LLM call:
# "Order 12345 is shipped and will arrive in 2 days."
```

Behavior:

- The tool executes normally and its output is wrapped in a `ToolMessage`.
- The agent stops looping and returns the tool’s output as the final response, bypassing any additional model call.
- **Multiple parallel tool calls:** When the model calls several tools in one step, all of them execute first. After all tools finish, the agent routes to `END` only if **every** tool in that batch has `return_direct=True`. The final response includes the `ToolMessage` outputs of every tool that was called in that step.

Use this when:

- The tool’s output is the complete, user-ready answer (for example, a lookup that returns a ready-to-display result).
- You want to avoid an extra model call when no additional reasoning is needed.
- You need deterministic, unmodified output: the model cannot rephrase, summarize, or act on the tool result.

### Return a Command with return_direct

A tool with `return_direct=True` can also return a [`Command`](https://reference.langchain.com/python/langgraph/types/Command) to update graph state before the agent exits. Unlike a plain return value, a `Command` is not automatically converted into a `ToolMessage`. When the `Command` targets the current graph (`graph` is not set or is `None`), include a `ToolMessage` in `Command.update` matching the tool call’s `tool_call_id`. Omitting it causes `ToolNode` to raise a `ValueError`, because every `AIMessage` tool call must have a corresponding `ToolMessage` in the message history.

```
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command


@tool(return_direct=True)
def fetch_and_store_order(order_id: str, runtime: ToolRuntime) -> Command:
    """Fetch order status and store it in state."""
    status = f"Order {order_id} is shipped and will arrive in 2 days."
    return Command(
        update={
            "last_order_status": status,
            # Must include a ToolMessage so the message history stays valid
            "messages": [
                ToolMessage(
                    content=status,
                    tool_call_id=runtime.tool_call_id,
                )
            ],
        }
    )
```

## Error handing

Using LangChain middleware to retry failed tool calls or return custom error message

```
from collections.abc import Callable

from langchain.agents import create_agent
from langchain.agents.middleware import wrap_tool_call
from langchain.messages import ToolMessage
from langchain.tools.tool_node import ToolCallRequest


@wrap_tool_call
def handle_tool_errors(
    request: ToolCallRequest,
    handler: Callable[[ToolCallRequest], ToolMessage],
) -> ToolMessage:
    """Convert tool exceptions into ToolMessages the model can handle."""
    try:
        return handler(request)
    except Exception as e:
        return ToolMessage(
            content=f"Tool error: Please check your input and try again. ({e})",
            tool_call_id=request.tool_call["id"],
        )


agent = create_agent(
    model="openai:gpt-5.5",
    tools=[],
    middleware=[handle_tool_errors],
)
```

## State injection

Tool access graph state through `ToolRUntime`

# Dynamic tool section

太多tool会占用过多的context,太少则会限制能力
动态工具允许在runtime时修改
主要有两种方式实现,取决于工具是否事先已知

### Filtering pre-registered tools

When all tools are known at agent creation time,you can pre-register them and dynamically filter which ones are exposed to the model based on state,permissions,or context

```
  代码有三个,自己去官网看
```

- All possible tools are known at compile/startup time
- You want to filter based on permissions, feature flags, or conversation state
- Tools are static but their availability is dynamic

### Runtime tool register

when tools are not discovered or created at runtime

1. `wrap_model_call` - Add the dynamic tools to the request
2. `wrap_tool_call` - Handle execution of the dynamically added tools

```
from langchain.tools import tool
from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware, ModelRequest, ToolCallRequest

# A tool that will be added dynamically at runtime
@tool
def calculate_tip(bill_amount: float, tip_percentage: float = 20.0) -> str:
    """Calculate the tip amount for a bill."""
    tip = bill_amount * (tip_percentage / 100)
    return f"Tip: ${tip:.2f}, Total: ${bill_amount + tip:.2f}"

class DynamicToolMiddleware(AgentMiddleware):
    """Middleware that registers and handles dynamic tools."""

    def wrap_model_call(self, request: ModelRequest, handler):
        # Add dynamic tool to the request
        # This could be loaded from an MCP server, database, etc.
        updated = request.override(tools=[*request.tools, calculate_tip])
        return handler(updated)

    def wrap_tool_call(self, request: ToolCallRequest, handler):
        # Handle execution of the dynamic tool
        if request.tool_call["name"] == "calculate_tip":
            return handler(request.override(tool=calculate_tip))
        return handler(request)

agent = create_agent(
    model="gpt-5.5",
    tools=[get_weather],  # Only static tools registered here
    middleware=[DynamicToolMiddleware()],
)

# The agent can now use both get_weather AND calculate_tip
result = agent.invoke({
    "messages": [{"role": "user", "content": "Calculate a 20% tip on $85"}]
})
```

This approach is best when:

- Tools are discovered at runtime (e.g., from an MCP server)
- Tools are generated dynamically based on user data or configuration
- You’re integrating with external tool registries

# Headless tools

某些工具应该运行在**用户应用运行的地方**（通常是浏览器），而不是在进程内部。**无头工具 (Headless tools)**是工具定义（包括名称、描述和参数 schema），您在**服务端**向智能体进行注册。而**实现**仅在**客户端**注册，并在简短的中断/恢复（interrupt/resume）握手后执行

## when to use

when the work depends on the **environment, device, or UI** that only exists on the client. For example:

- Browser APIs
- Privacy and locality
- Latency(延迟)
- Structured,safe effects

## How it work

model can see it and call it but it actually happens outside the process

1. Define with (name, description,parameter) without in-process implementation
2. Register it with create agent so the model can call it normally
3. Handle the interrupt payload when the tool is invoked. Instead of running locally, the graph pauses with a payload shaped like `{"type": "tool", "tool_call": {"id", "name", "args"}}`.
4. Resume the graph

Use the optional **`onTool`** callback to observe lifecycle events (`start`, `success`, `error`) for UI feedback such as spinners or toasts.

# Prebuilt tools

LangChain provides a large collection of prebuilt tools and toolkits for common tasks like web search, code interpretation, database access, and more. These ready-to-use tools can be directly integrated into your agents without writing custom code.See the [tools and toolkits](https://docs.langchain.com/oss/python/integrations/tools) integration page for a complete list of available tools organized by category.

# Tools from MCP

[Model Context Protocol (MCP)](https://modelcontextprotocol.io/) is an open protocol that standardizes how applications expose tools to language models. Rather than hand-authoring a tool, you connect to an MCP server and adapt the tools it advertises into LangChain tools, ready to pass to an agent like any other tool.[`MCPAdapter`](https://reference.langchain.com/python/langchain/mcp/adapter/MCPAdapter) discovers a server’s tools and converts them into LangChain tools. Open the adapter, call `list_tools()`, and hand the result to [`create_agent`](https://reference.langchain.com/python/langchain/agents/factory/create_agent):

```
from langchain.agents import create_agent
from langchain.mcp import MCPAdapter

async with MCPAdapter("https://example.com/mcp") as adapter:
    tools = await adapter.list_tools()
    agent = create_agent("claude-sonnet-4-6", tools)
```

# Server-side tool use

Some chat models feature built-in tools that are executed server-side by the model provider. These include capabilities like web search and code interpreters that don’t require you to define or host the tool logic.Refer to the individual [chat model integration pages](https://docs.langchain.com/oss/python/integrations/providers) and the [tool calling documentation](https://docs.langchain.com/oss/python/langchain/models#server-side-tool-use) for details on enabling and using these built-in tools.