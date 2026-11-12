+++
title = "Streaming"
slug = "streaming"
weight = 80
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Streaming相关学习笔记与实践要点。"
+++
# Overview

实现的功能:

- Stream agent progress
- Stream LLM tokens
- Streaming thinking/reasoning tokens
- Stream custom updates
- Stream multiple modes:从updates,messages,custom中进行选择
  

# Supported stream modes

将下列的一个或者多个流式传输模式作为列表传输给stream或者astream方法

| Mode       | Description                                                  |
| :--------- | :----------------------------------------------------------- |
| `updates`  | Streams state updates after each agent step. If multiple updates are made in the same step (e.g., multiple nodes are run), those updates are streamed separately. |
| `messages` | Streams tuples of `(token, metadata)` from any graph nodes where an LLM is invoked. |
| `custom`   | Streams custom data from inside your graph nodes using the stream writer. |

# Agent progress

使用带有stream_mode ="updates"的stream或者astream方法
将在每个agent step之后发送一个事件

例子:
在一次tool call之后,你应该看到下列更新

- **LLM node**: [`AIMessage`](https://reference.langchain.com/python/langchain-core/messages/ai/AIMessage) with tool call requests
- **Tool node**: [`ToolMessage`](https://reference.langchain.com/python/langchain-core/messages/tool/ToolMessage) with execution result
- **LLM node**: Final AI response

通过`config`传递thread_id以便checkpointer进行保存和后续的resume
也可以传递context,后续可以使用runtime.context进行访问

# LLM tokens

使用`stream_mode = "message"`来访问token usage
在输出中可以看到agent的工具调用和最终的response

# Custom updates

想要流式传输工具执行的过程(或结果),使用``get_stream_writer `inside the tool

```
from langchain.agents import create_agent
from langgraph.config import get_stream_writer  


def get_weather(city: str) -> str:
    """Get weather for a given city."""
    writer = get_stream_writer()
    # stream any arbitrary data
    writer(f"Looking up data for city: {city}")
    writer(f"Acquired data for city: {city}")
    return f"It's always sunny in {city}!"

agent = create_agent(
    model="claude-sonnet-4-6",
    tools=[get_weather],
)

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "What is the weather in SF?"}]},
    stream_mode="custom",
    version="v2",
):
    if chunk["type"] == "custom":
        print(chunk["data"])
```

# Stream multiple modes

通过将它们以mode列表的形式传输:stream_mode=["updates","custom"]

每一段streamed chunk都是`StreamPart`的dict with type,ns and data 的keys
通过chunk["type"]来决定流式模式,通过chunk["data"]来访问负载

```

```

```
from langchain.agents import create_agent
from langgraph.config import get_stream_writer


def get_weather(city: str) -> str:
    """Get weather for a given city."""
    writer = get_stream_writer()
    writer(f"Looking up data for city: {city}")
    writer(f"Acquired data for city: {city}")
    return f"It's always sunny in {city}!"

agent = create_agent(
    model="gpt-5-nano",
    tools=[get_weather],
)

for chunk in agent.stream(
    {"messages": [{"role": "user", "content": "What is the weather in SF?"}]},
    stream_mode=["updates", "custom"],
    version="v2",
):
    print(f"stream_mode: {chunk['type']}")
    print(f"content: {chunk['data']}")
    print("\n")
```

# Common patterns

常见的几种应用场景

## Stream thinking/reasoning tokens

一些模型会在产生最终的answer之前在内部进行思考
可以通过过滤standard contnent blocks中的type = "reasoning"的部分来这些thinging/reasoning tokens

需要使用的mode为message即,stream_mode ="message"(与上文相符合)

```
stream = agent.stream_events(
    {"messages": [{"role": "user", "content": "What is the weather in SF?"}]},
    version="v3",
)
for message in stream.messages:
    for token in message.reasoning:
        print(f"[thinking] {token}", end="")
    for token in message.text:
        print(token, end="", flush=True)
```

## Streaming tool calls

if you want to stream both:

1. Partial JSON as [tool calls](https://docs.langchain.com/oss/python/langchain/models#tool-calling) are generated
2. The completed, parsed tool calls that are executed

前者可以通过指定stream_mode= "message"
后者,根据是否在state中被tracked:
True: 指定stream_mode = ["messages","updates"],并通过state updates来访问(如下所示)
False: 使用custom updates 或者 aggregate the chunks during the streaming loop ([next section](https://docs.langchain.com/oss/python/langchain/streaming#accessing-completed-messages)).

```
for chunk in agent.stream(
    {"messages": [input_message]},
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk):
            _render_message_chunk(token)
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source in ("model", "tools"):  # `source` captures node name
                _render_completed_message(update["messages"][-1])
```

### Accessing completed messages

在message不通过state updates反映时采取的途径之一
通过aggrrgate message chunks in the streaming loop

1.使用stream_writer inside the tool
2.如果你不能添加自定义的时间到stream中时,你可以流式传输中聚合消息块

## Streaming with human-in-the-loop

解决human-in-the-loop interrupts:

1. 为agent配置hunman-in-the-loop middleare 和 checkpointer
2. 搜集在"update"流式传输模式下的interrupts
3. 通过command来对这些interrupts进行响应

```
from typing import Any

from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware
from langchain.messages import AIMessage, AIMessageChunk, AnyMessage, ToolMessage
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.types import Command, Interrupt


def get_weather(city: str) -> str:
    """Get weather for a given city."""

    return f"It's always sunny in {city}!"


checkpointer = InMemorySaver()

agent = create_agent(
    "openai:gpt-5.5",
    tools=[get_weather],
    middleware=[
        HumanInTheLoopMiddleware(interrupt_on={"get_weather": True}),
    ],
    checkpointer=checkpointer,
)


def _render_message_chunk(token: AIMessageChunk) -> None:
    if token.text:
        print(token.text, end="|")
    if token.tool_call_chunks:
        print(token.tool_call_chunks)


def _render_completed_message(message: AnyMessage) -> None:
    if isinstance(message, AIMessage) and message.tool_calls:
        print(f"Tool calls: {message.tool_calls}")
    if isinstance(message, ToolMessage):
        print(f"Tool response: {message.content_blocks}")


def _render_interrupt(interrupt: Interrupt) -> None:
    interrupts = interrupt.value  
    for request in interrupts["action_requests"]:
        print(request["description"])


input_message = {
    "role": "user",
    "content": (
        "Can you look up the weather in Boston and San Francisco?"
    ),
}
config = {"configurable": {"thread_id": "some_id"}}
interrupts = []
for chunk in agent.stream(
    {"messages": [input_message]},
    config=config,
    stream_mode=["messages", "updates"],
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk):
            _render_message_chunk(token)
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source in ("model", "tools"):
                _render_completed_message(update["messages"][-1])
            if source == "__interrupt__":
                interrupts.extend(update)
                _render_interrupt(update[0])
```

接下来,为每一个interrupt收集对应的decision,并且decision的顺序与我们收集的action对应

```
def _get_interrupt_decisions(interrupt: Interrupt) -> list[dict]:
    return [
        {
            "type": "edit",
            "edited_action": {
                "name": "get_weather",
                "args": {"city": "Boston, U.K."},
            },
        }
        if "boston" in request["description"].lower()
        else {"type": "approve"}
        for request in interrupt.value["action_requests"]
    ]

decisions = {}
for interrupt in interrupts:
    decisions[interrupt.id] = {
        "decisions": _get_interrupt_decisions(interrupt)
    }

decisions
```

我们可以通过向流式传输的循环传入一个command来resume

```
interrupts = []
for chunk in agent.stream(
    Command(resume=decisions),
    config=config,
    stream_mode=["messages", "updates"],
    version="v2",
):
    # Streaming loop is unchanged
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if isinstance(token, AIMessageChunk):
            _render_message_chunk(token)
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source in ("model", "tools"):
                _render_completed_message(update["messages"][-1])
            if source == "__interrupt__":
                interrupts.extend(update)
                _render_interrupt(update[0])
```

## Streaming from sub-agents

当agent中有多个LLMs时,需要对其来源进行消歧
在创建agent时使用`name`参数,该参数在"message"的stream_mode中可以通过lc_agent_name键中的metadata访问
ps: 在创建stream时specify `subgraph是= True`

```
from typing import Any

from langchain.agents import create_agent
from langchain.chat_models import init_chat_model
from langchain.messages import AIMessage, AnyMessage


def get_weather(city: str) -> str:
    """Get weather for a given city."""

    return f"It's always sunny in {city}!"


weather_model = init_chat_model("openai:gpt-5.5")
weather_agent = create_agent(
    model=weather_model,
    tools=[get_weather],
    name="weather_agent",
)


def call_weather_agent(query: str) -> str:
    """Query the weather agent."""
    result = weather_agent.invoke({
        "messages": [{"role": "user", "content": query}]
    })
    return result["messages"][-1].text


supervisor_model = init_chat_model("openai:gpt-5.5")
agent = create_agent(
    model=supervisor_model,
    tools=[call_weather_agent],
    name="supervisor",
)
```

```
def _render_message_chunk(token: AIMessageChunk) -> None:
    if token.text:
        print(token.text, end="|")
    if token.tool_call_chunks:
        print(token.tool_call_chunks)


def _render_completed_message(message: AnyMessage) -> None:
    if isinstance(message, AIMessage) and message.tool_calls:
        print(f"Tool calls: {message.tool_calls}")
    if isinstance(message, ToolMessage):
        print(f"Tool response: {message.content_blocks}")


input_message = {"role": "user", "content": "What is the weather in Boston?"}
current_agent = None
for chunk in agent.stream(
    {"messages": [input_message]},
    stream_mode=["messages", "updates"],
    subgraphs=True,
    version="v2",
):
    if chunk["type"] == "messages":
        token, metadata = chunk["data"]
        if agent_name := metadata.get("lc_agent_name"):
            if agent_name != current_agent:
                print(f"🤖 {agent_name}: ")
                current_agent = agent_name  
        if isinstance(token, AIMessageChunk):
            _render_message_chunk(token)
    elif chunk["type"] == "updates":
        for source, update in chunk["data"].items():
            if source in ("model", "tools"):
                _render_completed_message(update["messages"][-1])
```

# Disable streaming

初始化时: set `streaming = False`

# v2 streaming format

Pass `version="v2"` to `stream()` or `astream()` to get a unified output format. Every chunk is a `StreamPart` dict with `type`, `ns`, and `data` keys — the same shape regardless of stream mode or number of modes:

The v2 format also improves `invoke()` — it returns a `GraphOutput` object with `.value` and `.interrupts` attributes, cleanly separating state from interrupt metadata: