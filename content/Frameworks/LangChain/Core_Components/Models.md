+++
title = "Models"
slug = "models"
weight = 60
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Models相关学习笔记与实践要点。"
+++
In addition to text generation,many LLMs provide :tool calling,Structured output,Multimodality,Reasoning
different model excel at different tasks

LangChain has  Standard model interface,which allow you to experiment with and switch models

# Basic usage

1.with agents 2.Standalone(outside the agent loop)

## Initialize a model

the easiest way: use `init_chat_model`

```
import os
from langchain.chat_models import init_chat_model

os.environ["OPENAI_API_KEY"] = "sk-..."

model = init_chat_model("gpt-5.5")
```

key method:
invoke,streaming.patch(批量处理)

## Parameters

model: string (required)
api_key: string
temperature: number
max_tokens: number
timeout: number
max_retries: number (default: 6)

```
model = init_chat_model(
    "claude-sonnet-4-6",
    # Kwargs passed to the model:
    temperature=0.7,
    timeout=30,
    max_tokens=1000,
    max_retries=6,  # Default; increase for unreliable networks
)
```

## Connection resilience(连接韧性?)

LangChain chat models automatically retry failed API requests with exponential backoff

By default, models retry up to **6 times** for network errors, rate limits (429), and server errors (5xx). Client errors like 401 (unauthorized) or 404 are not retried.

Use **max_retries** and **timeout** 

### Invocation

### invoke:

with a message along with a thread_id
role of a message: models use it to verify who sent the message

### Streaming:

Calling [`stream()`](https://reference.langchain.com/python/langchain-core/language_models/chat_models/BaseChatModel/stream) returns an iterator that yields output chunks as they are produced. You can use a loop to process each chunk in real-time:

Return `AIMessageChunk`objects ,each chunk in a stream is designed to be gathered into a full message via summation

```
full = None  # None | AIMessageChunk
for chunk in model.stream("What color is the sky?"):
    full = chunk if full is None else full + chunk
    print(full.text)
```

### Batch

Batching a collection of independent requests to a model can significantly improve performance and reduce costs, as the processing can be done in parallel:

Use `batch_as_completed()` to stream result,but the response is out of order


## Tool calling

1. A schema, including the name of the tool, a description, and/or argument definitions (often a JSON schema)
2. A function or coroutine to execute.

Basic tool calling flow:

![image-20260919161339819](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260919161339819.png)

Use `bind_tools` to make tools you have defined available

```
from langchain.tools import tool

@tool
def get_weather(location: str) -> str:
    """Get the weather at a location."""
    return f"It's sunny in {location}."


model_with_tools = model.bind_tools([get_weather])
```

#### Common way to use tool calling

- Tool execution loop
- Forcing tool calls
- Parallel tool calls
- Streaming tool calls:
  tool calls are progressively built through [`ToolCallChunk`](https://reference.langchain.com/python/langchain-core/messages/tool/ToolCallChunk)
  You can accumulate chunks to build complete tool calls

## Structured output

Provide their response in a format matching a given schema
LangChain supports multiple schema types and methods for enforcing structured output.

[Pydantic models](https://docs.pydantic.dev/latest/concepts/models/#basic-model-usage) provide the richest feature set with field validation, descriptions, and nested structures.

Python’s `TypedDict` provides a simpler alternative to Pydantic models, ideal when you don’t need runtime validation.

Provide a [JSON Schema](https://json-schema.org/understanding-json-schema/about) for maximum control and interoperability.

1.raw message和parsed message并存 2.nested structure

## Multimodal

You can use content block to provide ono-text data to the model
If the response contains multimodal data,the resulting AIMessage

will have content blocks with multimodal types

## Reasoning

Many models are capable of performing multi-step reasoning to arrive at a conclusion. This involves breaking down complex problems into smaller, more 

manageable steps.**If supported by the underlying model,** you can surface this reasoning process to better understand how the model arrived at its final answer.

Depending on the model,you can sometimes specify the level of effort it should put into reasoning. Using reasoning_effort parameter when invoking.

## Local models

## Prompt caching

ou can engage caching at three levels:

- Implicit provider caching:
- Provider-level explicit controls(显式):
  providers let you manually indicate cache points for greater control or to guarantee cost savings. These mirror the underlying provider/API behavior. Examples:
  - [`ChatOpenAI`](https://reference.langchain.com/python/langchain-openai/chat_models/base/ChatOpenAI) (via `prompt_cache_key`)
  - Anthropic content-block [`cache_control`](https://docs.langchain.com/oss/python/integrations/chat/anthropic#prompt-caching)
  - [Gemini](https://reference.langchain.com/python/integrations/langchain_google_genai/).
  - AWS Bedrock [`cachePoint`](https://docs.langchain.com/oss/python/integrations/chat/bedrock#prompt-caching) blocks

- LangChain middleware:

   for agents, middleware lets LangChain optimize caching of stable system prompt and tool content. Examples:

  - Anthropic’s [`AnthropicPromptCachingMiddleware`](https://docs.langchain.com/oss/python/integrations/middleware/anthropic#prompt-caching)
  - AWS Bedrock’s [`BedrockPromptCachingMiddleware`](https://docs.langchain.com/oss/python/integrations/middleware/aws#prompt-caching)

Cache usage will be reflected in the [usage metadata](https://docs.langchain.com/oss/python/langchain/messages#token-usage) of the model response.

## Server-side tool use

Some providers support server-side [tool-calling](https://docs.langchain.com/oss/python/langchain/models#tool-calling) loops: models can interact with web search, code interpreters, and other tools and analyze the results in a single conversational turn.

If a model invokes a tool server-side, the content of the response message will include content representing the invocation and result of the tool. Accessing the [content blocks](https://docs.langchain.com/oss/python/langchain/messages#standard-content-blocks) of the response will return the server-side tool calls and results in a provider-agnostic format:

```
from langchain.chat_models import init_chat_model

model = init_chat_model("gpt-5.4-mini")

tool = {"type": "web_search"}
model_with_tools = model.bind_tools([tool])

response = model_with_tools.invoke("What was a positive news story from today?")
print(response.content_blocks)
```

```
[
    {
        "type": "server_tool_call",
        "name": "web_search",
        "args": {
            "query": "positive news stories today",
            "type": "search"
        },
        "id": "ws_abc123"
    },
    {
        "type": "server_tool_result",
        "tool_call_id": "ws_abc123",
        "status": "success"
    },
    {
        "type": "text",
        "text": "Here are some positive news stories from today...",
        "annotations": [
            {
                "end_index": 410,
                "start_index": 337,
                "title": "article title",
                "type": "citation",
                "url": "..."
            }
        ]
    }
]
```

This represents a single conversational turn; there are no associated [ToolMessage](https://docs.langchain.com/oss/python/langchain/messages#tool-message) objects that need to be passed in as in client-side [tool-calling](https://docs.langchain.com/oss/python/langchain/models#tool-calling).

## Model exceptions

Major integration packages raise standard exception types from `langchain_core.exceptions` for common model failures such as authentication errors, rate limits, and timeouts. These exceptions inherit from both the LangChain base type and the provider SDK’s own exception type, so you can catch either one:

## Rate limiting

To control your call frequency ,and i you hit it, you will receive a rate limit error

To help manage rate limits, chat model integrations accept a `rate_limiter` parameter that can be provided during initialization to control the rate at which requests are made.

## Base URL and proxy settings

You can configure a custom base URL for providers that implement the OpenAI Chat Completions API.

**Custom base URL:**

```
model = init_chat_model(
    model="MODEL_NAME",
    model_provider="openai",
    base_url="BASE_URL",
    api_key="YOUR_API_KEY",
)
```

**HTTP proxy configuration:**

```
from langchain_openai import ChatOpenAI

model = ChatOpenAI(
    model="gpt-5.5",
    openai_proxy="http://proxy.example.com:8080"
)
```

## Log probabilities

## Token usage



A number of model providers return token usage information as part of the invocation response.

You can track aggregate token counts across models in an application using either a callback or context manager, as shown below:

**Callback:**

```
You can track aggregate token counts across models in an application using either a callback or context manager, as shown below:
```

**Context manager:**

```
from langchain.chat_models import init_chat_model
from langchain_core.callbacks import get_usage_metadata_callback

model_1 = init_chat_model(model="gpt-5.4-mini")
model_2 = init_chat_model(model="claude-haiku-4-5-20251001")

with get_usage_metadata_callback() as cb:
    model_1.invoke("Hello")
    model_2.invoke("Hello")
    print(cb.usage_metadata)
```

## Invocation config

When invoking a model, you can pass additional configuration through the `config` parameter using a [`RunnableConfig`](https://reference.langchain.com/python/langchain-core/runnables/config/RunnableConfig) dictionary. This provides run-time control over execution behavior, callbacks, and metadata tracking.

```
response = model.invoke(
    "Tell me a joke",
    config={
        "run_name": "joke_generation",      # Custom name for this run
        "tags": ["humor", "demo"],          # Tags for categorization
        "metadata": {"user_id": "123"},     # Custom metadata
        "callbacks": [my_callback_handler], # Callback handlers
    }
)
```

Key configuration attributes
run_name: string : identifier
tags: string[]
metadata: object
max_concurrency: number
callbacks: array
recursion_limit: number


Configurable models:
You can also create a runtime-configurable model by specifying [`configurable_fields`](https://reference.langchain.com/python/langchain_core/language_models/#langchain_core.language_models.chat_models.BaseChatModel.configurable_fields). If you don’t specify a model value, then `'model'` and `'model_provider'` will be configurable by default.

```
from langchain.chat_models import init_chat_model

configurable_model = init_chat_model(temperature=0)

configurable_model.invoke(
    "what's your name",
    config={"configurable": {"model": "gpt-5-nano"}},  # Run with GPT-5-Nano
)
configurable_model.invoke(
    "what's your name",
    config={"configurable": {"model": "claude-sonnet-4-6"}},  # Run with Claude
)
```

## Dynamic model selection

Dynamic models are selected at runtime based on the current state and context. This enables sophisticated routing logic and cost optimization.

To use a dynamic model, create middleware using the [`@wrap_model_call`](https://reference.langchain.com/python/langchain/agents/middleware/types/wrap_model_call) decorator that modifies the model in the request:

```
from langchain_openai import ChatOpenAI
from langchain.agents import create_agent
from langchain.agents.middleware import wrap_model_call, ModelRequest, ModelResponse


basic_model = ChatOpenAI(model="gpt-5.4-mini")
advanced_model = ChatOpenAI(model="gpt-5.5")

@wrap_model_call
def dynamic_model_selection(request: ModelRequest, handler) -> ModelResponse:
    """Choose model based on conversation complexity."""
    message_count = len(request.state["messages"])

    if message_count > 10:
        # Use an advanced model for longer conversations
        model = advanced_model
    else:
        model = basic_model

    return handler(request.override(model=model))

agent = create_agent(
    model=basic_model,  # Default model
    tools=[],
    middleware=[dynamic_model_selection]
)
```

Pre-bound models (models with [`bind_tools`](https://reference.langchain.com/python/langchain-core/language_models/chat_models/BaseChatModel/bind_tools) already called) are not supported when using structured output. If you need dynamic model selection with structured output, ensure the models passed to the middleware are not pre-bound.