+++
title = "Message"
slug = "message"
weight = 50
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Message相关学习笔记与实践要点。"
+++
# Message

Carrying both the content and metadata which represent the state

Messages contain:

- Role: identifies the message type(system,user)
- Content: the actual content
- Metadata: optional fields: such as information,message IDs,and token usage

This is the standard message type

## Basic usage

The easiest way to use message is to **create message objects** and pass them to a model when invoking

## Text prompts

String
Ideal for generation tasks where you don't need to retain.

```
response = model.invoke("Write a haiku about spring")
```

When to use:

- a single ,standalone request
- no need for conversation history
- minimal code complexity

## Message prompts

Providing  a list of messages

```
from langchain.messages import SystemMessage, HumanMessage, AIMessage

messages = [
    SystemMessage("You are a poetry expert"),
    HumanMessage("Write a haiku about spring"),
    AIMessage("Cherry blossoms bloom...")
]
response = model.invoke(messages)
```

When:

- Managing multi-turn conversations
- Working with multimodal content (images, audio, files)
- Including system instructions

## Dictionary format

Specify message in OpenAI chat completions format:

```
messages = [
    {"role": "system", "content": "You are a poetry expert"},
    {"role": "user", "content": "Write a haiku about spring"},
    {"role": "assistant", "content": "Cherry blossoms bloom..."}
]
response = model.invoke(messages)
```

## Message types

- System messages
- Human messages
- Al messages: 
- Tool messages: 

### System message

An initial set of instructions that primes the model's behavior

### Human message

user input and interactions

### AI message

The LLM sometimes treat the message differently, so sometimes we can make up a AI message manually.

#### Tool calls

 are included in AI messages

#### Token usage

in AI message in usage_metadata field

#### Streaming and chunks

When streaming, u can receive `AIMessageChunk` objects and it can be combined into a full message by summing

### Tool message

tool result in `ToolMessage` object

## Message content

An loosely-typed attribute,supporting strings and lists if untyped objects

Beside, LangChain provides dedicated content types for text, reasoning, citations, multi-modal data, server-side tool calls, and other message content

This may contain either:

1. A string
2. A list of content blocks in a provider-native format
3. A list of [LangChain’s standard content blocks](https://docs.langchain.com/oss/python/langchain/messages#standard-content-blocks)

```
from langchain.messages import HumanMessage

# String content
human_message = HumanMessage("Hello, how are you?")

# Provider-native format (e.g., OpenAI)
human_message = HumanMessage(content=[
    {"type": "text", 
    "text": "Hello, how are you?"},
    {"type": "image_url", 
    "image_url": {"url": "https://example.com/image.jpg"}}
])

# List of standard content blocks
human_message = HumanMessage(content_blocks=[
    {"type": "text", "text": "Hello, how are you?"},
    {"type": "image", "url": "https://example.com/image.jpg"},
])
```

## Standard content blocks

LangChain provides a standard representation for message content that works across providers.

消息对象实现了一个 `content_blocks` 属性，该属性会延迟将 `content` 属性解析为标准的、类型安全的表示形式。例如，从 [`ChatAnthropic`](https://docs.langchain.org.cn/oss/python/integrations/chat/anthropic) 或 [`ChatOpenAI`](https://docs.langchain.org.cn/oss/python/integrations/chat/openai) 生成的消息将包含各自提供商格式的 `thinking` 或 `reasoning` 块，但可以延迟解析为一致的 [`ReasoningContentBlock`](https://docs.langchain.org.cn/oss/python/langchain/messages#content-block-reference) 表示形式

```
from langchain.messages import AIMessage

message = AIMessage(
    content=[
        {
            "type": "reasoning",
            "id": "rs_abc123",
            "summary": [
                {"type": "summary_text", "text": "summary 1"},
                {"type": "summary_text", "text": "summary 2"},
            ],
        },
        {"type": "text", "text": "...", "id": "msg_abc123"},
    ],
    response_metadata={"model_provider": "openai"}
)
message.content_blocks
```

```
[{'type': 'reasoning', 'id': 'rs_abc123', 'reasoning': 'summary 1'},
 {'type': 'reasoning', 'id': 'rs_abc123', 'reasoning': 'summary 2'},
 {'type': 'text', 'text': '...', 'id': 'msg_abc123'}]
```

将不同的provider的统一接口,是通过content_blocks属性来实现的

## Multimodal

**Multimodality** refers to the ability to work with data that comes in different forms, such as text, audio, images, and video

[Chat models](https://docs.langchain.com/oss/python/langchain/models) can accept multimodal data as input and generate it as output. Below we show short examples of input messages featuring multimodal data.

```
# From URL
message = {
    "role": "user",
    "content": [
        {"type": "text", "text": "Describe the content of this image."},
        {"type": "image", "url": "https://example.com/path/to/image.jpg"},
    ]
}

# From base64 data
message = {
    "role": "user",
    "content": [
        {"type": "text", "text": "Describe the content of this image."},
        {
            "type": "image",
            "base64": "AAAAIGZ0eXBtcDQyAAAAAGlzb21tcDQyAAACAGlzb2...",
            "mime_type": "image/jpeg",
        },
    ]
}

# From provider-managed File ID
message = {
    "role": "user",
    "content": [
        {"type": "text", "text": "Describe the content of this image."},
        {"type": "image", "file_id": "file-abc123"},
    ]
}
```

Content blocks are represented (either when creating a message or accessing the `content_blocks` property) as **a list of typed dictionaries**

##  Serialization

You can serialize messages to plain objects for storage and deserialize back to message instances. This is useful for persisting conversation history and resuming sessions.

```
from langchain.messages import HumanMessage
from langchain_core.load import dumpd, load

message = HumanMessage("What is the capital of France?")

# Serialize to a plain dict
serialized = dumpd(message)

# Deserialize back to a message object
restored = load(serialized)
```

