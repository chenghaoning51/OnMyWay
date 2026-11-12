+++
title = "Token counting"
slug = "token-counting"
weight = 120
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "在把 message 发给 Claude 之前统计其中的 tokens。用 token 计数来管理速率限制和成本、做模型路由决策，以及把 prompt 调整到目标长度。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/token-counting"
+++

## 兼容性
- [ZDR](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention): 符合条件（不含 [Covered Models](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention#model-specific-data-retention-requirements)）
- 平台: Claude API, Claude Platform on AWS, Amazon Bedrock, Google Cloud, Microsoft Foundry

Token counting 可以让你在把 message 发给 Claude 之前确定其中的 token 数量。这有助于你就 prompt 和用量做出更有依据的决策。借助 token counting，你可以：

* 主动管理速率限制和成本
* 做出明智的模型路由决策
* 将 prompt 优化到特定长度

***

## 如何统计 message tokens

[token counting](https://platform.claude.com/docs/en/api/messages-count-tokens) endpoint 接受与创建 message 相同的结构化输入列表，包括对 system prompt、[tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview)、[images](https://platform.claude.com/docs/en/build-with-claude/vision) 和 [PDFs](https://platform.claude.com/docs/en/build-with-claude/pdf-support) 的支持。响应中包含输入 tokens 的总数。

对于 Messages API 会接受、但本 endpoint 不接受的少数输入，该 endpoint 会返回 `invalid_request_error`：例如 web search、web fetch、code execution 和 tool search 等 [server tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools)（[advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool) 除外的所有 server tool）、[MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector)，以及 `source` 为 `url` 或 `file` 的 `image` 或 `document` blocks。统计图片和 PDF 时请以 base64 发送。对于使用 server tools 或 MCP servers 的请求，Messages API 响应会在其 `usage` 对象中报告所用 tokens。

<Note>
  Token 计数是一个**估计**。在某些情况下，创建 message 时实际使用的输入 tokens 数量可能有小幅差异。

  Token 计数可能包含 Anthropic 为系统优化自动添加的 tokens。**系统添加的 tokens 不会向你计费**。计费只反映你的内容。
</Note>

### 支持的模型

所有 [active models](https://platform.claude.com/docs/en/models/overview) 都支持 token counting。

<Note>
  Claude 4.7 及之后的模型和 Claude Mythos Preview 使用较新的 tokenizer。同一段输入文本产生的 tokens 大约比早期模型多 30 percent。具体增幅取决于内容和 workload 形态。请针对你计划使用的模型重新统计 prompt，而不是复用在早期模型上测得的计数。
</Note>

### 统计基本 messages 中的 tokens

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.messages.count_tokens(
      model="claude-opus-5",
      system="You are a scientist",
      messages=[{"role": "user", "content": "Hello, Claude"}],
  )

  print(response.json())
  ```

</CodeGroup>

```json Output
{ "input_tokens": 14 }
```

### 统计带 tools 的 messages 中的 tokens

<Note>
  Token counting 支持 client tools 和 [advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool)。包含其他 [server tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools) 的请求会返回错误。对于 advisor tool，计数只覆盖 executor 的第一次 sampling call。
</Note>

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.messages.count_tokens(
      model="claude-opus-5",
      tools=[
          {
              "name": "get_weather",
              "description": "Get the current weather in a given location",
              "input_schema": {
                  "type": "object",
                  "properties": {
                      "location": {
                          "type": "string",
                          "description": "The city and state, e.g. San Francisco, CA",
                      }
                  },
                  "required": ["location"],
              },
          }
      ],
      messages=[{"role": "user", "content": "What's the weather like in San Francisco?"}],
  )

  print(response.json())
  ```

</CodeGroup>

```json Output
{ "input_tokens": 403 }
```

### 统计带图片的 messages 中的 tokens

<CodeGroup>

  ```python Python
  import base64
  import httpx2

  image_url = "https://platform.claude.com/docs/images/vision-example.jpg"
  image_media_type = "image/jpeg"
  image_data = base64.standard_b64encode(httpx2.get(image_url).content).decode("utf-8")

  client = anthropic.Anthropic()

  response = client.messages.count_tokens(
      model="claude-opus-5",
      messages=[
          {
              "role": "user",
              "content": [
                  {
                      "type": "image",
                      "source": {
                          "type": "base64",
                          "media_type": image_media_type,
                          "data": image_data,
                      },
                  },
                  {"type": "text", "text": "Describe this image"},
              ],
          }
      ],
  )
  print(response.json())
  ```

</CodeGroup>

```json Output
{ "input_tokens": 1028 }
```

设置了 [`"oversized_image": "error"`](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates#oversized-image-error) 的嵌入 image block 会在计数时被拒绝，拒绝方式与 Messages API 完全相同。

### 统计带 thinking 的 messages 中的 tokens

<Note>
  更多细节见 [Thinking and the context window](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-the-context-window)。

  * 来自**先前** assistant turn 的 thinking blocks，在 [保留全部先前 turns](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-block-preservation-by-model) 的模型上会计入你的输入 tokens；在只保留最后一个 turn 的模型上，API 会剥离它们，因此**不**计入
  * **当前** assistant turn 的 thinking **会**计入你的输入 tokens
</Note>

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.messages.count_tokens(
      model="claude-opus-5",
      thinking={"type": "adaptive"},
      messages=[
          {
              "role": "user",
              "content": "Are there an infinite number of prime numbers such that n mod 4 == 3?",
          },
          {
              "role": "assistant",
              "content": [
                  {
                      "type": "thinking",
                      "thinking": "This is a nice number theory question. Let's think about it step by step...",
                      "signature": "EuYBCkQYAiJAgCs1le6/Pol5Z4/JMomVOouGrWdhYNsH3ukzUECbB6iWrSQtsQuRHJID6lWV...",
                  },
                  {
                      "type": "text",
                      "text": "Yes, there are infinitely many prime numbers p such that p mod 4 = 3...",
                  },
              ],
          },
          {"role": "user", "content": "Can you write a formal proof?"},
      ],
  )

  print(response.json())
  ```

</CodeGroup>

```json Output
{ "input_tokens": 88 }
```

### 统计带 PDF 的 messages 中的 tokens

<Note>
  Token counting 支持 base64 编码的 PDF，要求与 Messages API 的 [PDF requirements](https://platform.claude.com/docs/en/build-with-claude/pdf-support#check-pdf-requirements) 相同。该 endpoint 不支持 `url` 或 `file` 类型的 document source。
</Note>

<CodeGroup>

  ```python Python
  import base64
  import anthropic

  client = anthropic.Anthropic()

  with open("/path/to/document.pdf", "rb") as pdf_file:
      pdf_base64 = base64.standard_b64encode(pdf_file.read()).decode("utf-8")

  response = client.messages.count_tokens(
      model="claude-opus-5",
      messages=[
          {
              "role": "user",
              "content": [
                  {
                      "type": "document",
                      "source": {
                          "type": "base64",
                          "media_type": "application/pdf",
                          "data": pdf_base64,
                      },
                  },
                  {"type": "text", "text": "Please summarize this document."},
              ],
          }
      ],
  )

  print(response.json())
  ```

</CodeGroup>

```json Output
{ "input_tokens": 2188 }
```

***

## Claude Fable 和 Claude Mythos 模型上的 token 计数

Claude Fable 5.1、Claude Mythos 5.1、Claude Fable 5 和 Claude Mythos 5 共用 Claude Opus 4.7 引入的 tokenizer。同一段 prompt 在这四个模型上的计数相同，并且比 Claude Opus 4.7 之前的模型大约高 30 percent（具体增幅取决于内容）。token counting endpoint 按你传入的 `model` 所对应的 tokenizer 计数。要衡量对你 workload 的差异，请对同一请求计数两次：一次用当前模型，一次用你计划迁移到的模型，然后比较两次的 `input_tokens` 值。

<Note>
  **计费与迁移：** 这些模型上的用量和计费以该 tokenizer 的计数为准。从 Claude Opus 4.7 之前的模型迁移时，不要复用在旧模型上测得的 token 计数来估计成本或上下文窗口是否放得下。请用你计划使用的 `model` ID（例如 `"claude-fable-5-1"`）来统计 prompt。
</Note>

***

## 定价与速率限制

Token counting **免费使用**，但受基于你的 [usage tier](https://platform.claude.com/docs/en/api/rate-limits#rate-limits) 的每分钟请求数速率限制约束。如果需要更高限额，请在 [Rate limits](https://platform.claude.com/settings/limits) 页面使用 **Request rate limit increase**。

| Usage tier | 每分钟请求数 (RPM) |
| ---------- | ------------------------- |
| Start      | 5,000                     |
| Build      | 10,000                    |
| Scale      | 20,000                    |

<Note>
  Token counting 与 message 创建有各自独立的速率限制。使用其中一项不会占用另一项的限额。
</Note>

***

## FAQ

<AccordionGroup>
  <Accordion title="Token counting 会使用 prompt caching 吗？">
    不会。Token counting 提供估计，不使用缓存逻辑。虽然你可以在 token counting 请求中提供 `cache_control` blocks，但 prompt caching 只在实际创建 message 时发生。
  </Accordion>
</AccordionGroup>

***

## 后续步骤

<CardGroup cols={2}>
  <Card title="统计 message tokens" icon="code" href="https://platform.claude.com/docs/en/api/messages-count-tokens">
    阅读 token counting endpoint 的完整 API 参考。
  </Card>

  <Card title="上下文窗口" icon="arrows-maximize" href="https://platform.claude.com/docs/en/build-with-claude/context-windows">
    用 token 计数把 prompt 控制在模型的上下文窗口内。
  </Card>

  <Card title="速率限制" icon="gauge" href="https://platform.claude.com/docs/en/api/rate-limits">
    在发送请求前检查 token 计数，以保持在你的 usage tier 内。
  </Card>

  <Card title="Prompt caching" icon="database" href="https://platform.claude.com/docs/en/build-with-claude/prompt-caching">
    通过缓存 prompt 前缀，降低重复 prompt 的成本和延迟。
  </Card>
</CardGroup>