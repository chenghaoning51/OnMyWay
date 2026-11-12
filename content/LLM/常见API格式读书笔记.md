+++
title = "常见API格式读书笔记"
slug = "llm-api-formats-notes"
weight = 80
categories = ["LLM"]
tags = ["LLM", "API"]
description = "常见API格式读书笔记相关学习笔记与实践要点。"
+++
# 三种最常见的LLM API兼容格式

1. **OpenAI Chat Completions** — `POST /v1/chat/completions`
2. **OpenAI Responses API** — `POST /v1/responses`
3. **Anthropic Messages API** — `POST /v1/messages`

# OpenAI Chat Completions

2023-03启用的对话API,通过修改base_url就可以实现兼容

## 端点和认证:

```
POST {base}/v1/chat/completions
Authorization: Bearer $API_KEY
Content-Type: application/json
```

SDK的**base_url**一般带**/v1**
legacy指的是不建议使用但是任然可以使用的
比如:
POST /v1/completions

## 请求

```
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

## 相关的字段

| 字段                                     | 说明                                                         |
| ---------------------------------------- | ------------------------------------------------------------ |
| `model`                                  | 必填                                                         |
| `messages`                               | 必填。角色：`system` / `developer`（o1 及更新推理模型用 `developer` 替代 `system`）/ `user` / `assistant` / `tool` |
| `content`                                | 字符串，或多模态数组 `[{type:"text",text}, {type:"image_url",image_url:{url}}]` |
| `temperature`                            | 0–2，默认 1                                                  |
| `top_p`                                  | 0–1。与 temperature 二选一调                                 |
| `max_completion_tokens`                  | 输出上限；`max_tokens` 已弃用。推理模型把隐藏 thinking 也算进这个上限 |
| `stop`                                   | 字符串或最多 4 个序列                                        |
| `n`                                      | 候选条数，1–128。Responses **没有** 对应项                   |
| `presence_penalty` / `frequency_penalty` | -2–2                                                         |
| `response_format`                        | `{type:"json_object"}` 或 `{type:"json_schema", json_schema:{...}}` |
| `tools`                                  | `[{type:"function", function:{name, description, parameters}}]` |
| `tool_choice`                            | `"none"` / `"auto"` / `"required"` / 指定函数                |
| `parallel_tool_calls`                    | 默认 true                                                    |
| `reasoning_effort`                       | 推理深度。GPT-5.4 起，Chat Completions 在非 `none` 的 effort 上**不支持** tool calling，要走 Responses |
| `stream`                                 | true 时 SSE                                                  |
| `stream_options`                         | `{include_usage: true}` 在末包带回 usage                     |
| `store`                                  | 新账号默认存储；关存储设 `false`                             |

## 响应

```
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

```
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

## 流式

同端点，`stream: true`。每行 `data: {json}`，结束 `data: [DONE]`。对象类型 `chat.completion.chunk`，增量在 `choices[0].delta.content`。

```json
{"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
{"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}
{"id":"chatcmpl-123","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
```

工具流式：`delta.tool_calls[].function.arguments` 是 JSON 字符串碎片，按 `index` 拼接。

## 最小调用:

```
from openai import OpenAI
client = OpenAI(api_key="sk-...", base_url="https://api.openai.com/v1")
r = client.chat.completions.create(
    model="gpt-4.1",
    messages=[{"role": "user", "content": "ping"}],
)
print(r.choices[0].message.content)
```

# OpenAI Responses API

OpenAI先主推的primitive
设计目标:把[一次模型动作]从一条站在一起的message拆分成类型化的item(message/reasoning/function_call/内置工具调用),同一请求内跑完多步工具循环(agentic loop)

官方更推荐,原因:
SWE-bench得分更高,且prompt cache利用率也更高,相应的成本也就更低

## 端点和认证

```
POST https://api.openai.com/v1/responses
Authorization: Bearer $OPENAI_API_KEY
Content-Type: application/json
```

认证与chat/completions完全相同


## 请求

最简:input可以是字符串

```
{
"model" : "gpt-5.5",
"instructions":"你是助手.",
"input":"一句话解释token"
}
```

多轮或者多模态时input为item数组,而在迁移期兼容,简单的{role,content}消息也可以追加到input中
例如:

```
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

## 字段

| 字段                    | 说明                                                         |
| ----------------------- | ------------------------------------------------------------ |
| `model`                 | 必填                                                         |
| `input`                 | 必填。字符串，或 item 数组（message / function_call_output / 内置工具结果 / item_reference） |
| `instructions`          | 顶层系统提示，不进 `input`。利于 prompt cache                |
| `max_output_tokens`     | 输出上限，对应 CC 的 `max_completion_tokens`                 |
| `temperature` / `top_p` | 与 CC 同量纲 0–2 / 0–1                                       |
| `text.format`           | 结构化输出。对应 CC 的 `response_format`                     |
| `tools`                 | 扁平：`{type:"function", name, description, parameters}`，**不再**套一层 `function`。也可放内置工具 `{type:"web_search"}` 等 |
| `tool_choice`           | `"none"` / `"auto"` / `"required"` / 具名                    |
| `reasoning`             | `{effort:"low"|"medium"|"high"|...}`；可要 `summary`         |
| `previous_response_id`  | 把上一轮 `resp_...` 链上来，服务端持有历史                   |
| `store`                 | 默认 **true**。ZDR / 不要落盘设 `false`，推理连续性改走加密 reasoning item |
| `background`            | 长任务异步；可配合 `stream` 断线后续传                       |
| `stream`                | true 时语义 SSE 事件                                         |
| `conversation`          | 接到 Conversations API 的会话 id                             |

## 响应

```
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

`status`：`in_progress` / `completed` / `failed` / `cancelled` / `queued`

## 工具调用形状(与CC不同)

#### 定义(扁平,无function包一层)

```
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

模型吐出的是独立item,不嵌套在message中

```
{
  "type": "function_call",
  "id": "fc_...",
  "call_id": "call_abc",
  "name": "get_weather",
  "arguments": "{\"location\":\"Boston, MA\"}"
}
```

回灌用另一个item.call_id必须对齐

```
{
  "type": "function_call_output",
  "call_id": "call_abc",
  "output": "72°F, sunny"
}
```

两种多轮方式:

1. 服务端状态:下一请求只带 `previous_response_id` + 新 `input`（用户话或 `function_call_output`）:链式多轮
2. 无状态:把上一轮 `output` 里的 reasoning / function_call 原样放进下一轮 `input`，再追加 `function_call_output`。丢掉 reasoning item 会打断推理连续性。`store: false` 时用加密 reasoning 字段回放。

内置工具同意**tools**数组:

```
{"tools": [{"type": "web_search"}, {"type": "function", "name": "get_weather", "parameters": {...}}]}
```

## 结构化输出

CC 的 `response_format` 迁到 `text.format`：

## 流式

同端点 `stream: true`。**不要**用 Chat Completions 的 `choices[0].delta` 解析器。事件带 `type`：

| 事件                                     | 含义                                                 |
| ---------------------------------------- | ---------------------------------------------------- |
| `response.created`                       | 对象已建，`status: in_progress`                      |
| `response.output_item.added`             | 新 item（message / reasoning / function_call）       |
| `response.content_part.added`            | 新 content part                                      |
| `response.output_text.delta`             | 文本增量，读 `delta`                                 |
| `response.function_call_arguments.delta` | 函数参数碎片                                         |
| `response.output_item.done`              | 该 item 完成；reasoning 以这条的完整 item 为准再回放 |
| `response.completed`                     | 整次完成                                             |
| `error`                                  | 失败                                                 |

```
stream = client.responses.create(model="gpt-5.5", input="ping", stream=True)
for event in stream:
    if event.type == "response.output_text.delta":
        print(event.delta, end="", flush=True)
```

## 最小调用

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

# Anthropic Messages API

Claude 原生协议

## 端点与认证:

```
POST https://api.anthropic.com/v1/messages
x-api-key: $ANTHROPIC_API_KEY
anthropic-version: 2023-06-01
Content-Type: application/json
```

兼容层常见两种：只认 `x-api-key`，或同时接受 `Authorization: Bearer`。`anthropic-version` 多数网关忽略，SDK 会带。

## 请求

```
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

字段

| 字段                   | 说明                                                         |
| ---------------------- | ------------------------------------------------------------ |
| `model`                | 必填                                                         |
| `max_tokens`           | **必填**，> 1。thinking 也计入                               |
| `messages`             | 必填。角色只有 `user` / `assistant`，**没有** `system` / `tool` |
| `system`               | 顶层，字符串或 content block 数组                            |
| `temperature`          | 0–1，默认 1。Opus 4.7+ / Sonnet 5 / Fable 5 上非默认采样参数会 400，应省略 |
| `top_p` / `top_k`      | 同上，新模型上移除                                           |
| `stop_sequences`       | 数组                                                         |
| `tools`                | `[{name, description, input_schema}]`，schema 在顶层，不套 `function` |
| `tool_choice`          | `{type:"auto"|"any"|"tool"|"none"}`。Fable 5.1 / Mythos 5.1 拒绝 `any` / `tool` |
| `thinking`             | `{type:"adaptive"}` 或旧式 `{type:"enabled", budget_tokens:N}` |
| `output_config.format` | 结构化输出（`output_format` 已替换）                         |
| `cache_control`        | 顶层自动缓存，或打在单个 content block 上                    |
| `stream`               | true 时 SSE                                                  |

## 响应

```
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

```
{
  "type": "tool_use",
  "id": "toolu_01",
  "name": "get_weather",
  "input": {"location": "Boston, MA"}
}
```

回灌：下一条 `user` 消息的 content 里放 `tool_result`，`tool_use_id` 对齐。下一轮要把上一轮完整 `content`（含 thinking / tool_use）原样追加进 `assistant` 消息。丢掉 thinking 块会校验失败

## 流式

同端点。事件名与 `data.type` 一致。

顺序：

1. `message_start` — 空 `content` 的 Message，含 input usage
2. 每个块：`content_block_start` → 若干 `content_block_delta` → `content_block_stop`
3. `message_delta` — `stop_reason` + 最终 output usage
4. `message_stop`

文本增量：`delta.type == "text_delta"`。工具参数增量：`input_json_delta`（`partial_json`）。中间可能夹 `ping`。不要把所有 `content_block_delta` 都当文本。

## Prompt cache(这个可以查看上下文管理部分,有更详细的讲解)

两种开法：

- 自动：请求顶层 `"cache_control": {"type": "ephemeral"}`，断点落在最后一个可缓存块，多轮会前移。
- 显式：在 tools / system / 某个 content block 上挂 `cache_control`。

默认 TTL 5 分钟，刷新命中免费；另有 1 小时档（写入更贵）。缓存前缀顺序固定：tools → system → messages。usage 里看 `cache_creation_input_tokens` / `cache_read_input_tokens`。

Responses 的 cache 主要靠稳定的 `instructions` + 服务端状态；Messages 是显式断点。两套机制不能对着抄字段名。

## 最小调用

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

## 横切对照(自己看)

### 认证与路径

|                   | Chat Completions        | Responses | Messages                                            |
| ----------------- | ----------------------- | --------- | --------------------------------------------------- |
| Header            | `Authorization: Bearer` | 同左      | `x-api-key`                                         |
| 额外              | 无                      | 无        | `anthropic-version: 2023-06-01`                     |
| SDK base          | 带 `/v1`                | 带 `/v1`  | **不**带 `/v1`（路径自含 `/v1/messages`）           |
| 同一把 OpenAI key | 是                      | 是        | 否（Anthropic key；网关可统一成 `sk-` 再改 header） |

OpenAI 两条协议可以共用 SDK 对象：`client.chat.completions.create` vs `client.responses.create`。Messages 必须换 Anthropic SDK 或改 header。

### 系统提示、角色、内容模型

|              | Chat Completions                    | Responses                                              | Messages                                       |
| ------------ | ----------------------------------- | ------------------------------------------------------ | ---------------------------------------------- |
| 系统提示     | message role `system` / `developer` | 顶层 `instructions`                                    | 顶层 `system`                                  |
| 用户         | `user`                              | `input` 里 user message                                | `user`                                         |
| 助手         | `assistant`                         | `output` 里 `type: message`                            | `assistant`                                    |
| 工具结果角色 | `role: tool` + `tool_call_id`       | item `type: function_call_output` + `call_id`          | 仍是 `user`，块类型 `tool_result`              |
| 内容单元     | string 或 `{type, ...}` part        | 类型化 item；文本 part 叫 `input_text` / `output_text` | 类型化 block：`text` / `tool_use` / `thinking` |

Responses 的 item 模型和 Messages 的 content block 更像：都把 reasoning / tool call 从「一条 assistant message」里拆出来。Chat Completions 把这些粘在 `message` + `tool_calls` 上。

### 采样与长度

| 参数              | Chat Completions        | Responses           | Messages             |
| ----------------- | ----------------------- | ------------------- | -------------------- |
| temperature       | 0–2                     | 0–2                 | **0–1**              |
| 1.5 是否合法      | 是                      | 是                  | 否，400              |
| 输出上限          | `max_completion_tokens` | `max_output_tokens` | `max_tokens`（必填） |
| 是否计入 thinking | 是                      | 是                  | 是                   |
| 多候选 `n`        | 有                      | 无                  | 无                   |
| 惩罚项            | presence / frequency    | 无（当前 schema）   | 无                   |
| stop              | `stop`，最多 4          | 以当前文档为准      | `stop_sequences`     |

移植最容易炸的两件事：Messages 漏 `max_tokens`；把 OpenAI 的 `temperature: 1.5` 打到 Claude。

### 结构化输出

|             | Chat Completions                        | Responses                           | Messages                                                 |
| ----------- | --------------------------------------- | ----------------------------------- | -------------------------------------------------------- |
| 仅合法 JSON | `response_format: {type:"json_object"}` | `text.format: {type:"json_object"}` | 走 schema 形式                                           |
| 带 schema   | `response_format.json_schema`           | `text.format` + `json_schema`       | `output_config.format: {type:"json_schema", schema:...}` |
| 严格模式    | `strict: true`（默认 false）            | 同左，放在 `text.format` 里         | tool `strict: true` / output_config                      |

CC → Responses 只改字段位置，schema 不用重写。

### 工具调用词汇

循环相同：声明 → 模型吐调用 → 本地执行 → 结果作为下一轮输入。字段和落点不同。

|              | Chat Completions                     | Responses                                             | Messages                                          |
| ------------ | ------------------------------------ | ----------------------------------------------------- | ------------------------------------------------- |
| 定义         | `tools[].function.{name,parameters}` | `tools[].{type:"function", name, parameters}`（扁平） | `tools[].{name,input_schema}`                     |
| 让模型决定   | `"auto"`                             | `"auto"`                                              | `{type:"auto"}`                                   |
| 强制用工具   | `"required"`                         | `"required"`                                          | `{type:"any"}`                                    |
| 禁止         | `"none"`                             | `"none"`                                              | `{type:"none"}`                                   |
| 调用落点     | `message.tool_calls[]`               | `output[]` 里 `type: function_call`                   | `content[]` 里 `tool_use`                         |
| 参数类型     | `arguments` **字符串**               | `arguments` **字符串**                                | `input` **对象**                                  |
| 结果落点     | `role: tool`                         | `function_call_output` item                           | `user` + `tool_result`                            |
| 关联 id      | `tool_call_id`                       | `call_id`                                             | `tool_use_id`                                     |
| 内置工具     | 无                                   | web_search 等，一次请求内可连跑                       | web_search / web_fetch 等（Anthropic 服务端工具） |
| 同请求内多步 | 否，每步一次 HTTP                    | **是**（内置工具）；自定义 function 仍要回灌          | 否，每步一次 HTTP                                 |

`any` ≈ `required`（必须调工具）。OpenAI 两套的 `arguments` 都是序列化 JSON 字符串；Anthropic 是已解析对象。网关漏转这个类型会让客户端二次 `JSON.parse` 或 TypeError。

### 推理

|              | Chat Completions                        | Responses                                           | Messages                     |
| ------------ | --------------------------------------- | --------------------------------------------------- | ---------------------------- |
| 开关         | `reasoning_effort`                      | `reasoning.effort`                                  | `thinking`                   |
| 露出思路     | 弱                                      | `reasoning.summary`；output 里独立 `reasoning` item | `thinking` block + `display` |
| 多轮连续性   | 你自己重发；GPT-5.4+ 带 tool 时 CC 受限 | `previous_response_id` 或回放 reasoning item        | 必须把 thinking 块原样带回   |
| 与 tool 同用 | GPT-5.4+ 仅 `effort=none`               | 一等公民                                            | 一等公民                     |

上限字段把 thinking + 可见文本算在一起。上限过小会只产出 thinking、正文为空。

### 流式事件不能混解析

|        | Chat Completions                               | Responses                                               | Messages                                            |
| ------ | ---------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------- |
| 怎么开 | `stream: true`                                 | `stream: true`                                          | `stream: true`                                      |
| 形态   | `data: {chunk}` + `[DONE]`                     | 带 `type` 的语义事件                                    | `event:` + `data:` 成对                             |
| 取文本 | `choices[0].delta.content`                     | `event.type == "response.output_text.delta"` 的 `delta` | `delta.text` 且 `type==text_delta`                  |
| usage  | 默认不在中间包；`stream_options.include_usage` | `response.completed` 上的完整对象                       | `message_start` 有 input，`message_delta` 有 output |

三套解码器不能共用。用 CC 解析器读 Responses 流会找不到 `choices`。

### 状态

|            | Chat Completions                       | Responses                                  | Messages                |
| ---------- | -------------------------------------- | ------------------------------------------ | ----------------------- |
| 默认       | 无状态，重发 `messages`                | `store: true`，可链 `previous_response_id` | 无状态，重发 `messages` |
| 服务端会话 | 无（除非自己存 completion id，能力弱） | Conversations API + `previous_response_id` | 无                      |
| 关掉存储   | `store: false`                         | `store: false` + 加密 reasoning 回放       | 本来就不存              |

`previous_response_id` 省的是**重传字节和 cache 友好性**，不是免掉历史 token 账单。