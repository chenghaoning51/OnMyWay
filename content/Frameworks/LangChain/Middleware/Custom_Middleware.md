+++
title = "Custom Middleware"
slug = "custom-middleware"
weight = 40
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Custom Middleware相关学习笔记与实践要点。"
+++
通过在agent工作流中实现hook来构建自定义的midddleware

# Hooks

two types:

## Node-style hook

在特定的执行点顺序执行.Use for validation,logging and state updates.



| Hook           | When it runs                                |
| :------------- | :------------------------------------------ |
| `before_agent` | Before agent starts (once per invocation)   |
| `before_model` | Before each model call                      |
| `after_model`  | After each model response                   |
| `after_agent`  | After agent completes (once per invocation) |

**Wrap-style hooks** run around each call, giving you control over execution:

| Hook              | When it runs           |
| :---------------- | :--------------------- |
| `wrap_model_call` | Around each model call |
| `wrap_tool_call`  | Around each tool call  |

```
from langchain.agents.middleware import before_model, after_model, AgentState
from langchain.messages import AIMessage
from langgraph.runtime import Runtime
from typing import Any


@before_model(can_jump_to=["end"])
def check_message_limit(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    if len(state["messages"]) >= 50:
        return {
            "messages": [AIMessage("Conversation limit reached.")],
            "jump_to": "end"
        }
    return None

@after_model
def log_response(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    print(f"Model returned: {state['messages'][-1].content}")
    return None
```

## Warp-style hooks

拦截执行并且控制出处理机制的调用时机.Use for retries,caching,and information.
由你决定处理机制是被调用zero times(short-circuit短路),once(normal flow), or multiple times(retry logic)

**Available hooks:**

- `wrap_model_call` - Around each model call
- `wrap_tool_call` - Around each tool call

```python
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse
from typing import Callable


@wrap_model_call
def retry_model(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    for attempt in range(3):
        try:
            return handler(request)
        except Exception as e:
            if attempt == 2:
                raise
            print(f"Retry {attempt + 1}/3 after error: {e}")
```

# State updates

Both node-style and warp-style hooks can update agent state. But the mechanism differs.

Node-style hooks:
直接返回一个dict, 由graph的reducers将该dict应用到agent's state

```
from langchain.agents.middleware import after_model, AgentState
from langgraph.runtime import Runtime
from typing import Any
from typing_extensions import NotRequired


class TrackingState(AgentState):
    model_call_count: NotRequired[int]


@after_model(state_schema=TrackingState)
def increment_after_model(state: TrackingState, runtime: Runtime) -> dict[str, Any] | None:
    return {"model_call_count": state.get("model_call_count", 0) + 1}
```

Warp-style hooks:
对于model calls,返回`ExtendedModeResponse` with a `Command`来通过model response插入state updates

```python
from typing import Callable
from langchain.agents.middleware import (
    wrap_model_call,
    ModelRequest,
    ModelResponse,
    AgentState,
    ExtendedModelResponse
)
from langgraph.types import Command
from typing_extensions import NotRequired

class UsageTrackingState(AgentState):
    """Agent state with token usage tracking."""

    last_model_call_tokens: NotRequired[int]


@wrap_model_call(state_schema=UsageTrackingState)
def track_usage(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ExtendedModelResponse:
    response = handler(request)
    return ExtendedModelResponse(
        model_response=response,
        command=Command(update={"last_model_call_tokens": 150}),
    )
```

[`Command`](https://reference.langchain.org.cn/python/langgraph/types/Command) 会流经图的 reducer，因此更新会被正确应用，并且消息是累加的，而不是替换现有状态



对于tool calls,直接返回一个`Command`

### Composition with multiple middleware

当多个Middleware layer返回`ExtendedModelResponse`时,他们的命令会进行组合

- 命令通过reducer应用:每个Command都会成为一个独立的状态更新,对于消息而言,他们是additive
- 冲突时外层优先
- 重试安全:如果外层的Middleware会导致handler()的多次调用,会抛弃早期的调用命令

```
from typing import Annotated, Callable

from langchain.agents.middleware import (
    AgentMiddleware,
    AgentState,
    ExtendedModelResponse,
    ModelRequest,
    ModelResponse,
)
from langchain.messages import SystemMessage
from langgraph.types import Command
from typing_extensions import NotRequired


def _last_wins(_a: str, b: str) -> str:
    """Reducer: last writer wins (outer overwrites inner)."""
    return b


class CustomMiddlewareState(AgentState):
    """Agent state: trace_layer uses last-wins (outer wins), messages use additive reducer."""

    # Non-reducer field with last-wins: both middleware write; outermost value wins
    trace_layer: NotRequired[Annotated[str, _last_wins]]


class OuterMiddleware(AgentMiddleware):
    def wrap_model_call(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ) -> ExtendedModelResponse:
        response = handler(request)
        return ExtendedModelResponse(
            model_response=response,
            command=Command(update={
                "trace_layer": "outer",
                "messages": [SystemMessage(content="[Outer ran]")],
            }),
        )


class InnerMiddleware(AgentMiddleware):
    """Adds trace_layer and message. Outer adds to same keys; trace_layer: outer wins, messages: additive."""

    def wrap_model_call(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ):
        response = handler(request)
        return ExtendedModelResponse(
            model_response=response,
            command=Command(update={
                "trace_layer": "inner",
                "messages": [SystemMessage(content="[Inner ran]")],
            }),
        )
```

# Create middleware

In two ways:

## Decorator-base middleware

for single-hook middleware. To warp individual functions.

**Node-style:**

- [`@before_agent`](https://reference.langchain.com/python/langchain/agents/middleware/types/before_agent) - Runs before agent starts (once per invocation)
- [`@before_model`](https://reference.langchain.com/python/langchain/agents/middleware/types/before_model) - Runs before each model call
- [`@after_model`](https://reference.langchain.com/python/langchain/agents/middleware/types/after_model) - Runs after each model response
- [`@after_agent`](https://reference.langchain.com/python/langchain/agents/middleware/types/after_agent) - Runs after agent completes (once per invocation)

**Wrap-style:**

- [`@wrap_model_call`](https://reference.langchain.com/python/langchain/agents/middleware/types/wrap_model_call) - Wraps each model call with custom logic
- [`@wrap_tool_call`](https://reference.langchain.com/python/langchain/agents/middleware/types/wrap_tool_call) - Wraps each tool call with custom logic

**Convenience:**

- [`@dynamic_prompt`](https://reference.langchain.com/python/langchain/agents/middleware/types/dynamic_prompt) - Generates dynamic system prompts

**When to use decorators:**

- Single hook needed
- No complex configuration
- Quick prototyping

```
from langchain.agents.middleware import (
    before_model,
    wrap_model_call,
    AgentState,
    ModelRequest,
    ModelResponse,
)
from langchain.agents import create_agent
from langgraph.runtime import Runtime
from typing import Any, Callable


@before_model
def log_before_model(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    print(f"About to call model with {len(state['messages'])} messages")
    return None

@wrap_model_call
def retry_model(
    request: ModelRequest,
    handler: Callable[[ModelRequest], ModelResponse],
) -> ModelResponse:
    for attempt in range(3):
        try:
            return handler(request)
        except Exception as e:
            if attempt == 2:
                raise
            print(f"Retry {attempt + 1}/3 after error: {e}")

agent = create_agent(
    model="gpt-5.5",
    middleware=[log_before_model, retry_model],
    tools=[...],
)
```

## Class-based middleware

适用于multiple hooks和更复杂的configuration;适用于你需要同时实现同步和异步for the same hook,或者你想要在一个组件内部组合多个hooks

py 的 `AgentMiddleware`子类会声明三个属性,agent factory会在编译时会自动提取

- state_schema:适用自定义的字段拓展agent state
- tools:注册middleware承载的工具
- transformer:注册范围感知的流转化工厂

下面这个例子体现了多个hooks和同时实现同步与异步

```
from langchain.agents.middleware import (
    AgentMiddleware,
    AgentState,
    ModelRequest,
    ModelResponse,
)
from langgraph.runtime import Runtime
from typing import Any, Callable

class LoggingMiddleware(AgentMiddleware):
    def before_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        print(f"About to call model with {len(state['messages'])} messages")
        return None

    def after_model(self, state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
        print(f"Model returned: {state['messages'][-1].content}")
        return None

    async def abefore_model(
        self, state: AgentState, runtime: Runtime
    ) -> dict[str, Any] | None:
        # Async version of before_model
        return None

    async def aafter_model(
        self, state: AgentState, runtime: Runtime
    ) -> dict[str, Any] | None:
        # Async version of after_model
        print(f"Model returned: {state['messages'][-1].content}")
        return None


agent = create_agent(
    model="gpt-5.5",
    middleware=[LoggingMiddleware()],
    tools=[...],
)
```

适用场景:

- 同时定义同步与异步实现for same hook
- multiple hooks needed in a single middleware
- 复杂的定义需要
- 有跨项目的复用需求

### Custom state schema

when you need to track state across hooks,middleware can extend the agent's state with custom properties.

- 跨执行跟踪状态
- 在hooks之间共享数据
- 实现横切聚焦
- 执行条件性决策

```py
from langchain.agents import create_agent
from langchain.messages import HumanMessage
from langchain.agents.middleware import AgentState, before_model, after_model
from typing_extensions import NotRequired
from typing import Any
from langgraph.runtime import Runtime


class CustomState(AgentState):
    model_call_count: NotRequired[int]
    user_id: NotRequired[str]


@before_model(state_schema=CustomState, can_jump_to=["end"])
def check_call_limit(state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
    count = state.get("model_call_count", 0)
    if count > 10:
        return {"jump_to": "end"}
    return None


@after_model(state_schema=CustomState)
def increment_counter(state: CustomState, runtime: Runtime) -> dict[str, Any] | None:
    return {"model_call_count": state.get("model_call_count", 0) + 1}


agent = create_agent(
    model="gpt-5.5",
    middleware=[check_call_limit, increment_counter],
    tools=[],
)

# Invoke with custom state
result = agent.invoke({
    "messages": [HumanMessage("Hello")],
    "model_call_count": 0,
    "user_id": "user-123",
})
```

### Custom stream transformer(目前不知道有什么用处)

中间件可以注册流转换器工厂，将来自活动智能体流的事件投影到类型化的扩展通道上。这对于显现计数器、旁路伪影（side-channel artifacts）、部分输出或网络层脱敏（wire-level redaction）非常有用，而无需与框架的内置投影耦合。在编译时，中间件注册的工厂将与调用者直接传递给智能体工厂的任何内容合并。[最终排序规则](https://docs.langchain.org.cn/oss/python/langchain/event-streaming#register-transformers-on-middleware)使内置的 `ToolCallTransformer` 处于最前面，并让调用者提供的条目排在最后。将 `transformers` 类属性设置为一个由工厂可调用对象组成的元组。每个工厂的形式为 `Callable[[tuple[str, ...]], StreamTransformer]` 并通过 `factory(scope)` 进行调用，其中 `scope` 是 mini-mux 作用域元组（`()` 表示根目录，非空表示子图）；每次调用都返回一个新的转换器，以保持每个子图的隔离。

```py
from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware


class ToolActivityMiddleware(AgentMiddleware):
    transformers = (ToolActivityTransformer,)


agent = create_agent(
    model="gpt-5-nano",
    tools=[...],
    middleware=[ToolActivityMiddleware()],
)
```

# Execution order

key rules:

- `before_*` hooks: First to last
- `after_*` hooks: Last to first (reverse)
- `wrap_*` hooks: Nested (first middleware wraps all others)

```
Before 钩子按顺序运行
middleware1.before_agent()
middleware2.before_agent()
middleware3.before_agent()
智能体循环开始
middleware1.before_model()
middleware2.before_model()
middleware3.before_model()
Wrap 钩子像函数调用一样嵌套
middleware1.wrap_model_call() → middleware2.wrap_model_call() → middleware3.wrap_model_call() → 模型
After 钩子按相反顺序运行
middleware3.after_model()
middleware2.after_model()
middleware1.after_model()
智能体循环结束
middleware3.after_agent()
middleware2.after_agent()
middleware1.after_agent()
```

# Agent jumps

为了提前结束middleware,发挥一个 dictionary with `jump_to`

可选的 targets:

- `'end'`:跳转到agent执行的end(或者first after_agent hook)
- `'tools'`:跳转到tool节点
- `'model'`跳转到model节点(或者first before_model hook)

```
from langchain.agents.middleware import after_model, hook_config, AgentState
from langchain.messages import AIMessage
from langgraph.runtime import Runtime
from typing import Any


@after_model
@hook_config(can_jump_to=["end"])
def check_for_blocked(state: AgentState, runtime: Runtime) -> dict[str, Any] | None:
    last_message = state["messages"][-1]
    if "BLOCKED" in last_message.content:
        return {
            "messages": [AIMessage("I cannot respond to that request.")],
            "jump_to": "end"
        }
    return None
```

# Configure tracing

自己看

# Best practices

1. 单一职责
2. 优雅地处理错误
3. 使用正确地hook类型
4. 清晰地记录每一个自定义的state属性
5. 在集成之前对于每一个中间件进行单元测试
6. 考虑执行的顺序:将关键的middleware放在第一位(前面)
7. 使用内置的中间件

# Examples

## Dynamic prompt

在运行时动态的调整提示词,以注入上下文,用户特定的指令和其他的信息
这是最常用的middleware之一
使用`ModelRequest`中的`system_message`字段来阅读和修改系统提示词.他包含了一个`SystemMessage`对象

```
from collections.abc import Callable

from langchain.agents.middleware import AgentMiddleware, ModelRequest, ModelResponse


class ContextMiddleware(AgentMiddleware):
    def wrap_model_call(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ) -> ModelResponse:
        new_content = list(request.system_message.content_blocks) + [
            {"type": "text", "text": "Additional context."}
        ]
        new_system_message = SystemMessage(content=new_content)
        return handler(request.override(system_message=new_system_message))
```

```
ModelRequest.system_message 始终是 SystemMessage 对象，即使智能体是使用 system_prompt="string" 创建的
使用 SystemMessage.content_blocks 将内容作为块列表进行访问，无论原始内容是字符串还是列表
修改系统消息时，请使用 content_blocks 并追加新块，以保留现有结构
对于缓存控制等高级用例，您可以将 SystemMessage 对象直接传递给 create_agent 的 system_prompt 参数
```

## Dynamic model selection

```
from collections.abc import Callable

from langchain.agents.middleware import AgentMiddleware, ModelRequest, ModelResponse
from langchain.chat_models import init_chat_model

complex_model = init_chat_model("claude-sonnet-4-6")
simple_model = init_chat_model("claude-haiku-4-5-20251001")


class DynamicModelMiddleware(AgentMiddleware):
    def wrap_model_call(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ) -> ModelResponse:
        if len(request.messages) > 10:
            model = complex_model
        else:
            model = simple_model
        return handler(request.override(model=model))
```

## Dynamically selecting tools

动态选择工具
适用于:需要减短prompts;更好的准确性;访问控制

```
from langchain.agents import create_agent
from langchain.agents.middleware import AgentMiddleware, ModelRequest, ModelResponse
from typing import Callable


class ToolSelectorMiddleware(AgentMiddleware):
    def wrap_model_call(
        self,
        request: ModelRequest,
        handler: Callable[[ModelRequest], ModelResponse],
    ) -> ModelResponse:
        """Middleware to select relevant tools based on state/context."""
        # Select a small, relevant subset of tools based on state/context
        relevant_tools = select_relevant_tools(request.state, request.runtime)
        return handler(request.override(tools=relevant_tools))

agent = create_agent(
    model="gpt-5.5",
    tools=all_tools,  # All available tools need to be registered upfront
    middleware=[ToolSelectorMiddleware()],
)
```

## Tool calling monitoring

```py
from collections.abc import Callable

from langchain.agents.middleware import AgentMiddleware
from langchain.messages import ToolMessage
from langchain.tools.tool_node import ToolCallRequest
from langgraph.types import Command


class ToolMonitoringMiddleware(AgentMiddleware):
    def wrap_tool_call(
        self,
        request: ToolCallRequest,
        handler: Callable[[ToolCallRequest], ToolMessage | Command],
    ) -> ToolMessage | Command:
        print(f"Executing tool: {request.tool_call['name']}")
        print(f"Arguments: {request.tool_call['args']}")
        try:
            result = handler(request)
            print("Tool completed successfully")
            return result
        except Exception as e:
            print(f"Tool failed: {e}")
            raise
```

Prompt caching(Anthropic)

- `ModelRequest.system_message` 始终是 [`SystemMessage`](https://reference.langchain.org.cn/python/langchain-core/messages/system/SystemMessage) 对象，即使智能体是使用 `system_prompt="string"` 创建的
- 使用 `SystemMessage.content_blocks` 将内容作为块列表进行访问，无论原始内容是字符串还是列表
- 修改系统消息时，请使用 `content_blocks` 并追加新块，以保留现有结构
- 对于缓存控制等高级用例，您可以将 [`SystemMessage`](https://reference.langchain.org.cn/python/langchain-core/messages/system/SystemMessage) 对象直接传递给 `create_agent` 的 `system_prompt` 参数