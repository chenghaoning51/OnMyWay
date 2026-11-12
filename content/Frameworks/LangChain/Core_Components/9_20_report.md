+++
title = "9 月 20 日学习报告：LangChain Agent 的 Tool、Memory 与 Streaming"
slug = "langchain-agent-study-report-2026-09-20"
weight = 1
categories = ["Frameworks", "LangChain"]
tags = ["Agent", "Tool", "Schema", "Memory", "Stream", "Middleware"]
description = "按修改时间与源文件结构整理 Tool、short-term memory、Event Streaming 和 Streaming。"
draft = false
+++

# 9 月 20 日学习报告：LangChain Agent 的 Tool、Memory 与 Streaming

仅整理 2026-09-20 修改的 4 个文件。文件按最后修改时间排列；各文件内部保持原文标题顺序与层级，只压缩重复表述和示例，不省略知识点。

## 14:08:52 — Tools.md

### Tools

Tools extend what agents can do。

### Create tools

#### Basic tool definition

定义 Tool 最简单的方式是使用 `@tool` decorator。函数 docstring 会成为 Tool description；参数 type hints 是必须的，因为它们定义 Tool 的输入 Schema。docstring 应内容丰富且简明扼要。

```python
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

#### Customize tool properties

##### Custom tool name

Tool name 默认等于函数名，可通过 `@tool("web_search")` 覆盖。

##### Custom tool description

默认 description 来自 docstring。需要更明确地指导 model 时，使用 `description=` 覆盖自动生成的 description。

#### Advanced schema definition

复杂输入使用 Pydantic model 或 JSON Schema。`Field(description=...)` 描述字段，`Literal` 限定可选值，`@tool(args_schema=...)` 绑定输入 Schema。

```python
from typing import Literal
from pydantic import BaseModel, Field

class WeatherInput(BaseModel):
    location: str = Field(description="City name or coordinates")
    units: Literal["celsius", "fahrenheit"] = Field(
        default="celsius",
        description="Temperature unit preference",
    )
    include_forecast: bool = Field(default=False)

@tool(args_schema=WeatherInput)
def get_weather(
    location: str,
    units: str = "celsius",
    include_forecast: bool = False,
) -> str:
    """Get current weather and optional forecast."""
    ...
```

#### Reserved argument names

- `config` 保留给 `RunnableConfig`；
- `runtime` 保留给 `ToolRuntime`。

二者不能用作普通业务参数，否则会产生 runtime error。

### Access context

Tool 通过 `ToolRuntime` 访问 conversation history、user data、persistent memory 和执行信息。

| Component | 访问方式 | 含义与用途 |
| :--- | :--- | :--- |
| State | `runtime.state` | 当前 conversation 的可变 short-term memory；messages、计数器、自定义字段 |
| Context | `runtime.context` | invocation 时传入的不可变配置；user ID、session info |
| Store | `runtime.store` | 跨 conversation 持久化的 long-term memory |
| Stream Writer | `runtime.stream_writer` | Tool 执行时发送实时 custom updates |
| Execution Info | `runtime.execution_info` | thread ID、run ID、attempt number |
| Server Info | `runtime.server_info` | assistant ID、graph ID、authenticated user |
| Config | `runtime.config` | `RunnableConfig` 的 callbacks、tags、metadata |
| Tool Call ID | `runtime.tool_call_id` | 当前 Tool invocation ID，用于匹配 `ToolMessage` |

#### Short-term memory(State)

State 包含 message history 和 graph state 中定义的自定义字段。

##### Access state

在 Tool 签名中声明 `runtime: ToolRuntime`。`ToolNode` 会自动注入它，但它不会出现在发送给 model 的 Tool Schema 中。Tool 通过 `runtime.state` 读取 State。

```python
from langchain.messages import HumanMessage
from langchain.tools import ToolRuntime, tool

@tool
def get_last_user_message(runtime: ToolRuntime) -> str:
    """Get the most recent message from the user."""
    for message in reversed(runtime.state["messages"]):
        if isinstance(message, HumanMessage):
            return message.content
    return "No user messages found"

@tool
def get_user_preference(pref_name: str, runtime: ToolRuntime) -> str:
    """Get a user preference value."""
    return runtime.state.get("user_preferences", {}).get(pref_name, "Not set")
```

第二个 Tool 的 model-visible Schema 只有 `pref_name`，没有 `runtime`。

##### Update state

Tool 更新 State 时返回 `Command`。当目标是当前 graph 时：

1. 在 `Command.update` 写入 State 字段；
2. 在 `Command.update["messages"]` 中加入 `ToolMessage`；
3. 结果写入 `ToolMessage.content`；
4. `ToolMessage.tool_call_id` 必须等于 `runtime.tool_call_id`。

```python
from langchain.agents import AgentState
from langchain.messages import ToolMessage
from langchain.tools import ToolRuntime, tool
from langgraph.types import Command

class CustomState(AgentState):
    user_name: str

@tool
def set_user_name(
    new_name: str,
    runtime: ToolRuntime[None, CustomState],
) -> Command:
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

每个 `AIMessage` tool call 都必须有对应的 `ToolMessage`。消息缺失或 ID 不匹配时，`ToolNode` 抛出 `ValueError`。多个 Tool 并行更新同一 State 字段时，应定义 reducer，明确覆盖、追加或其他合并规则。

#### Context

Context 是 invocation 时传入的不可变配置，包括 user ID、session details 和 application settings。使用 `context_schema` 声明结构，通过 `context=` 传入，Tool 从 `runtime.context` 读取。

```python
from dataclasses import dataclass

@dataclass
class UserContext:
    user_id: str

@tool
def get_account_info(runtime: ToolRuntime[UserContext]) -> str:
    """Get the current user's account information."""
    return str(USER_DATABASE.get(runtime.context.user_id, "User not found"))

agent = create_agent(
    model="openai:gpt-5.5",
    tools=[get_account_info],
    context_schema=UserContext,
)

result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's my balance?"}]},
    config={"configurable": {"thread_id": "thread-1"}},
    context=UserContext(user_id="user123"),
)
```

`thread_id` 标识 conversation；`user_id` 标识业务用户，二者不同。

#### Long-term memory(Store)

`BaseStore` 提供跨 conversation 持久化的数据。使用 `runtime.store` 访问，以 namespace/key 组织记录。

```python
@tool
def get_user_info(user_id: str, runtime: ToolRuntime) -> str:
    """Look up user info."""
    item = runtime.store.get(("users",), user_id)
    return str(item.value) if item else "Unknown user"

@tool
def save_user_info(
    user_id: str,
    name: str,
    age: int,
    email: str,
    runtime: ToolRuntime,
) -> str:
    """Save user info."""
    runtime.store.put(
        ("users",), user_id, {"name": name, "age": age, "email": email}
    )
    return "Successfully saved user info."
```

把同一 Store 传给 `create_agent(store=store)` 后，可在一个 session 保存、另一个 session 读取。

#### Streaming writer

`runtime.stream_writer` 可在 Tool 执行中发送实时 custom updates，适合长任务进度；Tool 最终仍用 `return` 返回完成结果。

```python
@tool
def get_weather(city: str, runtime: ToolRuntime) -> str:
    """Get weather for a given city."""
    runtime.stream_writer(f"Looking up data for city: {city}")
    runtime.stream_writer(f"Acquired data for city: {city}")
    return f"It's always sunny in {city}!"
```

#### Execution info

`runtime.execution_info` 提供 `thread_id`、`run_id` 和 `node_attempt`，用于日志关联和重试判断。

#### Server info

在 LangGraph Server 上，`runtime.server_info` 提供 `assistant_id`、`graph_id` 和 authenticated user；非 Server 环境下为 `None`。

### Tool execution

Tool 由 Agent 使用；Tool error handling 由 middleware 配置。

#### Tool return values

##### Return a string

返回 human-readable `str`，供 model 下一步读取；框架自动将其转换为 `ToolMessage`。

##### Return an object

返回结构化 `object`，供 model 读取字段并推理。对象会序列化为 Tool output，但不会直接更新 graph State。

##### Return multimodal content

多模态结果使用 standard content blocks，例如 text block 和 image block。结果转换成带 multimodal `content` 的 `ToolMessage`；可用 `message.content_blocks` 读取归一化 blocks。model 必须支持所返回的 image、audio 或 video modality。

##### Return a Command

需要更新 graph State 时返回 `Command`。若目标是当前 graph，必须显式提供与当前 tool call ID 匹配的 `ToolMessage`。普通 `str`/`object` 会自动包装为 `ToolMessage`，`Command` 不会。

##### Return directly from a tool

`@tool(return_direct=True)` 使 agent loop 短路：Tool 正常执行，输出包装成 `ToolMessage` 后直接返回 caller，不再追加 model call。

适用于：Tool output 已是完整答案；希望避免额外 model call；需要 deterministic、unmodified output。

同一步包含多个并行 tool calls 时，会先执行整个批次；仅当每个 Tool 都设置 `return_direct=True` 时才路由到 `END`，最终响应包含全部 Tool outputs。

##### Return a Command with return_direct

`return_direct=True` 的 Tool 可返回 `Command`，在退出前更新 State。`Command` 仍不会自动生成 `ToolMessage`，必须手动加入 `tool_call_id=runtime.tool_call_id` 的消息。

```python
@tool(return_direct=True)
def fetch_and_store_order(order_id: str, runtime: ToolRuntime) -> Command:
    """Fetch order status and store it in state."""
    status = f"Order {order_id} is shipped."
    return Command(
        update={
            "last_order_status": status,
            "messages": [
                ToolMessage(content=status, tool_call_id=runtime.tool_call_id)
            ],
        }
    )
```

#### Error handing

使用 middleware 重试失败 Tool，或把异常转换为 model 可处理的自定义 `ToolMessage`。异常结果的 `tool_call_id` 必须取原调用的 `request.tool_call["id"]`。

```python
from langchain.agents.middleware import wrap_tool_call
from langchain.messages import ToolMessage

@wrap_tool_call
def handle_tool_errors(request, handler) -> ToolMessage:
    try:
        return handler(request)
    except Exception as error:
        return ToolMessage(
            content=f"Tool error: Please check your input. ({error})",
            tool_call_id=request.tool_call["id"],
        )
```

#### State injection

Tool 通过框架注入且对 model 隐藏的 `ToolRuntime` 访问 State：读取用 `runtime.state`，更新用带匹配 `ToolMessage` 的 `Command`。

### Dynamic tool section

Tool 太多会占用 context，太少会限制能力。动态 Tool 根据启动时是否已知分为两类。

##### Filtering pre-registered tools

全部 Tool 在创建 Agent 时已知：先预注册，再依据 State、permissions 或 Context 动态过滤暴露给 model 的集合。适合 Tool 静态、availability 动态的场景。

##### Runtime tool register

Tool 在 runtime 才发现或创建时，需要同时处理：

1. `wrap_model_call`：用 `request.override(tools=[...])` 加入本次 model request；
2. `wrap_tool_call`：识别对应 name，用 `request.override(tool=...)` 提供执行对象。

只让 model 看见而不提供执行处理器，runtime 无法完成调用。此方式适合 MCP server、database、user configuration 和 external registry。

### Headless tools

服务端只注册 name、description 和 parameter Schema，实现只在客户端。model 可正常调用，但执行通过 interrupt/resume 在进程外完成。

#### when to use

用于依赖客户端 environment、device 或 UI 的工作：Browser APIs、privacy/locality、latency、structured safe effects。

#### How it work

1. 定义 Tool Schema，不提供 in-process implementation；
2. 将定义注册给 `create_agent`；
3. 调用时 graph 暂停，返回 `{"type":"tool","tool_call":{"id","name","args"}}`；
4. 客户端执行，再 resume graph。

`onTool` callback 可观察 `start`、`success`、`error`，用于 spinner 或 toast。

### Prebuilt tools

LangChain 提供 web search、code interpretation、database access 等 prebuilt tools/toolkits，可直接集成，无需自行实现。

### Tools from MCP

MCP 统一应用向 model 暴露 Tools 的方式。`MCPAdapter` 发现 MCP server 的 Tools，将 `list_tools()` 结果转换为 LangChain Tools，再传给 `create_agent`。

### Server-side tool use

部分 chat models 提供由 provider 执行的 built-in Tools，例如 web search 和 code interpreter，无需自行定义或托管 Tool logic；具体配置取决于 model integration。

## 15:38:37 — Short-term_memory.md

Conversation history 是最常见的 short-term memory；Message 包含 instructions 和 inputs。

### Usage

为 Agent 添加 short-term memory，需要在 `create_agent` 时指定 `checkpointer`。Short-term memory 是 Agent State 的一部分；checkpointer 按 thread 持久化 State，使 conversation 可恢复。

State 在 Agent invocation 或 tool call 等 step 完成时更新，在每个 step 开始时读取。相同 `thread_id` 恢复相同 conversation；不同 `thread_id` 使用独立 State。

```python
from langchain.agents import create_agent
from langgraph.checkpoint.memory import InMemorySaver

agent = create_agent(
    model="openai:gpt-5.5",
    tools=[get_user_info],
    checkpointer=InMemorySaver(),
)

config = {"configurable": {"thread_id": "1"}}
agent.invoke(
    {"messages": [{"role": "user", "content": "Hi! My name is Bob."}]},
    config,
)
result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's my name?"}]},
    config,
)
```

#### In production

生产环境使用 database-backed checkpointer；`InMemorySaver` 只适合本地示例和测试。

### Customizing agent memory

Agent 使用 `AgentState` 管理 short-term memory，其中 `messages` key 保存 conversation history。需要额外字段时继承 `AgentState`，通过 `state_schema=` 传给 `create_agent`。

```python
from langchain.agents import AgentState

class CustomAgentState(AgentState):
    user_id: str
    preferences: dict

agent = create_agent(
    model="openai:gpt-5.5",
    tools=[get_user_info],
    state_schema=CustomAgentState,
    checkpointer=InMemorySaver(),
)

result = agent.invoke(
    {
        "messages": [{"role": "user", "content": "Hello"}],
        "user_id": "user_123",
        "preferences": {"theme": "dark"},
    },
    {"configurable": {"thread_id": "1"}},
)
```

`state_schema` 定义 State 结构；`checkpointer` 负责按 thread 保存它。

### Common patterns

以下模式用于处理 conversation history 超过 LLM context window。

#### Trim message(截断消息)

接近 token limit 时，根据 token count 截断，并指定 boundary strategy。也可在 `@before_model` 中清空旧 messages，再写回首条与最近 messages。

```python
from langchain.agents.middleware import before_model
from langchain.messages import RemoveMessage
from langgraph.graph.message import REMOVE_ALL_MESSAGES

@before_model
def trim_messages(state, runtime) -> dict | None:
    """Keep only the first and most recent messages."""
    messages = state["messages"]
    if len(messages) <= 3:
        return None

    first_message = messages[0]
    recent_messages = messages[-3:] if len(messages) % 2 == 0 else messages[-4:]
    return {
        "messages": [
            RemoveMessage(id=REMOVE_ALL_MESSAGES),
            first_message,
            *recent_messages,
        ]
    }
```

`None` 表示不更新 State。选择最近 3 或 4 条是为了尽量维持有效的 request/response 边界。

#### Delete message

使用 `RemoveMessage` 删除指定 message 或清空全部 history。Messages State key 必须使用 `add_messages` reducer；默认 `AgentState` 已提供。

###### To remove specific messages:

```python
from langchain.messages import RemoveMessage

def delete_messages(state):
    messages = state["messages"]
    if len(messages) > 2:
        return {
            "messages": [RemoveMessage(id=message.id) for message in messages[:2]]
        }
```

###### To remove all messages:

```python
from langchain.messages import RemoveMessage
from langgraph.graph.message import REMOVE_ALL_MESSAGES

def delete_messages(state):
    return {"messages": [RemoveMessage(id=REMOVE_ALL_MESSAGES)]}
```

删除后必须保持有效消息历史：部分 provider 要求以 `user` message 开始；多数 provider 要求带 tool call 的 `assistant` message 后紧跟对应的 `tool` result，不能只删除配对的一侧。

#### Summarize messages

Trim 和 Delete 会丢失信息。需要保留旧语义时，使用内置 `SummarizationMiddleware`。

```python
from langchain.agents.middleware import SummarizationMiddleware

agent = create_agent(
    model="openai:gpt-5.5",
    tools=[...],
    middleware=[
        SummarizationMiddleware(
            model="openai:gpt-5.4-mini",
            trigger=("tokens", 4000),
            keep=("messages", 20),
        )
    ],
    checkpointer=checkpointer,
)
```

示例在 4000 tokens 时触发摘要，保留最近 20 条 messages。

### Access memory

#### tools

##### Read short-term memory in a tool

Tool 使用对 model 隐藏的 `runtime: ToolRuntime`，通过 `runtime.state` 读取 short-term memory。

```python
@tool
def get_user_info(runtime: ToolRuntime) -> str:
    """Look up user info."""
    user_id = runtime.state["user_id"]
    return "User is John Smith" if user_id == "user_123" else "Unknown user"
```

##### write short-term memory form tools

Tool 写 short-term memory 时返回 `Command`，并在 `Command.update["messages"]` 中加入 `tool_call_id=runtime.tool_call_id` 的 `ToolMessage`。

#### Prompt

使用 middleware 根据 conversation history 或 custom State fields 创建 dynamic prompt。`@dynamic_prompt` 可通过 `request.runtime.context` 读取 invocation Context。

```python
from typing import TypedDict
from langchain.agents.middleware import ModelRequest, dynamic_prompt

class CustomContext(TypedDict):
    user_name: str

@dynamic_prompt
def dynamic_system_prompt(request: ModelRequest) -> str:
    user_name = request.runtime.context["user_name"]
    return f"You are a helpful assistant. Address the user as {user_name}."
```

创建 Agent 时传入 `context_schema=CustomContext`，调用时通过 `context=CustomContext(...)` 提供值。

#### Before model

`@before_model` 在每次 model call 前处理 State，适合 trim、删除、注入或重排 messages。返回 `None` 表示无修改，返回 `dict` 表示要合并进 State 的更新。

After model

`@after_model` 在 model call 后检查 State。可读取最后一条 response，用 `RemoveMessage(id=last_message.id)` 删除不符合要求的输出。

```python
from langchain.agents.middleware import after_model
from langchain.messages import RemoveMessage

@after_model
def validate_response(state, runtime) -> dict | None:
    """Remove messages containing sensitive words."""
    stop_words = ["password", "secret"]
    last_message = state["messages"][-1]
    if any(word in last_message.content for word in stop_words):
        return {"messages": [RemoveMessage(id=last_message.id)]}
    return None
```

该 hook 修改最终 State；对于实时 Stream，只在 `after_model` 删除可能太晚，流式输出需在离开 run 前过滤。

## 16:27:01 — Event_Streaming.md

LangChain Agents 构建在 LangGraph 上，因此支持相同的 streaming stack，并提供 messages、tool calls、State 和 custom updates 等 Agent-focused projections。

多数场景使用 `stream_events(..., version="v3")`。它返回带 typed projections 的 run object，各 projection 可独立消费，无需解析 stream-mode tuples。

```python
stream = agent.stream_events(
    {"messages": [{"role": "user", "content": "What is the weather in SF?"}]},
    version="v3",
)

for message in stream.messages:
    for delta in message.text:
        print(delta, end="", flush=True)

final_state = stream.output
```

### What you can stream

| Projection | 内容 |
| :--- | :--- |
| `for event in stream` | 带完整 envelope、可访问全部 channel 的 raw protocol events |
| `stream.messages` | 每次 LLM call 的 model message streams |
| `message.text` | Text deltas 与 final text |
| `message.reasoning` | Model 支持时的 reasoning deltas |
| `message.tool_calls` | Tool-call argument chunks 与 finalized tool calls |
| `message.output` | 本次 model call 的 final message object |
| `stream.values` | Agent State snapshots |
| `stream.output` | Final Agent State |
| `stream.subgraphs` | Nested graph runs，包括 sub-agents 和普通 subgraphs |
| `stream.extensions` | Custom transformer projections |
| `stream.tool_calls` | Tool lifecycle、inputs、output deltas、final output、errors |

`stream.messages` 产生 `ChatModelStream`。每个 message stream 暴露 `.text`、`.reasoning`、`.tool_calls`、`.output`。同步 projection 可实时迭代，也可排空后读取最终值：`str(message.text)` 得到最终文本，`message.tool_calls.get()` 得到完整 Tool calls。

### Agent messages

需要每次 LLM call 的 model output 时使用 `stream.messages`。`message.output` 是 finalized AI message，包含 provider-specific content blocks；token usage 位于 `message.output.usage_metadata`。

```python
for message in stream.messages:
    print(f"[{message.node}] ", end="")
    for delta in message.text:
        print(delta, end="", flush=True)
    if message.output.usage_metadata:
        print(message.output.usage_metadata)
```

### Reasoning content

`message.reasoning` 与 `.text` 用法相同，但只有 model 发出 reasoning blocks 时才有内容。

```python
for message in stream.messages:
    for delta in message.reasoning:
        print(f"[thinking] {delta}", end="", flush=True)
    for delta in message.text:
        print(delta, end="", flush=True)
```

### Tool calls

Tool calls 有两种 projection：

- `message.tool_calls`：model 生成 Tool call 时，流式输出参数 chunks 和 finalized call；
- `stream.tool_calls`：Tool 开始执行后，流式输出 lifecycle、input、output deltas、final output、error。

前者观察 model 正在构造什么调用，后者观察 Tool 实际如何执行。

### Streaming sub-agent

当一个 `create_agent` 调用另一个已命名的 `create_agent` 时，内部 Agent 事件位于嵌套 namespace。传给 `create_agent` 的 `name=` 用于标识内部 Agent。

命名 sub-agent 出现在 `stream.subagents` projection；每个 handle 暴露 `.messages`、`.values`、`.tool_calls`、`.output`，以及 `.name`、`.cause`。

```python
for subagent in stream.subagents:
    print(f"{subagent.name}: ", end="")
    for message in subagent.messages:
        for token in message.text:
            print(token, end="", flush=True)
```

### state and final output

`stream.values` 获取运行过程中的 State snapshots；`stream.output` 获取最终 Agent State。

```python
for snapshot in stream.values:
    print(snapshot)

final_state = stream.output
```

`message.output` 是单次 model call 的最终 AI message；`stream.output` 是整个 Agent run 的最终 State。

### Multiple projections

Async code 使用 `astream_events` 与 `asyncio.gather` 并发消费多个 projections。

```python
import asyncio

stream = await agent.astream_events(input, version="v3")

async def consume_messages():
    async for message in stream.messages:
        print(await message.text)

async def consume_tool_calls():
    async for call in stream.tool_calls:
        print(call.tool_name, call.input)

await asyncio.gather(consume_messages(), consume_tool_calls())
```

Synchronous code 使用 `stream.interleave(...)`，返回 `(name, item)` 区分 projection。

```python
for name, item in stream.interleave("messages", "tool_calls", "values"):
    if name == "messages":
        print(item.text)
    elif name == "tool_calls":
        print(item.tool_name, item.input)
    elif name == "values":
        print(item)
```

### Custom updates

内置 projection 不够时，使用 custom stream transformer，并从 `stream.extensions` 读取扩展 projection。

```python
stream = agent.stream_events(
    input,
    version="v3",
    transformers=[ToolActivityTransformer],
)

for activity in stream.extensions["tool_activity"]:
    print(activity)
```

#### Register transformers on middleware

Middleware 可在 hooks 和 Tools 旁声明 transformer factories。将 `AgentMiddleware.transformers` 设置为 factories 序列；每个 factory 形如 `Callable[[tuple[str, ...]], StreamTransformer]`，框架调用 `factory(scope)`。

Root mux 的 `scope` 为 `()`，subgraph 为非空 tuple。每次返回新的 transformer，使各 subgraph 隔离。

```python
from langchain.agents.middleware import AgentMiddleware

class ToolActivityMiddleware(AgentMiddleware):
    transformers = (ToolActivityTransformer,)
```

`create_agent` 编译时合并 middleware factories 与自身 `transformers=`，顺序为：

1. 内置 `ToolCallTransformer`；
2. Middleware factories，按 middleware 顺序；
3. 调用方传给 `create_agent(transformers=...)` 的 factories。

这让内置 Tool call projection 位于消费者 transformer 之前，并让调用方条目拥有最终处理权。

`PIIMiddleware(..., apply_to_output=True)` 会在 text deltas、tool call arguments、tool outputs、State snapshots 离开 run 前清除 PII。

```python
agent = create_agent(
    model="openai:gpt-5-nano",
    tools=[],
    middleware=[
        PIIMiddleware("email", strategy="redact", apply_to_output=True),
    ],
)
```

若只依赖 `after_model` 做 State-level filtering，原始 PII 可能已通过 `stream_events(version="v3")` 实时发送给 reader。

## 16:52:27 — Streaming.md

### Overview

Streaming 支持：

- Stream Agent progress；
- Stream LLM tokens；
- Streaming thinking/reasoning tokens；
- Stream custom updates；
- 从 `updates`、`messages`、`custom` 中选择一个或多个 modes。

### Supported stream modes

将一个 mode 或多个 modes 的 list 传给 `stream` / `astream`。

| Mode | Description |
| :--- | :--- |
| `updates` | 每个 Agent step 后发送 State updates；同一步运行多个 nodes 时分别发送 |
| `messages` | 从所有调用 LLM 的 graph nodes 发送 `(token, metadata)` tuples |
| `custom` | 发送 graph nodes 内通过 stream writer 写出的 custom data |

### Agent progress

使用 `stream_mode="updates"` 的 `stream` 或 `astream`，在每个 Agent step 后接收事件。一次 Tool call 的典型顺序是：

1. **LLM node**：输出带 Tool call requests 的 `AIMessage`；
2. **Tool node**：输出带 execution result 的 `ToolMessage`；
3. **LLM node**：输出 final AI response。
