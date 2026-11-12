+++
title = "Event Streaming"
slug = "event-streaming"
weight = 20
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Event Streaming相关学习笔记与实践要点。"
+++
LangChain agents are built on LangGraph, so they support the same streaming stack with agent-focused projections for messages, tool calls, state, and custom updates.

For most situation,use Event Streaming through`stream_event(...,version="v3")`
 Event Streaming returns a run object with typed projections, so each projection can be consumed independently instead of parsing stream-mode tuples

```
stream = agent.stream_events({
    "messages": [{"role": "user", "content": "What is the weather in SF?"}],
}, version="v3")

for message in stream.messages:
    for delta in message.text:
        print(delta, end="", flush=True)

final_state = stream.output
```

# What you can stream

| Projection            | Use                                                          |
| :-------------------- | :----------------------------------------------------------- |
| `for event in stream` | Raw protocol events with full envelope and access to every channel. |
| `stream.messages`     | Model message streams, one per LLM call.                     |
| `message.text`        | Text deltas and final text for a message.                    |
| `message.reasoning`   | Reasoning deltas for models that expose reasoning content.   |
| `message.tool_calls`  | Tool-call argument chunks and finalized tool calls.          |
| `message.output`      | Final message object after the model call completes.         |
| `stream.values`       | Agent state snapshots.                                       |
| `stream.output`       | Final agent state.                                           |
| `stream.subgraphs`    | Nested graph runs (sub-agents and plain subgraphs).          |
| `stream.extensions`   | Custom transformer projections.                              |
| `stream.tool_calls`   | Tool execution lifecycle, inputs, output deltas, final output, and errors. |

`stream.messages` 会生成 `ChatModelStream` 对象。每个消息流都暴露了 `.text`、`.reasoning`、`.tool_calls` 和 `.output`。同步投影可迭代以获取实时增量，也可排空以获取最终值：使用 `str(message.text)` 获取最终文本，使用 `message.tool_calls.get()` 获取已完成的工具调用

# Agent messages

Use `stream.message` when you want model output from each LLM call

`message.output` gives you the finalized AI message,including previder-specific content blocks
read usage from `message.output.usage_metadata`.(If you want token counts)

```
stream = agent.stream_events(input, version="v3")

for message in stream.messages:
    print(f"[{message.node}] ", end="")
    for delta in message.text:
        print(delta, end="", flush=True)

    full_message = message.output
    usage = full_message.usage_metadata
    if usage:
        print(usage)
```



# Reasoning content

the same shape as text ,but only available when the model emits reasoning blocks

```
stream = agent.stream_events(input, version="v3")

for message in stream.messages:
    for delta in message.reasoning:
        print(f"[thinking] {delta}", end="", flush=True)

    for delta in message.text:
        print(delta, end="", flush=True)
```

将上面的message.text更换为message.reasoning

# Tool calls

有两种投影

- message.tool_calls在模型生成工具调用的时候,会流式传输工具调用参数块
- stream.tool_calls会在工具调用开始后流式传输工具执行的生命周期

```
stream = agent.stream_events(input, version="v3")

for message in stream.messages:
    for delta in message.reasoning:
        print(f"[thinking] {delta}", end="", flush=True)

    for delta in message.text:
        print(delta, end="", flush=True)
```

# Streaming sub-agent

当一个create_agent调用另一个已命名的create_agent时,内部智能体的时间会在一个内嵌的namespace中流动,你传递给create_agent的name= 会在stream中标识该内部智能体

命名的子智能体会在主智能体的stream.subagents投影上呈现,而每个句柄都暴露出该内部智能体的.message,.value,.tool_calls和.output加上你传递的name和.cause

```
upervisor = create_agent(
    model=init_chat_model("openai:gpt-5.5"),
    tools=[call_weather],
    name="supervisor",
)

stream = supervisor.stream_events(
    {"messages": [{"role": "user", "content": "What's the weather in Boston?"}]},
    version="v3",
)

for subagent in stream.subagents:
    print(f"{subagent.name}: ", end="")
    for message in subagent.messages:
        for token in message.text:
            print(token, end="", flush=True)
    print()
```

# state and final output

用`stream.value`来获取state的快照
用`stream.output`来获取最终的agent state

```
stream = agent.stream_events(input, version="v3")

for snapshot in stream.values:
    print(snapshot)

final_state = stream.output
```

# Multiple projections

对于 async code中的并发消费,请使用 `astream_events` with `asyncio.gather`
前者创建异步事件流,后者并发执行多个事件并且根据返回顺序聚合他们的结果

```
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

对于synchronous code,使用stream.interleave(...)

```
stream = agent.stream_events(input, version="v3")

for name, item in stream.interleave("messages", "tool_calls", "values"):
    if name == "messages":
        print(item.text)
    elif name == "tool_calls":
        print(item.tool_name, item.input)
    elif name == "values":
        print(item)
```

# Custom updates

使用custom stream transformer当你需要内置未提供的投影

```
stream = agent.stream_events(
    input,
    version="v3",
    transformers=[ToolActivityTransformer],
)

for activity in stream.extensions["tool_activity"]:
    print(activity)
```

##  Register transformers on middleware

中间件可以在其钩子和工具旁边声明流转换器工厂。工厂的形态在不同语言中有所不同：将 `AgentMiddleware` 子类上的 `transformers` 属性设置为一系列工厂。每个工厂的形态为 `Callable[[tuple[str, ...]], StreamTransformer]`，调用方式为 `factory(scope)`，其中 `scope` 是 mini-mux 作用域元组（根 mux 为 `()`，子图则为非空）。每次调用返回一个新的转换器可使每个子图保持隔离。

```
from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware


class ToolActivityMiddleware(AgentMiddleware):
    transformers = (ToolActivityTransformer,)


agent = create_agent(
    model="gpt-5-nano",
    tools=[get_weather],
    middleware=[ToolActivityMiddleware()],
)
```

在编译时，`create_agent` 会将中间件注册的工厂与传递给其自身的 `transformers=` 参数的内容进行合并。编译后图上的最终顺序为：

1. 内置的 `ToolCallTransformer`。
2. 中间件注册的工厂，按中间件顺序排列。
3. 由调用方通过 `create_agent` 提供的 `transformers=`。

这使得内置的工具调用投影排在消费者转换器之前，并让调用方提供的条目拥有最终决定权。内置的 `PIIMiddleware` 使用此钩子从流式传输的线路输出中过滤 PII。通过设置 `apply_to_output=True`，其注册的转换器会在文本增量、工具调用参数、工具输出和状态快照离开运行之前，清除其中检测到的 PII，从而关闭了一个窗口——在该窗口中，`after_model` 状态级别的过滤原本会让原始 PII 透传给 `stream_events(version="v3")` 的实时读取者。

```
from langchain.agents import create_agent
from langchain.agents.middleware import PIIMiddleware

agent = create_agent(
    model="gpt-5-nano",
    tools=[],
    middleware=[
        PIIMiddleware("email", strategy="redact", apply_to_output=True),
    ],
)
```