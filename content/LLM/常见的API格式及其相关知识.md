+++
title = "三种常见 LLM API 兼容格式"
slug = "llm-api-compat-formats"
weight = 40
draft = false
categories = ["LLM"]
tags = ["API", "OpenAI", "Chat Completions", "Responses", "Anthropic"]
description = "OpenAI Chat Completions、OpenAI Responses API、Anthropic Messages 三种兼容格式的端点、认证、请求响应、流式、工具调用、状态与生态。"
+++

# 三种常见 LLM API 兼容格式

客户端、SDK、网关对「兼容」的约定，当前收敛成三条线协议：

1. **OpenAI Chat Completions** — `POST /v1/chat/completions`
2. **OpenAI Responses API** — `POST /v1/responses`
3. **Anthropic Messages API** — `POST /v1/messages`

Chat Completions 是跨厂商事实标准。Responses 是 OpenAI 2025-03 起的新主 API，agent / 内置工具 / 推理连续性落在这里。Messages 是 Claude 原生协议，因 Claude Code 成为第二标准。

OpenAI 官方：Chat Completions **继续支持、不会sunset**；新项目推荐 Responses。被 sunset 的是 Assistants API（2026-08-26），迁到 Responses + Conversations，不是迁回 Chat Completions。

## 一句话对照

| 项 | Chat Completions | Responses API | Anthropic Messages |
|---|---|---|---|
| 主端点 | `POST /v1/chat/completions` | `POST /v1/responses` | `POST /v1/messages` |
| 认证 | `Authorization: Bearer` | 同左 | `x-api-key` + `anthropic-version` |
| 对话容器 | `messages[]` | `input`（字符串或 item 数组） | `messages[]` + 顶层 `system` |
| 系统提示 | `messages` 里 `role: system` / `developer` | 顶层 `instructions` | 顶层 `system` |
| 取出文本 | `choices[0].message.content` | `output_text` 或 `output[]` 里 `output_text` | `content[0].text` |
| 返回单元 | `choices[].message`（多关切粘在一条 message） | 类型化 `output[]` item：`message` / `reasoning` / `function_call` | 类型化 `content[]` block：`text` / `thinking` / `tool_use` |
| 流式 | 同端点 `stream: true`，chunk + `delta` | 同端点 `stream: true`，语义事件 `response.*.delta` | 同端点 `stream: true`，命名事件 `content_block_delta` |
| 输出上限 | `max_completion_tokens`（`max_tokens` 弃用） | `max_output_tokens` | `max_tokens`（**必填**） |
| 多轮状态 | 客户端重发全部 history | 可选 `previous_response_id` / Conversations；也可手传 item | 客户端重发全部 history |
| 内置工具 | 无（只有你自己的 function） | web_search / file_search / code_interpreter / computer_use / MCP / image_generation | 服务端工具：web_search / web_fetch / code_execution / computer use 等 |
| 生态 | 最广：国内云、vLLM、Ollama、Cursor | OpenAI 自家 + 少数网关；兼容层常残缺 | Claude Code / Anthropic SDK；DeepSeek、MiniMax、Kimi 已跟 |

识别规则：看路径和请求体，不看模型名。

- 有 `messages` + 响应有 `choices` → Chat Completions
- 有 `input`（或顶层 `instructions`）+ 响应有 `output` / `output_text` → Responses
- 有必填 `max_tokens` + 顶层 `system` + 响应 `content` 块数组 → Messages

## 1. OpenAI Chat Completions

2023-03 起的对话 API。换 `base_url` 就能打 DeepSeek、Qwen compatible-mode、Moonshot、GLM、xAI、vLLM、Ollama、大多数网关。跨厂商移植仍写这套。

### 端点与认证

```
POST:{base}/v1/chat/completions
Authorization: Bearer $API_KEY
Content-Type: application/json
```

SDK 的 `base_url` 通常**带** `/v1`。官方：`https://api.openai.com/v1`。

常见附属：`GET /v1/models`、`POST /v1/embeddings`。`POST /v1/completions` 是更旧的 prompt 补全，已 legacy。

### 请求

```json
{
  "model": "gpt-4.1",
  "messages": [
    {"role": "system", "content": "你是助手。"},
    {"role": "user", "content": "用一句话解释 token。"}
  ],
  "temperature": 0.7,
  "max_completion_tokens": 512,
  "stream": false
}
```

| 字段 | 说明 |
|---|---|
| `model` | 必填 |
| `messages` | 必填。角色：`system` / `developer`（o1 及更新推理模型用 `developer` 替代 `system`）/ `user` / `assistant` / `tool` |
| `content` | 字符串，或多模态数组 `[{type:"text",text}, {type:"image_url",image_url:{url}}]` |
| `temperature` | 0–2，默认 1 |
| `top_p` | 0–1。与 temperature 二选一调 |
| `max_completion_tokens` | 输出上限；`max_tokens` 已弃用。推理模型把隐藏 thinking 也算进这个上限 |
| `stop` | 字符串或最多 4 个序列 |
| `n` | 候选条数，1–128。Responses **没有** 对应项 |
| `presence_penalty` / `frequency_penalty` | -2–2 |
| `response_format` | `{type:"json_object"}` 或 `{type:"json_schema", json_schema:{...}}` |
| `tools` | `[{type:"function", function:{name, description, parameters}}]` |
| `tool_choice` | `"none"` / `"auto"` / `"required"` / 指定函数 |
| `parallel_tool_calls` | 默认 true |
| `reasoning_effort` | 推理深度。GPT-5.4 起，Chat Completions 在非 `none` 的 effort 上**不支持** tool calling，要走 Responses |
| `stream` | true 时 SSE |
| `stream_options` | `{include_usage: true}` 在末包带回 usage |
| `store` | 新账号默认存储；关存储设 `false` |

### 响应

```json
{
  "id": "chatcmpl-...",
  "object": "chat.completion",
  "created": 1714000000,
  "model": "gpt-4.1",
  "choices": [
    {
      "index": 0,
      "message": {"role": "assistant", "content": "..."},
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 25,
    "completion_tokens": 9,
    "total_tokens": 34
  }
}
```

`finish_reason`：`stop` / `length` / `tool_calls` / `content_filter` / `function_call`（弃用）。

工具调用时 `message.content` 常为 `null`，调用在 `message.tool_calls[]`：

```json
{
  "role": "assistant",
  "content": null,
  "tool_calls": [
    {
      "id": "call_abc",
      "type": "function",
      "function": {
        "name": "get_weather",
        "arguments": "{\"location\":\"Boston, MA\"}"
      }
    }
  ]
}
```

回灌：同一 `messages` 里追加 `role: "tool"`，带 `tool_call_id`。必须客户端自己把 assistant 的 tool_calls 和 tool 结果都塞回下一轮。

### 流式

同端点，`stream: true`。每行 `data: {json}`，结束 `data: [DONE]`。对象类型 `chat.completion.chunk`，增量在 `choices[0].delta.content`。

```json
{"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
{"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
{"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
```

工具流式：`delta.tool_calls[].function.arguments` 是 JSON 字符串碎片，按 `index` 拼接。

### 最小调用

```python
from openai import OpenAI
client = OpenAI(api_key="sk-...", base_url="https://api.openai.com/v1")
r = client.chat.completions.create(
    model="gpt-4.1",
    messages=[{"role": "user", "content": "ping"}],
)
print(r.choices[0].message.content)
```

## 2. OpenAI Responses API

OpenAI 现推的主 primitive。设计目标：把「一次模型动作」从一条粘在一起的 message，拆成类型化 item（message / reasoning / function_call / 内置工具调用）。同一请求内可跑完多步工具循环（agentic loop）。

Chat Completions 能做的文本 / vision / 自定义 function / structured output，Responses 都能做，并且是超集。新能力只上 Responses：web_search、file_search、code_interpreter、computer use、远程 MCP、image_generation 当工具、reasoning summary、background mode。

内部评测（官方）：同样 prompt，推理模型走 Responses 比 Chat Completions 在 SWE-bench 高约 3%；prompt cache 利用率高 40%–80%。

### 端点与认证

```
POST https://api.openai.com/v1/responses
Authorization: Bearer $OPENAI_API_KEY
Content-Type: application/json
```

认证与 Chat Completions 相同。附属：`GET /v1/responses/{id}`、`POST /v1/responses/{id}/cancel`、Conversations API、`POST /v1/responses/compact`。

### 请求

最简：`input` 可以是纯字符串。

```json
{
  "model": "gpt-5.5",
  "instructions": "你是助手。",
  "input": "用一句话解释 token。"
}
```

多轮 / 多模态时 `input` 是 item 数组。简单 `{role, content}` 消息数组也能塞进 `input`（迁移期兼容）：

```json
{
  "model": "gpt-5.5",
  "instructions": "你是助手。",
  "input": [
    {
      "role": "user",
      "content": [
        {"type": "input_text", "text": "这张图里有什么？"},
        {"type": "input_image", "image_url": "https://..."}
      ]
    }
  ],
  "max_output_tokens": 512
}
```

| 字段 | 说明 |
|---|---|
| `model` | 必填 |
| `input` | 必填。字符串，或 item 数组（message / function_call_output / 内置工具结果 / item_reference） |
| `instructions` | 顶层系统提示，不进 `input`。利于 prompt cache |
| `max_output_tokens` | 输出上限，对应 CC 的 `max_completion_tokens` |
| `temperature` / `top_p` | 与 CC 同量纲 0–2 / 0–1 |
| `text.format` | 结构化输出。对应 CC 的 `response_format` |
| `tools` | 扁平：`{type:"function", name, description, parameters}`，**不再**套一层 `function`。也可放内置工具 `{type:"web_search"}` 等 |
| `tool_choice` | `"none"` / `"auto"` / `"required"` / 具名 |
| `reasoning` | `{effort:"low"|"medium"|"high"|...}`；可要 `summary` |
| `previous_response_id` | 把上一轮 `resp_...` 链上来，服务端持有历史 |
| `store` | 默认 **true**。ZDR / 不要落盘设 `false`，推理连续性改走加密 reasoning item |
| `background` | 长任务异步；可配合 `stream` 断线后续传 |
| `stream` | true 时语义 SSE 事件 |
| `conversation` | 接到 Conversations API 的会话 id |

没有 `n`（只生成一条）。没有 `presence_penalty` / `frequency_penalty` 这一套 CC-only 采样项（以当前 schema 为准）。

### 响应

```json
{
  "id": "resp_68af4030...",
  "object": "response",
  "created_at": 1756315696,
  "status": "completed",
  "model": "gpt-5.5",
  "output": [
    {
      "id": "rs_...",
      "type": "reasoning",
      "content": [],
      "summary": []
    },
    {
      "id": "msg_...",
      "type": "message",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "annotations": [],
          "text": "..."
        }
      ]
    }
  ],
  "usage": {
    "input_tokens": 25,
    "output_tokens": 40,
    "total_tokens": 65
  }
}
```

SDK 提供 `response.output_text`，把所有 `output_text` 拼起来。手写解析不要假定 `output[0]` 是 message——前面经常先有 `reasoning`。

`status`：`in_progress` / `completed` / `failed` / `cancelled` / `queued`。

### 工具调用形状（与 CC 不同）

定义（扁平，无 `function` 包一层）：

```json
{
  "type": "function",
  "name": "get_weather",
  "description": "Get weather",
  "parameters": {
    "type": "object",
    "properties": {"location": {"type": "string"}},
    "required": ["location"]
  }
}
```

模型吐出的是独立 item，不嵌在 message 里：

```json
{
  "type": "function_call",
  "id": "fc_...",
  "call_id": "call_abc",
  "name": "get_weather",
  "arguments": "{\"location\":\"Boston, MA\"}"
}
```

回灌用另一个 item，`call_id` 必须对齐：

```json
{
  "type": "function_call_output",
  "call_id": "call_abc",
  "output": "72°F, sunny"
}
```

两种多轮方式：

1. **服务端状态**：下一请求只带 `previous_response_id` + 新 `input`（用户话或 `function_call_output`）。
2. **无状态**：把上一轮 `output` 里的 reasoning / function_call 原样放进下一轮 `input`，再追加 `function_call_output`。丢掉 reasoning item 会打断推理连续性。`store: false` 时用加密 reasoning 字段回放。

`previous_response_id` **不免除** 对先前上下文的计费：链上的历史仍按 input tokens 计。

内置工具同一 `tools` 数组：

```json
{"tools": [{"type": "web_search"}, {"type": "function", "name": "get_weather", "parameters": {...}}]}
```

模型可在**一次** `responses.create` 里连打多个内置工具，再给你最终文本。自定义 function 仍要你本地执行后回灌。

### 结构化输出

CC 的 `response_format` 迁到 `text.format`：

```json
{
  "model": "gpt-5.5",
  "input": "抽出发票字段。",
  "text": {
    "format": {
      "type": "json_schema",
      "name": "invoice",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {"total": {"type": "number"}},
        "required": ["total"]
      }
    }
  }
}
```

schema 本身不变，只是位置变了。JSON mode 对应 `text.format.type = "json_object"`。

### 流式

同端点 `stream: true`。**不要**用 Chat Completions 的 `choices[0].delta` 解析器。事件带 `type`：

| 事件 | 含义 |
|---|---|
| `response.created` | 对象已建，`status: in_progress` |
| `response.output_item.added` | 新 item（message / reasoning / function_call） |
| `response.content_part.added` | 新 content part |
| `response.output_text.delta` | 文本增量，读 `delta` |
| `response.function_call_arguments.delta` | 函数参数碎片 |
| `response.output_item.done` | 该 item 完成；reasoning 以这条的完整 item 为准再回放 |
| `response.completed` | 整次完成 |
| `error` | 失败 |

```python
stream = client.responses.create(model="gpt-5.5", input="ping", stream=True)
for event in stream:
    if event.type == "response.output_text.delta":
        print(event.delta, end="", flush=True)
```

### 最小调用

```python
from openai import OpenAI
client = OpenAI()
r = client.responses.create(
    model="gpt-5.5",
    instructions="你是助手。",
    input="ping",
)
print(r.output_text)
```

链式多轮：

```python
r2 = client.responses.create(
    model="gpt-5.5",
    previous_response_id=r.id,
    input="把上一句翻译成英文。",
)
```

### 从 Chat Completions 迁过来的三件事

1. 路径 `/v1/chat/completions` → `/v1/responses`。
2. 读 `choices[0].message.content` → 读 `output_text` / 遍历 `output`（不要把每个 item 都当 message）。
3. 选状态策略：继续手传 history（`input` 里重放 item），或 `previous_response_id` / Conversations。

常见迁移错误：仍发 `response_format`；把 CC 的 `tools[].function` 套层原样丢给 Responses；回灌 function 结果不带 `call_id`；流式还在找 `choices`；丢掉 reasoning item。

GPT-6 Astra 的 tool calling **要求** Responses。Chat Completions 示例要用更早的模型。

## 3. Anthropic Messages API

Claude 原生协议。Claude Code、Anthropic SDK 只认这套。2025–2026 起 DeepSeek（`https://api.deepseek.com/anthropic`）、MiniMax（推荐走 Messages 拿满 thinking/tool）、Kimi、部分 Qwen 网关都加了 `/v1/messages`。

旧 Text Completions（`\n\nHuman:` / `\n\nAssistant:`）已弃用。

### 端点与认证

```
POST https://api.anthropic.com/v1/messages
x-api-key: $ANTHROPIC_API_KEY
anthropic-version: 2023-06-01
Content-Type: application/json
```

兼容层常见两种：只认 `x-api-key`，或同时接受 `Authorization: Bearer`。`anthropic-version` 多数网关忽略，SDK 会带。

附属：`POST /v1/messages/count_tokens`、`POST /v1/messages/batches`。

### 请求

```json
{
  "model": "claude-sonnet-4-6",
  "max_tokens": 1024,
  "system": "你是助手。",
  "messages": [
    {"role": "user", "content": "用一句话解释 token。"}
  ],
  "temperature": 0.7
}
```

| 字段 | 说明 |
|---|---|
| `model` | 必填 |
| `max_tokens` | **必填**，> 1。thinking 也计入 |
| `messages` | 必填。角色只有 `user` / `assistant`，**没有** `system` / `tool` |
| `system` | 顶层，字符串或 content block 数组 |
| `temperature` | 0–1，默认 1。Opus 4.7+ / Sonnet 5 / Fable 5 上非默认采样参数会 400，应省略 |
| `top_p` / `top_k` | 同上，新模型上移除 |
| `stop_sequences` | 数组 |
| `tools` | `[{name, description, input_schema}]`，schema 在顶层，不套 `function` |
| `tool_choice` | `{type:"auto"|"any"|"tool"|"none"}`。Fable 5.1 / Mythos 5.1 拒绝 `any` / `tool` |
| `thinking` | `{type:"adaptive"}` 或旧式 `{type:"enabled", budget_tokens:N}` |
| `output_config.format` | 结构化输出（`output_format` 已替换） |
| `cache_control` | 顶层自动缓存，或打在单个 content block 上 |
| `stream` | true 时 SSE |

`content` 可以是字符串，等价于 `[{type:"text", text:"..."}]`。正式形态是块数组。常见块：`text` / `image` / `tool_use` / `tool_result` / `thinking`。

图片：

```json
{
  "type": "image",
  "source": {"type": "base64", "media_type": "image/jpeg", "data": "<base64>"}
}
```

### 响应

```json
{
  "id": "msg_...",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-4-6",
  "content": [{"type": "text", "text": "..."}],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 25,
    "output_tokens": 200,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0
  }
}
```

`stop_reason`：`end_turn` / `max_tokens` / `stop_sequence` / `tool_use` / `pause_turn` / `refusal` / `model_context_window_exceeded`。

工具调用是 content 里的块，`input` 是**对象**不是字符串：

```json
{
  "type": "tool_use",
  "id": "toolu_01",
  "name": "get_weather",
  "input": {"location": "Boston, MA"}
}
```

回灌：下一条 `user` 消息的 content 里放 `tool_result`，`tool_use_id` 对齐。下一轮要把上一轮完整 `content`（含 thinking / tool_use）原样追加进 `assistant` 消息。丢掉 thinking 块会校验失败。

### 流式

同端点。事件名与 `data.type` 一致。

顺序：

1. `message_start` — 空 `content` 的 Message，含 input usage
2. 每个块：`content_block_start` → 若干 `content_block_delta` → `content_block_stop`
3. `message_delta` — `stop_reason` + 最终 output usage
4. `message_stop`

文本增量：`delta.type == "text_delta"`。工具参数增量：`input_json_delta`（`partial_json`）。中间可能夹 `ping`。不要把所有 `content_block_delta` 都当文本。

### Prompt cache

两种开法：

- 自动：请求顶层 `"cache_control": {"type": "ephemeral"}`，断点落在最后一个可缓存块，多轮会前移。
- 显式：在 tools / system / 某个 content block 上挂 `cache_control`。

默认 TTL 5 分钟，刷新命中免费；另有 1 小时档（写入更贵）。缓存前缀顺序固定：tools → system → messages。usage 里看 `cache_creation_input_tokens` / `cache_read_input_tokens`。

Responses 的 cache 主要靠稳定的 `instructions` + 服务端状态；Messages 是显式断点。两套机制不能对着抄字段名。

### 最小调用

```python
import anthropic
client = anthropic.Anthropic()
r = client.messages.create(
    model="claude-sonnet-4-6",
    max_tokens=1024,
    system="你是助手。",
    messages=[{"role": "user", "content": "ping"}],
)
print(r.content[0].text)
```

## 横切对照

### 认证与路径

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| Header | `Authorization: Bearer` | 同左 | `x-api-key` |
| 额外 | 无 | 无 | `anthropic-version: 2023-06-01` |
| SDK base | 带 `/v1` | 带 `/v1` | **不**带 `/v1`（路径自含 `/v1/messages`） |
| 同一把 OpenAI key | 是 | 是 | 否（Anthropic key；网关可统一成 `sk-` 再改 header） |

OpenAI 两条协议可以共用 SDK 对象：`client.chat.completions.create` vs `client.responses.create`。Messages 必须换 Anthropic SDK 或改 header。

### 系统提示、角色、内容模型

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| 系统提示 | message role `system` / `developer` | 顶层 `instructions` | 顶层 `system` |
| 用户 | `user` | `input` 里 user message | `user` |
| 助手 | `assistant` | `output` 里 `type: message` | `assistant` |
| 工具结果角色 | `role: tool` + `tool_call_id` | item `type: function_call_output` + `call_id` | 仍是 `user`，块类型 `tool_result` |
| 内容单元 | string 或 `{type, ...}` part | 类型化 item；文本 part 叫 `input_text` / `output_text` | 类型化 block：`text` / `tool_use` / `thinking` |

Responses 的 item 模型和 Messages 的 content block 更像：都把 reasoning / tool call 从「一条 assistant message」里拆出来。Chat Completions 把这些粘在 `message` + `tool_calls` 上。

### 采样与长度

| 参数 | Chat Completions | Responses | Messages |
|---|---|---|---|
| temperature | 0–2 | 0–2 | **0–1** |
| 1.5 是否合法 | 是 | 是 | 否，400 |
| 输出上限 | `max_completion_tokens` | `max_output_tokens` | `max_tokens`（必填） |
| 是否计入 thinking | 是 | 是 | 是 |
| 多候选 `n` | 有 | 无 | 无 |
| 惩罚项 | presence / frequency | 无（当前 schema） | 无 |
| stop | `stop`，最多 4 | 以当前文档为准 | `stop_sequences` |

移植最容易炸的两件事：Messages 漏 `max_tokens`；把 OpenAI 的 `temperature: 1.5` 打到 Claude。

### 结构化输出

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| 仅合法 JSON | `response_format: {type:"json_object"}` | `text.format: {type:"json_object"}` | 走 schema 形式 |
| 带 schema | `response_format.json_schema` | `text.format` + `json_schema` | `output_config.format: {type:"json_schema", schema:...}` |
| 严格模式 | `strict: true`（默认 false） | 同左，放在 `text.format` 里 | tool `strict: true` / output_config |

CC → Responses 只改字段位置，schema 不用重写。

### 工具调用词汇

循环相同：声明 → 模型吐调用 → 本地执行 → 结果作为下一轮输入。字段和落点不同。

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| 定义 | `tools[].function.{name,parameters}` | `tools[].{type:"function", name, parameters}`（扁平） | `tools[].{name,input_schema}` |
| 让模型决定 | `"auto"` | `"auto"` | `{type:"auto"}` |
| 强制用工具 | `"required"` | `"required"` | `{type:"any"}` |
| 禁止 | `"none"` | `"none"` | `{type:"none"}` |
| 调用落点 | `message.tool_calls[]` | `output[]` 里 `type: function_call` | `content[]` 里 `tool_use` |
| 参数类型 | `arguments` **字符串** | `arguments` **字符串** | `input` **对象** |
| 结果落点 | `role: tool` | `function_call_output` item | `user` + `tool_result` |
| 关联 id | `tool_call_id` | `call_id` | `tool_use_id` |
| 内置工具 | 无 | web_search 等，一次请求内可连跑 | web_search / web_fetch 等（Anthropic 服务端工具） |
| 同请求内多步 | 否，每步一次 HTTP | **是**（内置工具）；自定义 function 仍要回灌 | 否，每步一次 HTTP |

`any` ≈ `required`（必须调工具）。OpenAI 两套的 `arguments` 都是序列化 JSON 字符串；Anthropic 是已解析对象。网关漏转这个类型会让客户端二次 `JSON.parse` 或 TypeError。

### 推理

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| 开关 | `reasoning_effort` | `reasoning.effort` | `thinking` |
| 露出思路 | 弱 | `reasoning.summary`；output 里独立 `reasoning` item | `thinking` block + `display` |
| 多轮连续性 | 你自己重发；GPT-5.4+ 带 tool 时 CC 受限 | `previous_response_id` 或回放 reasoning item | 必须把 thinking 块原样带回 |
| 与 tool 同用 | GPT-5.4+ 仅 `effort=none` | 一等公民 | 一等公民 |

上限字段把 thinking + 可见文本算在一起。上限过小会只产出 thinking、正文为空。

### 流式事件不能混解析

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| 怎么开 | `stream: true` | `stream: true` | `stream: true` |
| 形态 | `data: {chunk}` + `[DONE]` | 带 `type` 的语义事件 | `event:` + `data:` 成对 |
| 取文本 | `choices[0].delta.content` | `event.type == "response.output_text.delta"` 的 `delta` | `delta.text` 且 `type==text_delta` |
| usage | 默认不在中间包；`stream_options.include_usage` | `response.completed` 上的完整对象 | `message_start` 有 input，`message_delta` 有 output |

三套解码器不能共用。用 CC 解析器读 Responses 流会找不到 `choices`。

### 状态

| | Chat Completions | Responses | Messages |
|---|---|---|---|
| 默认 | 无状态，重发 `messages` | `store: true`，可链 `previous_response_id` | 无状态，重发 `messages` |
| 服务端会话 | 无（除非自己存 completion id，能力弱） | Conversations API + `previous_response_id` | 无 |
| 关掉存储 | `store: false` | `store: false` + 加密 reasoning 回放 | 本来就不存 |

`previous_response_id` 省的是**重传字节和 cache 友好性**，不是免掉历史 token 账单。

## 生态：谁说哪种话

| 提供方 / 客户端 | Chat Completions | Responses | Messages |
|---|---|---|---|
| OpenAI 官方 | 支持，兼容标准 | **新功能主路径** | 无 |
| Azure OpenAI | 有 | 有 | 无 |
| Anthropic 官方 | 无 | 无 | 原生 |
| DeepSeek | 主路径 | 少 | `.../anthropic` |
| Qwen DashScope | `compatible-mode/v1` | 少 | 部分网关转 |
| Moonshot / Kimi | 有 | 少 | 有 |
| MiniMax | 有 | 少 | **推荐** |
| GLM / 豆包 / ERNIE | 有 CC 兼容入口 | 少 | 少 |
| vLLM / SGLang / Ollama / LM Studio | 是 | 部分开始加，覆盖面远小于 CC | Ollama 等开始加 |
| Cursor / Cline / 多数 Chat UI | 是 | 少 | 否 |
| Codex CLI | 走 OpenAI 协议（新栈偏 Responses） | 视版本 | 否 |
| Claude Code / Claude Desktop | 否 | 否 | **是** |
| LiteLLM 等网关 | `/v1/chat/completions` | `/v1/responses` | `/v1/messages` |

「OpenAI 兼容」在市面上几乎总是 Chat Completions，**不等于**实现了 Responses。内置工具、`previous_response_id`、语义流式事件、扁平 tools 定义，要逐项对文档。

LiteLLM 可以把 Messages 映射到 Responses：`messages` → `input`，`system` → `instructions`，`max_tokens` → `max_output_tokens`，`thinking` → `reasoning`。反向同样要处理 item ↔ block。

## 转换陷阱

1. **系统提示位置**。CC 的 `role: system` → Responses 的 `instructions` 或 Messages 的 `system`。反向要塞回 `messages[0]`。
2. **读输出**。`choices[0].message.content` / `output_text` / `content[0].text` 三套。Responses 的 `output[0]` 经常是 reasoning，不是文本。
3. **tools 套层**。CC 有 `function` 包一层；Responses 和 Messages 都扁平。
4. **工具参数类型**。两个 OpenAI 协议 `arguments` 是字符串；Anthropic `input` 是对象。
5. **工具结果角色**。CC 用 `tool`；Responses 用 `function_call_output` item；Messages 仍是 `user` + `tool_result`。
6. **id 字段名**。`tool_call_id` / `call_id` / `tool_use_id`。对不上就 400。
7. **max_tokens 必填**。只有 Messages 强制。CC/Responses 可选，但字段名还不一样。
8. **temperature 量纲**。1.5 在两条 OpenAI 协议合法，在 Anthropic 非法。
9. **流式解析器**。三套事件完全不同。
10. **思考块必须回放**。Messages 的 `thinking`、Responses 的 `reasoning` item，丢掉会拒或变笨。CC 没有对等的一等 item。
11. **`response_format` vs `text.format` vs `output_config`**。结构化输出三个家。
12. **把 Responses 当「改个 URL 的 CC」**。简单字符串 `input` 能跑；tools / 多轮 / 流式会在形状上炸掉。
13. **`previous_response_id` 与兼容层**。多数国内 CC 兼容层没有这个语义；链式状态一接就 404/忽略。
14. **header 与 base 后缀**。OpenAI SDK base 带 `/v1`；Anthropic SDK base **不要**再拼 `/v1`。

## 相邻格式（不计入三种）

| 格式 | 端点 | 用途 |
|---|---|---|
| OpenAI Completions | `POST /v1/completions` | 旧 prompt 补全，已 legacy |
| Assistants API | `/v1/threads` 等 | **2026-08-26 sunset**，迁 Responses + Conversations |
| Gemini generateContent | `:generateContent` | Google 原生；另有官方 OpenAI 兼容层 `/v1beta/openai/`（走的是 CC 形状） |
| Amazon Bedrock Converse | `Converse` | AWS 统一壳 |
| Ollama 原生 | `/api/chat` | 本地；同时提供 CC 兼容 |

## 怎么选

| 场景 | 选 |
|---|---|
| 跨厂商、国内 API、vLLM、现有 OpenAI SDK 聊天 | Chat Completions |
| 新做 OpenAI 自家 agent、内置工具、MCP、推理连续性、GPT-6 tool calling | Responses |
| Claude Code / Anthropic SDK / MiniMax 完整 agent | Messages |
| 已有稳定 CC 代码、无新需求 | 继续 CC，不必迁 |
| 还在 Assistants API | 必须在 2026-08-26 前迁 Responses，不是迁 CC |
| 要同时接三种客户端 | 网关三端点并行：`/v1/chat/completions`、`/v1/responses`、`/v1/messages` |

自建中枢时：用 **类型化 item/block**（Responses item 或 Messages content block）做内部表示。用 CC 的 `messages` 当中枢会丢掉 reasoning / thinking / 内置工具调用。

## 三格式最小请求并排

Chat Completions：

```bash
curl https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4.1",
    "messages": [
      {"role": "system", "content": "你是助手。"},
      {"role": "user", "content": "ping"}
    ]
  }'
```

Responses：

```bash
curl https://api.openai.com/v1/responses \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5.5",
    "instructions": "你是助手。",
    "input": "ping"
  }'
```

Messages：

```bash
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-6",
    "max_tokens": 1024,
    "system": "你是助手。",
    "messages": [{"role": "user", "content": "ping"}]
  }'
```

## 官方文档

- Chat Completions：<https://developers.openai.com/api/reference/resources/chat>
- Responses：<https://developers.openai.com/api/reference/resources/responses>
- 从 CC 迁 Responses：<https://platform.openai.com/docs/guides/migrate-to-responses>
- Responses 流式事件：<https://developers.openai.com/api/reference/resources/responses/streaming-events>
- Function calling（两套 OpenAI 形状）：<https://developers.openai.com/api/docs/guides/function-calling>
- Anthropic Messages：<https://platform.claude.com/docs/en/api/http/messages/create>
- Anthropic 流式：<https://docs.claude.com/en/docs/build-with-claude/streaming>
- Anthropic Prompt cache：<https://docs.claude.com/en/docs/build-with-claude/prompt-caching>
- 参数对照（含 CC / Responses / Messages）：<https://hidekazu-konishi.com/entry/llm_api_parameter_compatibility_reference.html>

字段名、temperature 是否还接受、thinking 档位、哪代模型强制走 Responses 做 tool calling，随模型代际会变。对接前以各家当前 API reference 为准。
