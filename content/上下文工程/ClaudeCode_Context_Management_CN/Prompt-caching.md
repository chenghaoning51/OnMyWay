+++
title = "Prompt Caching"
slug = "prompt-caching"
weight = 110
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "使用 `cache_control` 缓存 prompt 前缀，以降低成本和延迟；可采用自动缓存或显式缓存断点，TTL 为 5 分钟或 1 小时。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/prompt-caching"
+++

Prompt Caching 通过允许从 prompt 中的特定前缀恢复来优化 API 用量。对于重复性任务或包含一致元素的 prompt，这会显著降低处理时间和成本。

<Note>
  要了解零数据保留（ZDR）如何适用于此功能，请参阅 [API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)。
</Note>

有两种方式启用 Prompt Caching：

* **[自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)**：在请求的顶层添加单个 `cache_control` 字段。系统会自动将缓存断点应用到最后一个可缓存块，并随对话增长向前移动。最适合多轮对话，其中不断增长的消息历史应被自动缓存。
* **[显式缓存断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)**：将 `cache_control` 直接放在各个内容块上，以精细控制究竟缓存哪些内容。

最简单的起步方式是使用自动缓存：

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.messages.create(
      model="claude-opus-5",
      max_tokens=1024,
      cache_control={"type": "ephemeral"},
      system="You are an AI assistant tasked with analyzing literary works. Your goal is to provide insightful commentary on themes, characters, and writing style.",
      messages=[
          {
              "role": "user",
              "content": "Analyze the major themes in 'Pride and Prejudice'.",
          }
      ],
  )
  print(response.usage.model_dump_json())
  ```

</CodeGroup>

使用自动缓存时，系统会缓存直到并包括最后一个可缓存块的全部内容。在后续具有相同前缀的请求中，缓存内容会自动复用。

***

## Prompt Caching 如何工作

当你发送启用了 Prompt Caching 的请求时：

1. 系统检查某个 prompt 前缀（直到指定的缓存断点）是否已从近期查询中缓存。
2. 如果找到，则使用缓存版本，从而降低处理时间和成本。
3. 否则，系统处理完整 prompt，并在响应开始后缓存该前缀。

这尤其适用于：

* 包含大量示例的 prompt
* 大量上下文或背景信息
* 带有一致指令的重复性任务
* 较长的多轮对话

默认情况下，缓存的生命周期为 5 分钟。每次使用缓存内容时，缓存都会刷新，且不产生额外费用。

生命周期从写入或读取该缓存条目的请求开始时刻起算，而非从其响应结束时刻起算。生成响应所花费的时间会计入生命周期：如果一次响应需要 4 分钟才能完成流式传输，则复用同一缓存前缀的后续请求必须在该响应完成后大约 1 分钟内开始。

<Note>
  如果你觉得 5 分钟太短，Anthropic 还提供 1 小时缓存时长，[需额外付费](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#pricing)。

  更多信息请参阅 [1 小时缓存时长](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)。
</Note>

<Tip>
  **Prompt Caching 缓存完整前缀**

  Prompt Caching 引用整个 prompt——`tools`、`system` 和 `messages`（按此顺序），直到并包括用 `cache_control` 指定的块。
</Tip>

***

## 定价

Prompt Caching 引入了新的定价结构。下表列出了每个支持的模型每百万 token 的价格：

| 模型                                                        | 基础输入 token | 5 分钟缓存写入 | 1 小时缓存写入 | 缓存命中与刷新 | 输出 token |
| ------------------------------------------------------------ | ----------------- | --------------- | --------------- | ------------------------ | ------------- |
| Claude Fable 5.1                                             | $10 / MTok        | $12.50 / MTok   | $20 / MTok      | $0.25 / MTok1            | $50 / MTok    |
| Claude Mythos 5.1 ([有限供应](https://anthropic.com/glasswing)) | $10 / MTok        | $12.50 / MTok   | $20 / MTok      | $0.25 / MTok1            | $50 / MTok    |
| Claude Fable 5                                               | $10 / MTok        | $12.50 / MTok   | $20 / MTok      | $1 / MTok                | $50 / MTok    |
| Claude Mythos 5 ([有限供应](https://anthropic.com/glasswing)) | $10 / MTok        | $12.50 / MTok   | $20 / MTok      | $1 / MTok                | $50 / MTok    |
| Claude Opus 5                                                | $5 / MTok         | $6.25 / MTok    | $10 / MTok      | $0.50 / MTok             | $25 / MTok    |
| Claude Opus 4.8                                              | $5 / MTok         | $6.25 / MTok    | $10 / MTok      | $0.50 / MTok             | $25 / MTok    |
| Claude Opus 4.7                                              | $5 / MTok         | $6.25 / MTok    | $10 / MTok      | $0.50 / MTok             | $25 / MTok    |
| Claude Opus 4.6                                              | $5 / MTok         | $6.25 / MTok    | $10 / MTok      | $0.50 / MTok             | $25 / MTok    |
| Claude Opus 4.5                                              | $5 / MTok         | $6.25 / MTok    | $10 / MTok      | $0.50 / MTok             | $25 / MTok    |
| Claude Opus 4.1 ([已退役，Bedrock 和 Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $15 / MTok        | $18.75 / MTok   | $30 / MTok      | $1.50 / MTok             | $75 / MTok    |
| Claude Opus 4 ([已退役，Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $15 / MTok        | $18.75 / MTok   | $30 / MTok      | $1.50 / MTok             | $75 / MTok    |
| Claude Sonnet 5                                              | $2 / MTok         | $2.50 / MTok    | $4 / MTok       | $0.20 / MTok             | $10 / MTok    |
| Claude Sonnet 4.6                                            | $3 / MTok         | $3.75 / MTok    | $6 / MTok       | $0.30 / MTok             | $15 / MTok    |
| Claude Sonnet 4.5                                            | $3 / MTok         | $3.75 / MTok    | $6 / MTok       | $0.30 / MTok             | $15 / MTok    |
| Claude Sonnet 4 ([已退役，Bedrock 和 Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $3 / MTok         | $3.75 / MTok    | $6 / MTok       | $0.30 / MTok             | $15 / MTok    |
| Claude Haiku 4.5                                             | $1 / MTok         | $1.25 / MTok    | $2 / MTok       | $0.10 / MTok             | $5 / MTok     |
| Claude Haiku 3.5 ([已退役，Bedrock 和 Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)) | $0.80 / MTok      | $1 / MTok       | $1.60 / MTok    | $0.08 / MTok             | $4 / MTok     |

*1 Claude Fable 5.1 和 Claude Mythos 5.1 的缓存命中与刷新按基础输入价格的 0.025 倍计费。所有其他模型使用标准的 0.1 倍乘数。*

<Note>
  上表反映了 Prompt Caching 的以下定价乘数：

  * 5 分钟缓存写入 token 为基础输入 token 价格的 1.25 倍
  * 1 小时缓存写入 token 为基础输入 token 价格的 2 倍
  * 缓存读取 token 为基础输入 token 价格的 0.1 倍（各模型例外见上表脚注）

  这些乘数会与其他定价调整项叠加，例如 Batch API 折扣和数据驻留。完整详情请参阅 [pricing](https://platform.claude.com/docs/en/about-claude/pricing)。
</Note>

***

## 支持的模型

Prompt Caching（自动缓存和显式缓存断点）在所有[当前可用的 Claude 模型](https://platform.claude.com/docs/en/models/overview)上均受支持。

***

## 自动缓存

自动缓存是启用 Prompt Caching 的最简单方式。不必在各个内容块上放置 `cache_control`，只需在请求体顶层添加单个 `cache_control` 字段。系统会自动将缓存断点应用到最后一个可缓存块。

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.messages.create(
      model="claude-opus-5",
      max_tokens=1024,
      cache_control={"type": "ephemeral"},
      system="You are a helpful assistant that remembers our conversation.",
      messages=[
          {"role": "user", "content": "My name is Alex. I work on machine learning."},
          {
              "role": "assistant",
              "content": "Nice to meet you, Alex! How can I help with your ML work today?",
          },
          {"role": "user", "content": "What did I say I work on?"},
      ],
  )
  print(response.usage.model_dump_json())
  ```

</CodeGroup>

### 自动缓存在多轮对话中如何工作

使用自动缓存时，缓存点会随对话增长自动向前移动。每个新请求会缓存直到最后一个可缓存块的全部内容，而先前内容则从缓存读取。

| 请求   | 内容                                                      | 缓存行为                                               |
| --------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 请求 1 | System + User(1) + Asst(1) + **User(2)** ◀ cache             | 全部写入缓存                                  |
| 请求 2 | System + User(1) + Asst(1) + User(2) + Asst(2) + **User(3)** ◀ cache | System 到 User(2) 从缓存读取；Asst(2) + User(3) 写入缓存 |
| 请求 3 | System + User(1) + Asst(1) + User(2) + Asst(2) + User(3) + Asst(3) + **User(4)** ◀ cache | System 到 User(3) 从缓存读取；Asst(3) + User(4) 写入缓存 |

缓存断点会在每个请求中自动移到最后一个可缓存块，因此你无需随对话增长去更新任何 `cache_control` 标记。

### TTL 支持

默认情况下，自动缓存使用 5 分钟 TTL。你可以指定 1 小时 TTL，价格为基础输入 token 价格的 2 倍：

```json
{ "cache_control": { "type": "ephemeral", "ttl": "1h" } }
```

### 与块级缓存结合

自动缓存与[显式缓存断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)兼容。一起使用时，自动缓存断点会占用 4 个可用断点槽位中的一个。

这让你可以同时采用两种方式。例如，用显式断点缓存 system prompt，同时由自动缓存处理对话：

```json
{
  "model": "claude-opus-5",
  "max_tokens": 1024,
  "cache_control": { "type": "ephemeral" },
  "system": [
    {
      "type": "text",
      "text": "You are a helpful assistant.",
      "cache_control": { "type": "ephemeral" }
    }
  ],
  "messages": [{ "role": "user", "content": "What are the key terms?" }]
}
```

### 哪些保持不变

自动缓存使用相同的底层缓存基础设施。定价、最低 token 阈值、上下文顺序要求以及 20 块回看窗口，均与显式缓存断点相同。

### 边界情况

* 如果最后一个块已经带有相同 TTL 的显式 `cache_control`，自动缓存为 no-op。
* 如果最后一个块带有不同 TTL 的显式 `cache_control`，API 返回 400 error。
* 如果已经存在 4 个显式块级断点，API 返回 400 error（没有剩余槽位给自动缓存）。
* 如果最后一个块不适合作为自动缓存断点目标，系统会静默向后查找最近的合格块。如果找不到，则跳过缓存。

<Note>
  自动缓存在除旧版 [Amazon Bedrock (Opus 4.6 and earlier)](https://platform.claude.com/docs/en/build-with-claude/claude-on-amazon-bedrock-legacy) 集成之外的所有平台上均可用。在该集成上，顶层 `cache_control` 字段会使 API 返回 400 error，因此请改用[显式缓存断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)。
</Note>

***

## 显式缓存断点

若要更精细地控制缓存，你可以将 `cache_control` 直接放在各个内容块上。当你需要缓存以不同频率变化的不同区段，或需要精细控制究竟缓存哪些内容时，这很有用。

### 组织你的 prompt

将静态内容（工具定义、系统指令、上下文、示例）放在 prompt 开头。使用 `cache_control` 参数标记可复用内容的末尾以便缓存。

缓存前缀按以下顺序创建：`tools`、`system`，然后是 `messages`。该顺序形成层级，每一层都建立在前一层之上。

#### 自动前缀检查如何工作

你可以只在静态内容末尾使用一个缓存断点，系统会自动找到先前请求已经写入缓存的最长前缀。理解其工作方式有助于优化缓存策略。

**三条核心原则：**

1. **缓存写入只发生在你的断点处。** 用 `cache_control` 标记一个块只会写入恰好一条缓存条目：以该块结尾的前缀的哈希。系统不会为任何更早的位置写入条目。因为哈希是累积的，覆盖直到并包括断点的全部内容，所以更改断点处或断点之前的任何块都会在下一次请求时产生不同的哈希。

2. **缓存读取会向后查找先前请求写入的条目。** 每次请求时，系统会在你的断点处计算前缀哈希并检查是否有匹配的缓存条目。如果不存在，它会一次向后走一个块，检查每个更早位置的前缀哈希是否匹配缓存中已有的内容。它查找的是先前的写入，而不是稳定内容。

3. **回看窗口为 20 块。** 每个断点系统最多检查 20 个位置，断点本身计为第一个。如果系统在该窗口内找不到匹配条目，检查即停止（若存在下一个显式缓存断点，则从该断点继续）。在 Claude API 上，连续的 `tool_use` 块计为一个位置，连续的 `tool_result` 块也是如此，因此一轮中有许多并行工具调用本身不会把先前请求的条目挤出窗口。

**示例：增长中的对话里的回看**

你每轮追加新块，并在每个请求的最后一个块上设置 `cache_control`：

* **第 1 轮：** 10 个块，断点在第 10 块。不存在先前的缓存条目。系统在第 10 块写入一条条目。
* **第 2 轮：** 15 个块，断点在第 15 块。第 15 块没有条目，因此系统回看到第 10 块并找到第 1 轮的条目。在第 10 块缓存命中；系统只重新处理第 11 到第 15 块，并在第 15 块写入新条目。
* **第 3 轮：** 35 个块，断点在第 35 块。系统检查 20 个位置（第 35 到第 16 块）且什么也没找到。第 2 轮在第 15 块的条目刚好在窗口外一个位置，因此没有缓存命中。在第 15 块添加第二个断点会在那里开启第二个回看窗口，从而找到第 2 轮的条目。

**常见错误：把断点放在每次请求都会变化的内容上**

你的 prompt 有一大段静态系统上下文（第 1 到第 5 块），后面跟着一个每请求都会出现的块，其中包含时间戳和用户消息（第 6 块）。你在第 6 块上设置 `cache_control`：

* **请求 1：** 在第 6 块缓存写入。哈希包含时间戳。
* **请求 2：** 时间戳不同，因此第 6 块的前缀哈希不同。回看走过第 5、4、3、2 和 1 块，但系统从未在这些位置写入过条目。没有缓存命中。你每次请求都要为一次全新的缓存写入付费，并且永远得不到读取。

回看不会去发现断点之前的稳定内容并缓存它。它查找的是先前请求已经写入的条目，而写入只发生在断点处。把 `cache_control` 移到第 5 块——跨请求保持不变的最后一块——之后每个后续请求都会读取该缓存前缀。[自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)会落入同样的陷阱：它把断点放在最后一个可缓存块上，而在这种结构中该块每次请求都会变化，因此应改在第 5 块使用显式缓存断点。

**关键要点：** 将 `cache_control` 放在你希望共享缓存的那些请求之间前缀完全相同的最后一个块上。在增长中的对话里，只要每轮新增少于 20 个块，最后一个块就可以：更早的内容从不变化，因此下一次请求的回看能找到先前的写入。对于带有变化后缀（时间戳、每请求上下文、传入消息）的 prompt，把断点放在静态前缀的末尾，而不是放在变化的块上。

#### 何时使用多个断点

如果你希望做到以下几点，最多可以定义 4 个缓存断点：

* 缓存以不同频率变化的不同区段（例如，工具很少变化，但上下文每天更新）
* 更精细地控制究竟缓存哪些内容
* 当增长中的对话把你的断点推到距上次缓存写入 20 个或更多块时，仍能确保缓存命中

<Note>
  **重要限制：** 回看只能找到更早请求已经写入的条目。如果增长中的对话把你的断点推到距上次写入 20 个或更多块，回看窗口就会错过它。从一开始就在更靠近该位置处添加第二个断点，以便在你需要之前就在那里累积一次写入。
</Note>

### 理解缓存断点的成本

**缓存断点本身不会增加任何成本。** 你只需为以下项付费：

* **缓存写入：** 当新内容写入缓存时（5 分钟 TTL 比基础输入 token 贵 25%）
* **缓存读取：** 当使用缓存内容时（基础输入 token 价格的 10%，或在 Claude Fable 5.1 和 Claude Mythos 5.1 上为 2.5%）
* **常规输入 token：** 任何未缓存的内容

添加更多 `cache_control` 断点不会增加成本——你仍然根据实际被缓存和读取的内容支付相同金额。断点让你可以控制哪些区段能被独立缓存。

***

## 缓存策略与注意事项

### 缓存限制

在 Claude API、[Claude Platform on AWS](https://platform.claude.com/docs/en/build-with-claude/claude-platform-on-aws)、[Google Cloud](https://platform.claude.com/docs/en/build-with-claude/claude-on-vertex-ai) 和 [Microsoft Foundry](https://platform.claude.com/docs/en/build-with-claude/claude-in-microsoft-foundry) 上，可缓存 prompt 的最短长度为：

* Claude Fable 5.1、Claude Mythos 5.1、Claude Opus 5、Claude Fable 5 和 [Claude Mythos 5](https://anthropic.com/glasswing) 为 512 tokens
* [Claude Mythos Preview](https://anthropic.com/glasswing) 和 Claude Opus 4.7 为 2,048 tokens
* Claude Opus 4.6 和 Claude Opus 4.5 为 4,096 tokens
* Claude Opus 4.8、Claude Sonnet 5、Claude Sonnet 4.6、Claude Sonnet 4.5、Claude Opus 4.1（[已退役，Bedrock 和 Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)）、Claude Opus 4（[已退役，Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)）和 Claude Sonnet 4（[已退役，Bedrock 和 Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)）为 1,024 tokens
* Claude Haiku 4.5 为 4,096 tokens
* Claude Haiku 3.5（[已退役，Bedrock 和 Google Cloud 除外](https://platform.claude.com/docs/en/about-claude/model-deprecations)）为 2,048 tokens

这些下限适用于每个模型可用的所有平台。

更短的 prompt 即使标有 `cache_control` 也无法缓存。任何请求缓存少于该数量 token 的内容都会在不缓存的情况下处理，且不会返回错误。要验证 prompt 是否被缓存，请检查[响应 usage 字段](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#tracking-cache-performance)：如果 `cache_creation_input_tokens` 和 `cache_read_input_tokens` 均为 0，则该 prompt 未被缓存（很可能是因为它未达到最短长度要求）。

如果你的 prompt 刚好略低于所用模型和平台的下限，扩展被缓存内容以达到阈值通常是值得的。缓存读取的成本显著低于未缓存的输入 token，因此达到下限可以降低频繁复用 prompt 的成本。

<Note>
  [Bedrock](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock) 是 AWS 运营的平台。在 Bedrock 上，请参阅 [Bedrock prompt caching documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/prompt-caching.html)，了解适用的各模型下限、失败行为以及 usage 字段名称。
</Note>

对于并发请求，请注意缓存条目只有在第一次响应开始之后才可用。如果并行请求需要缓存命中，请在发送后续请求之前等待第一次响应。

目前，"ephemeral" 是唯一受支持的缓存类型，默认生命周期为 5 分钟。

### 哪些内容可以缓存

请求中的大多数块都可以缓存。这包括：

* 工具：`tools` 数组中的工具定义
* 系统消息：`system` 数组中的内容块
* 文本消息：`messages.content` 数组中的内容块，适用于 user 和 assistant 两轮
* 图像和文档：`messages.content` 数组中的内容块，位于 user 轮
* 工具使用和工具结果：`messages.content` 数组中的内容块，适用于 user 和 assistant 两轮

这些元素都可以缓存，既可以自动缓存，也可以用 `cache_control` 标记。

### 哪些内容不能缓存

虽然大多数请求块可以缓存，但也有一些例外：

* Thinking 块不能用 `cache_control` 直接缓存。但是，当 thinking 块出现在先前的 assistant 轮中时，它们可以与其他内容一起被缓存。以这种方式缓存时，从缓存读取时它们会计入输入 token。

* 子内容块（例如 [citations](https://platform.claude.com/docs/en/build-with-claude/citations)）本身不能直接缓存。应改为缓存顶层块。

  对于 citations，作为 citations 源材料的顶层文档内容块可以缓存。这样你可以通过缓存 citations 将引用的文档，有效地将 Prompt Caching 与 citations 一起使用。

* 空文本块不能缓存。

### 什么会使缓存失效

对已缓存内容的修改会使部分或全部缓存失效。

如[组织你的 prompt](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#structuring-your-prompt) 所述，缓存遵循层级：`tools` → `system` → `messages`。每一层的变更会使该层及之后的所有层失效。

下表显示不同类型的变更会使缓存的哪些部分失效。✘ 表示缓存失效，✓ 表示缓存仍然有效。

| 变更内容                                              | Tools 缓存    | System 缓存   | Messages 缓存 | 影响                                                       |
| --------------------------------------------------------- | -------------- | -------------- | -------------- | ------------------------------------------------------------ |
| **工具定义**                                      | ✘              | ✘              | ✘              | 修改工具定义（名称、描述、参数）会使整个缓存失效 |
| **Web search 开关**                                     | ✓              | ✘              | ✘              | 启用/禁用 web search 会修改 system prompt     |
| **Citations 开关**                                      | ✓              | ✘              | ✘              | 启用/禁用 citations 会修改 system prompt      |
| **速度设置**                                         | ✓              | ✘              | ✘              | 在 [`speed: "fast"` 与标准速度](https://platform.claude.com/docs/en/build-with-claude/fast-mode) 之间切换会使 system 和 message 缓存失效 |
| **Tool choice**                                           | ✓              | ✓              | ✘              | 对 `tool_choice` 参数的更改只影响 message 块 |
| **图像**                                                | ✓              | ✓              | ✘              | 在 prompt 任意位置添加/移除图像会影响 message 块 |
| **Thinking 参数**                                   | 因模型而异 | 因模型而异 | ✘              | thinking 配置（模式，以及 extended mode 中的 `budget_tokens`）会被渲染进 prompt，因此更改它总会使 message 块失效；在把该配置渲染在它们之前的模型上，tool 和 system 缓存也会失效。参见 [Thinking and prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-prompt-caching)。 |
| **Effort 设置**                                        | 因模型而异 | 因模型而异 | ✘              | 更改 [`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort) 值总会使 message 块失效，对 tool 和 system 缓存的模型相关影响与 thinking 参数相同。将 effort 显式设为模型默认值等价于省略它，不会使缓存失效。在支持[逐条消息 effort](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta) 的模型上，通过 `messages` 内 `role: "system"` 消息携带的 effort 变更会保持缓存前缀完好。 |
| **传入 extended thinking 请求的非工具结果** | ✓              | ✓              | 因模型而异 | 在 Opus 4.5+ 和 Sonnet 4.6+ 上，thinking 块默认被保留，因此缓存仍然有效（✓）。在更早的 Opus/Sonnet 模型以及所有 Haiku 模型上，所有先前已缓存的 thinking 块会从上下文中剥离，跟随这些 thinking 块的任何消息也会从缓存中移除（✘）。更多详情见 [Caching with thinking blocks](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#caching-with-thinking-blocks)。 |
| **被丢弃的 thinking 块**                               | ✓              | ✓              | ✘              | 当 API 丢弃一个在该请求上未被[保留](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-thinking) 的 Claude Fable 5.1 或 Claude Mythos 5.1 thinking 块时（例如，你把它重放到更早的模型），该请求上从该块位置起的缓存前缀会发生变化。接收模型能够读取、且原样传回的块会保持缓存完好。 |

<Note>
  在 Claude Fable 5.1、Claude Mythos 5.1、Claude Fable 5、[Claude Mythos 5](https://anthropic.com/glasswing)、Claude Opus 4.8 和 Claude Opus 5 上，你可以在对话中途添加新的系统指令，而不会使 system 或 message 缓存失效。向 `messages` 追加一条 `{"role": "system"}` 消息，而不是编辑顶层 `system` 字段，这样缓存前缀保持不变。此功能在 Claude Sonnet 5 上不可用。请改用顶层 `system` 字段。参见 [Mid-conversation system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)。
</Note>

### 跟踪缓存表现

使用 API 响应中 `usage` 内的这些字段监控缓存表现（若使用 [streaming](https://platform.claude.com/docs/en/build-with-claude/streaming)，则在 `message_start` 事件中）：

* `cache_creation_input_tokens`：创建新条目时写入缓存的 token 数。
* `cache_read_input_tokens`：本次请求从缓存检索的 token 数。
* `input_tokens`：既未从缓存读取、也未用于创建缓存的输入 token 数（即最后一个缓存断点之后的 token）。

<Note>
  **理解 token 分解**

  `input_tokens` 字段只表示请求中**最后一个缓存断点之后**的 token——并非你发送的全部输入 token。

  要计算总输入 token：

  ```text wrap
  total_input_tokens = cache_read_input_tokens + cache_creation_input_tokens + input_tokens
  ```

  **空间解释：**

  * `cache_read_input_tokens` = 断点之前已经缓存的 token（读取）
  * `cache_creation_input_tokens` = 断点之前正在被缓存的 token（写入）
  * `input_tokens` = 最后一个断点之后的 token（不符合缓存条件）

  **示例：** 如果你有一个请求包含 100,000 tokens 的已缓存内容（从缓存读取）、0 tokens 的正在被缓存的新内容，以及用户消息中的 50 tokens（在缓存断点之后）：

  * `cache_read_input_tokens`: 100,000
  * `cache_creation_input_tokens`: 0
  * `input_tokens`: 50
  * **处理的总输入 token：** 100,050 tokens

  这对于理解成本和速率限制都很重要，因为有效使用缓存时，`input_tokens` 通常会远小于你的总输入。
</Note>

### 使用 thinking 块进行缓存

将 [thinking](https://platform.claude.com/docs/en/build-with-claude/thinking) 与 Prompt Caching 一起使用时，thinking 块有特殊行为：

**与其他内容一起自动缓存：** 虽然 thinking 块不能用 `cache_control` 显式标记，但当你带着 tool results 发起后续 API 调用时，它们会作为请求内容的一部分被缓存。这在 tool use 期间很常见：你把 thinking 块传回去以继续对话。

**输入 token 计数：** 当 thinking 块从缓存读取时，它们会计入 usage 指标中的输入 token。这对成本计算和 token 预算很重要。

**缓存失效模式：**

* 当仅以 user messages 提供 tool results 时，缓存仍然有效
* 在 Opus 4.5+ 和 Sonnet 4.6+ 上，即使添加了非 tool-result 的用户内容，thinking 块默认仍被保留，因此缓存仍然有效
* 在更早的 Opus/Sonnet 模型以及所有 Haiku 模型上，添加非 tool-result 的用户内容会使缓存失效，导致所有先前的 thinking 块从上下文中剥离
* 即使没有显式的 `cache_control` 标记，也会出现这种缓存行为

关于缓存失效的更多详情，请参阅[什么会使缓存失效](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)。

**结合 tool use 的示例：**

```text wrap
Request 1: User: "What's the weather in Paris?"
Response: [thinking_block_1] + [tool_use block 1]

Request 2:
User: ["What's the weather in Paris?"],
Assistant: [thinking_block_1] + [tool_use block 1],
User: [tool_result_1, cache=True]
Response: [thinking_block_2] + [text block 2]
# Request 2 caches its request content (not the response)
# The cache includes: user message, thinking_block_1, tool_use block 1, and tool_result_1

Request 3:
User: ["What's the weather in Paris?"],
Assistant: [thinking_block_1] + [tool_use block 1],
User: [tool_result_1, cache=True],
Assistant: [thinking_block_2] + [text block 2],
User: [Text response, cache=True]
# On earlier Opus/Sonnet and all Haiku models, non-tool-result user block causes prior thinking blocks to be stripped; on Opus 4.5+/Sonnet 4.6+ they are kept
```

在更早的 Opus/Sonnet 模型以及所有 Haiku 模型上，此时所有先前的 thinking 块都会从上下文中移除。在 Opus 4.5+ 和 Sonnet 4.6+ 上，先前的 thinking 块默认被保留，并仍是缓存前缀的一部分。

更详细的信息请参阅 [Thinking and prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-prompt-caching)。

### 缓存存储与共享

<Warning>
  Prompt Caching 使用 [workspace](https://platform.claude.com/docs/en/manage-claude/workspaces) 级隔离。缓存在每个 workspace 之间隔离，确保同一组织内各 workspace 之间的数据分离。这适用于 Claude API、Claude Platform on AWS 和 Microsoft Foundry；Bedrock 和 Google Cloud 保持组织级缓存隔离。如果你使用多个 workspace，请审视缓存策略以考虑这一差异。
</Warning>

* **组织和 workspace 隔离：** 缓存在组织之间隔离。不同组织永远不会共享缓存，即使它们使用相同的 prompt。在 Claude API、Claude Platform on AWS 和 Microsoft Foundry 上，缓存在组织内也按 workspace 隔离；Bedrock 和 Google Cloud 仅使用组织级隔离。

* **精确匹配：** 缓存命中要求 prompt 片段 100% 相同，包括直到并包括用 cache control 标记的块在内的所有文本和图像。

* **输出 token 生成：** Prompt Caching 对输出 token 生成没有影响。你收到的响应与未使用 Prompt Caching 时完全相同。

### 有效缓存的最佳实践

要优化 Prompt Caching 表现：

* 对于多轮对话，从[自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)开始。它会自动处理断点管理。
* 当你需要以不同变化频率缓存不同区段时，使用[显式块级断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)。
* 缓存稳定、可复用的内容，例如系统指令、背景信息、大型上下文或常用工具定义。
* 将缓存内容放在 prompt 开头以获得最佳表现。
* 有策略地使用缓存断点，以分隔不同的可缓存前缀区段。
* 将断点放在跨请求保持相同的最后一个块上。对于带有静态前缀和变化后缀（时间戳、每请求上下文、传入消息）的 prompt，那就是前缀的末尾，而不是变化的块。
* 定期分析缓存命中率并根据需要调整策略。

### 针对不同用例进行优化

根据你的场景调整 Prompt Caching 策略：

* 对话式 agent：降低长对话的成本和延迟，尤其是带有长指令或上传文档的对话。
* 编程助手：通过在 prompt 中保留相关区段或代码库的摘要版本，改善自动补全和代码库问答。
* 大型文档处理：在 prompt 中纳入包括图像在内的完整长篇材料，而不增加响应延迟。
* 详尽指令集：共享详尽的指令、流程和示例列表，以微调 Claude 的响应。开发者通常会在 prompt 中放一两个示例，但借助 Prompt Caching，你可以通过包含 20+ 个高质量答案的多样化示例获得更好的表现。
* 智能体工具使用：增强涉及多次工具调用和迭代代码更改的场景表现，其中每一步通常都需要一次新的 API 调用。
* 与书籍、论文、文档、播客转录稿及其他长篇内容对话：通过把整份文档嵌入 prompt，让用户向其提问，使任何知识库变得可用。

### 排查常见问题

如果遇到意外行为：

<Tip>
  [Cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics)（beta）让 API 比较连续请求并报告 prompt 前缀究竟在何处发生分歧，从而自动处理本列表中的许多步骤。
</Tip>

* 确保跨调用的缓存区段完全相同。对于显式缓存断点，验证 `cache_control` 标记位于相同位置
* 检查调用是在缓存生命周期内发出的（默认为 5 分钟）
* 验证 `tool_choice`、图像使用、thinking 配置和 `output_config.effort` 在调用之间保持一致
* 确认你至少缓存了所用模型和平台要求的最低 token 数（参见[缓存限制](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-limitations)）
* 确认断点位于跨请求保持相同的块上。缓存写入只发生在断点处，如果该块发生变化（时间戳、每请求上下文、传入消息），前缀哈希永远不会匹配。回看不会发现断点之前的稳定内容；它只查找更早请求在其自身断点处写入的条目
* 验证 `tool_use` 内容块中的键具有稳定顺序，因为某些语言（例如 Swift、Go）在 JSON 转换期间会随机化键顺序，从而破坏缓存
* 使用 [cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics) 让 API 比较连续请求并报告 prompt 的哪一部分发生了分歧

<Note>
  对 `tool_choice` 的更改，或 prompt 任意位置图像的存在/缺失，都会使缓存失效，需要创建新的缓存条目。关于缓存失效的更多详情，请参阅[什么会使缓存失效](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)。
</Note>

***

## 1 小时缓存时长

如果你觉得 5 分钟太短，Anthropic 还提供 1 小时缓存时长，[需额外付费](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#pricing)。

<Note>
  1 小时缓存时长在 Claude API、[Amazon Bedrock](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock)、[Amazon Bedrock (Opus 4.6 and earlier)](https://platform.claude.com/docs/en/build-with-claude/claude-on-amazon-bedrock-legacy)、[Claude Platform on AWS](https://platform.claude.com/docs/en/build-with-claude/claude-platform-on-aws)、[Google Cloud](https://platform.claude.com/docs/en/build-with-claude/claude-on-vertex-ai) 和 [Microsoft Foundry](https://platform.claude.com/docs/en/build-with-claude/claude-in-microsoft-foundry) 上可用。
</Note>

要使用延长缓存，请像这样在 `cache_control` 定义中包含 `ttl`：

```json
"cache_control": {
  "type": "ephemeral",
  "ttl": "1h"
}
```

响应包含如下详细缓存信息：

```json Output
{
  "usage": {
    "input_tokens": 2048,
    "cache_read_input_tokens": 1800,
    "cache_creation_input_tokens": 248,
    "output_tokens": 503,

    "cache_creation": {
      "ephemeral_5m_input_tokens": 148,
      "ephemeral_1h_input_tokens": 100
    }
  }
}
```

请注意，当前的 `cache_creation_input_tokens` 字段等于 `cache_creation` 对象中各值之和。

如果你在使用 web search 等 server tools 时看到并未请求的 `ephemeral_5m_input_tokens` 写入，请参阅 [Tool use with prompt caching](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching#server-tool-results-are-cached-automatically)。

### 何时使用 1 小时缓存

如果你有按固定节奏使用的 prompt（也就是使用频率高于每 5 分钟一次的 system prompts），请继续使用 5 分钟缓存，因为它会继续刷新且不产生额外费用。

1 小时缓存最适合以下场景：

* 当你的 prompt 使用频率可能低于每 5 分钟一次，但高于每小时一次。例如，某个 agentic side-agent 会花费超过 5 分钟，或者在存储与用户的长聊天对话时，你通常预期该用户可能不会在接下来 5 分钟内回复。
* 当延迟很重要，且后续 prompt 可能在 5 分钟之后才发送。
* 当你想改善速率限制利用率时，因为缓存命中不会从速率限制中扣减。

<Note>
  5 分钟缓存和 1 小时缓存在延迟方面表现相同。对于长文档，你通常会看到更好的首 token 时间（TTFT）。
</Note>

### 混合不同 TTL

你可以在同一请求中同时使用 1 小时和 5 分钟的 cache controls，但有一个重要约束：TTL 更长的缓存条目必须出现在更短 TTL 之前（也就是说，1 小时缓存条目必须出现在任何 5 分钟缓存条目之前）。

混合 TTL 时，API 会在你的 prompt 中确定三个计费位置：

1. 位置 `A`：最高缓存命中处的 token 数（若无命中则为 0）。
2. 位置 `B`：`A` 之后最高的 1 小时 `cache_control` 块处的 token 数（若不存在则等于 `A`）。
3. 位置 `C`：最后一个 `cache_control` 块处的 token 数。

<Note>
  如果 `B` 或 `C` 大于 `A`，则必然是缓存未命中，因为 `A` 是最高缓存命中。
</Note>

你将被收取：

1. `A` 的缓存读取 token。
2. `(B - A)` 的 1 小时缓存写入 token。
3. `(C - B)` 的 5 分钟缓存写入 token。

下面是三个示例。图中描绘了 3 个请求的输入 token，每个请求具有不同的缓存命中和缓存未命中。因此每个请求都有不同的计算定价，显示在彩色框中。 ![混合 TTL 示意图](https://platform.claude.com/docs/images/prompt-cache-mixed-ttl.svg)

***

## 预热缓存

缓存预热让你在用户触发真实请求之前，把 system prompt 或工具定义加载进 prompt 缓存。这消除了首次用户交互时的缓存未命中延迟惩罚，从而降低对延迟敏感的应用的首 token 时间（TTFT）。

### 工作原理

在请求中设置 `max_tokens: 0`。API 将你的 prompt 读入模型，并在任何 `cache_control` 断点处写入缓存，然后立即返回而不生成任何输出。响应包含空的 `content` 数组、`stop_reason: "max_tokens"`，以及完整填充的 `usage` 块。

将 `cache_control` 断点放在与后续请求共享的最后一个块上（通常是你的 system prompt 或工具定义），而不是放在占位用户消息上。否则缓存条目会以占位符为键，后续请求将无法命中它。也要使用与后续请求相同的 thinking 配置和 `output_config.effort`：这些值会被渲染进 prompt（参见[什么会使缓存失效](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)），因此使用不同配置的预热可能写入一条真实流量永远命中不到的条目。这意味着应使用[显式缓存断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)而不是[自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)，因为自动缓存会把断点放在最后一个块上，而这里最后一个块就是占位符。占位用户消息可以是任何含非空白内容的字符串（此处示例使用 `"warmup"`）；其内容会被读入模型但永远不会被回答。

<Note>
  如果前缀尚未被缓存，预热请求会产生**缓存写入**费用，与任何其他请求相同。检查响应中的 `usage.cache_creation_input_tokens` 以确认发生了写入。输出 token 按零计费。
</Note>

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  # Fire this before users arrive to warm the shared system-prompt cache.
  prewarm = client.messages.create(
      model="claude-opus-5",
      max_tokens=0,
      system=[
          {
              "type": "text",
              "text": "You are an expert software engineer with deep knowledge of distributed systems...",
              "cache_control": {"type": "ephemeral"},
          }
      ],
      messages=[{"role": "user", "content": "warmup"}],
  )
  print(prewarm.stop_reason)  # "max_tokens"
  print(prewarm.content)  # []
  print(prewarm.usage)
  ```

</CodeGroup>

API 返回空的 `content` 数组：

```json Output
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [],
  "model": "claude-opus-5",
  "stop_reason": "max_tokens",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 8,
    "cache_creation_input_tokens": 5120,
    "cache_read_input_tokens": 0,
    "cache_creation": {
      "ephemeral_5m_input_tokens": 5120,
      "ephemeral_1h_input_tokens": 0
    },
    "iterations": [
      {
        "input_tokens": 8,
        "output_tokens": 0,
        "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 5120,
        "cache_creation": {
          "ephemeral_5m_input_tokens": 5120,
          "ephemeral_1h_input_tokens": 0
        },
        "type": "message"
      }
    ],
    "output_tokens": 0,
    "service_tier": "standard",
    "inference_geo": "global"
  }
}
```

### 典型用法模式

在应用启动时（或按计划间隔）发出一次预热请求，然后在预热完成后发送真实用户请求：

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  SYSTEM_PROMPT = [
      {
          "type": "text",
          "text": "You are an expert software engineer with deep knowledge of distributed systems...",
          "cache_control": {"type": "ephemeral"},
      }
  ]


  def prewarm_cache() -> None:
      """Call this at application startup or on a scheduled interval."""
      client.messages.create(
          model="claude-opus-5",
          max_tokens=0,
          system=SYSTEM_PROMPT,
          messages=[{"role": "user", "content": "warmup"}],
      )


  def respond(user_message: str) -> anthropic.types.Message:
      """The real user request; benefits from a warm cache."""
      return client.messages.create(
          model="claude-opus-5",
          max_tokens=1024,
          system=SYSTEM_PROMPT,
          messages=[{"role": "user", "content": user_message}],
      )


  # Warm the cache before any user traffic arrives.
  prewarm_cache()

  # Later, when the user submits a message, the system-prompt prefix is already cached.
  response = respond("How do I implement a binary search tree?")
  for block in response.content:
      if block.type == "text":
          print(block.text)
  ```

</CodeGroup>

请记住缓存 TTL 仍然适用。对于默认的 5 分钟缓存，至少每 5 分钟发送一次新的预热请求以保持缓存温热。如果用户请求之间的间隔更长，请改用 [1 小时缓存时长](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)。

### 限制

如果设置了以下任何一项，`max_tokens: 0` 请求会被拒绝并返回 `invalid_request_error`，因为每一项都意味着需要零 token 预算无法产生的输出：

* `stream: true`
* [Extended thinking](https://platform.claude.com/docs/en/build-with-claude/extended-thinking)（`thinking.type: "enabled"`）
* [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)（`output_config.format`）
* `tool_choice` 为 `{"type": "tool", ...}` 或 `{"type": "any"}`

`max_tokens: 0` 在 [Message Batches](https://platform.claude.com/docs/en/build-with-claude/batch-processing) 请求中也会被拒绝。预热针对的是首 token 时间（TTFT），这不适用于批处理，而且在批处理期间写入的缓存条目很可能在后续请求运行之前就已过期。

### 替代 max\_tokens=1 变通方法

在 `max_tokens: 0` 可用之前，一些应用使用 `max_tokens: 1` 预热调用以达到同样效果。更推荐 `max_tokens: 0` 方式：不产生任何输出，因此没有需要丢弃的单 token 回复，不产生输出 token 费用，并且请求意图明确。

***

## Prompt Caching 示例

为帮助你开始使用 Prompt Caching，[prompt caching cookbook](https://platform.claude.com/cookbook/misc-prompt-caching) 提供了详细示例和最佳实践。

以下代码片段展示了各种 Prompt Caching 模式。这些示例演示如何在不同场景中实现缓存，帮助你理解该功能的实际应用：

<AccordionGroup>
  <Accordion title="大型上下文缓存示例">
    <CodeGroup>

      ```python Python
      client = anthropic.Anthropic()
    
      response = client.messages.create(
          model="claude-opus-5",
          max_tokens=1024,
          system=[
              {
                  "type": "text",
                  "text": "You are an AI assistant tasked with analyzing legal documents.",
              },
              {
                  "type": "text",
                  "text": "Here is the full text of a complex legal agreement: [Insert full text of a 50-page legal agreement here]",
                  "cache_control": {"type": "ephemeral"},
              },
          ],
          messages=[
              {
                  "role": "user",
                  "content": "What are the key terms and conditions in this agreement?",
              }
          ],
      )
      print(response.usage.model_dump_json())
      ```
    
    </CodeGroup>
    
    本示例演示基本的 Prompt Caching 用法：将法律协议全文作为前缀缓存，同时保持用户指令不缓存。
    
    对于第一次请求：
    
    * `input_tokens`：仅用户消息中的 token 数
    * `cache_creation_input_tokens`：整个 system message 中的 token 数，包括法律文档
    * `cache_read_input_tokens`: 0（第一次请求没有缓存命中）
    
    对于缓存生命周期内的后续请求：
    
    * `input_tokens`：仅用户消息中的 token 数
    * `cache_creation_input_tokens`: 0（没有新的缓存创建）
    * `cache_read_input_tokens`：整个已缓存 system message 中的 token 数
  </Accordion>

  <Accordion title="缓存工具定义">
    可以通过在 `tools` 数组的最后一个工具上放置 `cache_control` 来缓存工具定义。在该工具之前（含该工具）定义的所有工具会作为一个前缀被缓存。

    ```json
    {
      "model": "claude-opus-5",
      "max_tokens": 1024,
      "tools": [
        {
          "name": "get_weather",
          "description": "Get the current weather in a given location",
          "input_schema": {
            "type": "object",
            "properties": { "location": { "type": "string" } },
            "required": ["location"]
          }
        },
        {
          "name": "get_time",
          "description": "Get the current time in a given time zone",
          "input_schema": {
            "type": "object",
            "properties": { "timezone": { "type": "string" } },
            "required": ["timezone"]
          },
          "cache_control": { "type": "ephemeral" }
        }
      ],
      "messages": [{ "role": "user", "content": "What is the weather and time in New York?" }]
    }
    ```
    
    在第一次请求中，`cache_creation_input_tokens` 反映所有工具定义的 token 数。在缓存生命周期内的后续请求中，这些 token 会出现在 `cache_read_input_tokens` 下。
    
    关于工具定义、`defer_loading` 和缓存失效之间的详细交互，请参阅 [Tool use with prompt caching](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching)。
  </Accordion>

  <Accordion title="继续多轮对话">
    <CodeGroup>

      ```python Python
      client = anthropic.Anthropic()
    
      response = client.messages.create(
          model="claude-opus-5",
          max_tokens=1024,
          system=[
              {
                  "type": "text",
                  "text": "...long system prompt",
                  "cache_control": {"type": "ephemeral"},
              }
          ],
          messages=[
              # ...long conversation so far
              {
                  "role": "user",
                  "content": [
                      {
                          "type": "text",
                          "text": "Hello, can you tell me more about the solar system?",
                      }
                  ],
              },
              {
                  "role": "assistant",
                  "content": "Certainly! The solar system is the collection of celestial bodies that orbit our Sun. It consists of eight planets, numerous moons, asteroids, comets, and other objects. The planets, in order from closest to farthest from the Sun, are: Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, and Neptune. Each planet has its own unique characteristics and features. Is there a specific aspect of the solar system you'd like to know more about?",
              },
              {
                  "role": "user",
                  "content": [
                      {"type": "text", "text": "Good to know."},
                      {
                          "type": "text",
                          "text": "Tell me more about Mars.",
                          "cache_control": {"type": "ephemeral"},
                      },
                  ],
              },
          ],
      )
      print(response.usage.model_dump_json())
      ```
    
    </CodeGroup>
    
    本示例演示如何在多轮对话中使用 Prompt Caching。
    
    在每一轮中，最后一条消息的最后一个块会标上 `cache_control`，以便对话可以被增量缓存。系统会自动查找并使用先前已缓存的最长块序列来处理后续消息。也就是说，先前用 `cache_control` 标记过的块之后不再带此标记，但如果在 5 分钟内被命中，它们仍会被视为缓存命中（同时也是一次缓存刷新！）。
    
    此外，请注意 `cache_control` 参数放在了 system message 上。这是为了确保如果它从缓存中被驱逐（超过 5 分钟未被使用之后），会在下一次请求时被重新加入缓存。
    
    这种方法适用于在进行中的对话里维持上下文，而无需反复处理相同信息。
    
    正确设置后，你应在每个请求的 usage 响应中看到以下内容：
    
    * `input_tokens`：新用户消息中的 token 数（会很少）
    * `cache_creation_input_tokens`：新的 assistant 和 user 轮中的 token 数
    * `cache_read_input_tokens`：直到上一轮为止的对话中的 token 数
  </Accordion>

  <Accordion title="综合运用：多个缓存断点">
    <CodeGroup>

      ```python Python
      client = anthropic.Anthropic()
    
      response = client.messages.create(
          model="claude-opus-5",
          max_tokens=1024,
          tools=[
              {
                  "name": "search_documents",
                  "description": "Search through the knowledge base",
                  "input_schema": {
                      "type": "object",
                      "properties": {
                          "query": {"type": "string", "description": "Search query"}
                      },
                      "required": ["query"],
                  },
              },
              {
                  "name": "get_document",
                  "description": "Retrieve a specific document by ID",
                  "input_schema": {
                      "type": "object",
                      "properties": {
                          "doc_id": {"type": "string", "description": "Document ID"}
                      },
                      "required": ["doc_id"],
                  },
                  "cache_control": {"type": "ephemeral"},
              },
          ],
          system=[
              {
                  "type": "text",
                  "text": "You are a helpful research assistant with access to a document knowledge base.\n\n# Instructions\n- Always search for relevant documents before answering\n- Provide citations for your sources\n- Be objective and accurate in your responses\n- If multiple documents contain relevant information, synthesize them\n- Acknowledge when information is not available in the knowledge base",
                  "cache_control": {"type": "ephemeral"},
              },
              {
                  "type": "text",
                  "text": "# Knowledge Base Context\n\nHere are the relevant documents for this conversation:\n\n## Document 1: Solar System Overview\nThe solar system consists of the Sun and all objects that orbit it...\n\n## Document 2: Planetary Characteristics\nEach planet has unique features. Mercury is the smallest planet...\n\n## Document 3: Mars Exploration\nMars has been a target of exploration for decades...\n\n[Additional documents...]",
                  "cache_control": {"type": "ephemeral"},
              },
          ],
          messages=[
              {
                  "role": "user",
                  "content": "Can you search for information about Mars rovers?",
              },
              {
                  "role": "assistant",
                  "content": [
                      {
                          "type": "tool_use",
                          "id": "tool_1",
                          "name": "search_documents",
                          "input": {"query": "Mars rovers"},
                      }
                  ],
              },
              {
                  "role": "user",
                  "content": [
                      {
                          "type": "tool_result",
                          "tool_use_id": "tool_1",
                          "content": "Found 3 relevant documents: Document 3 (Mars Exploration), Document 7 (Rover Technology), Document 9 (Mission History)",
                      }
                  ],
              },
              {
                  "role": "assistant",
                  "content": [
                      {
                          "type": "text",
                          "text": "I found 3 relevant documents about Mars rovers. Let me get more details from the Mars Exploration document.",
                      }
                  ],
              },
              {
                  "role": "user",
                  "content": [
                      {
                          "type": "text",
                          "text": "Yes, please tell me about the Perseverance rover specifically.",
                          "cache_control": {"type": "ephemeral"},
                      }
                  ],
              },
          ],
      )
      print(response.usage.model_dump_json())
      ```
    
    </CodeGroup>
    
    这个综合示例演示如何使用全部 4 个可用缓存断点来优化 prompt 的不同部分：
    
    1. **工具缓存**（缓存断点 1）：最后一个工具定义上的 `cache_control` 参数会缓存所有工具定义。
    
    2. **可复用指令缓存**（缓存断点 2）：system prompt 中的静态指令被单独缓存。这些指令在请求之间很少变化。
    
    3. **RAG 上下文缓存**（缓存断点 3）：知识库文档被独立缓存，让你可以更新 RAG 文档而不使 tools 或 instructions 缓存失效。
    
    4. **对话历史缓存**（缓存断点 4）：最后一条用户消息标有 `cache_control`，以便随对话推进进行增量缓存。
    
    这种方法提供最大灵活性：
    
    * 如果你向对话追加新一轮且不更改更早的内容，全部四个缓存区段都会被复用
    * 如果你更新 RAG 文档但保持相同的 tools 和 instructions，前两个缓存区段会被复用
    * 如果你更改对话但保持相同的 tools、instructions 和 documents，前三个区段会被复用
    * 任何断点处的变更会使该区段及其之后的一切失效，而更早的已缓存区段仍然有效
    
    对于第一次请求：
    
    * `input_tokens`：很少（最后一个缓存断点之后的 token，本示例中接近 0）
    * `cache_creation_input_tokens`：所有被缓存区段中的 token（tools + instructions + RAG documents + conversation history）
    * `cache_read_input_tokens`: 0（没有缓存命中）
    
    对于仅带有新用户消息的后续请求（并且第四个断点移到该新的最后一条消息上，如示例所示）：
    
    * `input_tokens`：很少（最后一个缓存断点之后的 token，本示例中接近 0）
    * `cache_creation_input_tokens`：新用户消息和上一轮 assistant 中的 token（正在被缓存的新对话区段）
    * `cache_read_input_tokens`：所有先前已缓存的 token（tools + instructions + RAG documents + previous conversation）
    
    这种模式尤其适用于：
    
    * 带有大型文档上下文的 RAG 应用
    * 使用多种工具的 Agent 系统
    * 需要维持上下文的长时间运行对话
    * 需要独立优化 prompt 不同部分的应用
  </Accordion>
</AccordionGroup>

## 数据保留

Prompt Caching（自动缓存和显式缓存断点）符合 ZDR 资格。Anthropic 不会存储你的 prompt 原文或 Claude 的响应。

KV（key-value）缓存表示以及已缓存内容的加密哈希仅保存在内存中，不会持久化存储。缓存条目的最短生命周期为 5 分钟（标准）或 1 小时（延长），之后会及时（尽管不是立即）删除。缓存条目在组织之间隔离；在 Claude API、Claude Platform on AWS 和 Microsoft Foundry 上，还在组织内的 workspace 之间隔离。

关于所有功能的 ZDR 资格，请参阅 [API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)。

***

## FAQ

<AccordionGroup>
  <Accordion title="我需要多个缓存断点，还是末尾一个就足够？">
    **在大多数情况下，静态内容末尾的单个缓存断点就足够了。** 缓存写入只发生在你标记的块上。把它放在跨请求保持相同的最后一个块上，之后每个后续请求都会读取同一条条目。如果后面的块每次请求都会变化（时间戳、传入消息），把断点保持在它之前，即最后一个稳定块上。

    你只在以下情况下需要多个断点：
    
    * 增长中的对话把你的断点推到距上次缓存写入 20 个或更多块，使先前条目落在回看窗口之外
    * 你希望独立缓存以不同频率更新的区段
    * 你需要显式控制缓存内容以便优化成本
    
    示例：如果你有系统指令（很少变化）和 RAG 上下文（每天变化），你可能会使用两个断点分别缓存它们。
  </Accordion>

  <Accordion title="缓存断点会增加额外成本吗？">
    不会，缓存断点本身是免费的。你只需为以下项付费：

    * 将内容写入缓存（5 分钟 TTL 比基础输入 token 贵 25%）
    * 从缓存读取（基础输入 token 价格的一小部分，参见[定价](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#pricing)）
    * 未缓存内容的常规输入 token
    
    断点数量不影响定价——只有实际被缓存和读取的内容量才重要。
  </Accordion>

  <Accordion title="如何从 usage 字段计算总输入 token？">
    usage 响应包含三个独立的输入 token 字段，它们合在一起表示你的总输入：

    ```text wrap
    total_input_tokens = cache_read_input_tokens + cache_creation_input_tokens + input_tokens
    ```
    
    * `cache_read_input_tokens`：从缓存检索的 token（缓存断点之前已缓存的一切）
    * `cache_creation_input_tokens`：正在写入缓存的新 token（在缓存断点处）
    * `input_tokens`：**最后一个缓存断点之后**未被缓存的 token
    
    **重要：** `input_tokens` 并不代表全部输入 token——只代表最后一个缓存断点之后的部分。如果有已缓存内容，`input_tokens` 通常会远小于你的总输入。
    
    **示例：** 一份 200k token 的文档已缓存，加上 50 token 的用户问题：
    
    * `cache_read_input_tokens`: 200,000
    * `cache_creation_input_tokens`: 0
    * `input_tokens`: 50
    * **总计：** 200,050 tokens
    
    这一分解对于理解成本和速率限制用量都至关重要。更多详情请参阅[跟踪缓存表现](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#tracking-cache-performance)。
  </Accordion>

  <Accordion title="缓存生命周期是多久？">
    缓存的默认最短生命周期（TTL）为 5 分钟。每次使用缓存内容时，该生命周期都会刷新。

    如果你觉得 5 分钟太短，Anthropic 还提供 [1 小时缓存 TTL](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)。
  </Accordion>

  <Accordion title="缓存生命周期从何时开始？">
    生命周期从写入或读取该缓存条目的请求开始时刻起算，而非从其响应结束时刻起算。生成响应所花费的时间会计入生命周期，因此后续请求复用缓存的窗口是生命周期减去生成时间。

    如果你的请求会产生很长的响应，且下一次请求可能在生命周期结束之后才开始，请使用 [1 小时缓存 TTL](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)。
  </Accordion>

  <Accordion title="我可以使用多少个缓存断点？">
    你可以在 prompt 中定义最多 4 个缓存断点（使用 `cache_control` 参数）。
  </Accordion>

  <Accordion title="Prompt Caching 是否适用于所有模型？">
    Prompt Caching 在所有[当前可用的 Claude 模型](https://platform.claude.com/docs/en/models/overview)上均受支持。
  </Accordion>

  <Accordion title="Prompt Caching 与 thinking 如何配合？">
    更改 thinking 参数（切换模式，或更改 extended mode 中的 budget）会使已缓存的 message 前缀失效，也可能使已缓存的 system prompts 和 tools 失效，因为 thinking 配置会被渲染进 prompt。[`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort) 值的行为相同。

    关于缓存失效的更多详情，请参阅[什么会使缓存失效](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)。
    
    关于 thinking 的更多信息，包括它与 tool use 和 Prompt Caching 的交互，请参阅 [Thinking and prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-prompt-caching)。
  </Accordion>

  <Accordion title="如何启用 Prompt Caching？">
    最简单的方式是在请求体顶层添加 `"cache_control": {"type": "ephemeral"}`（[自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)）。或者，在各个内容块上至少包含一个 `cache_control` 断点（[显式缓存断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)）。
  </Accordion>

  <Accordion title="我可以将 Prompt Caching 与其他 API 功能一起使用吗？">
    可以，Prompt Caching 可以与 tool use 和视觉能力等其他 API 功能一起使用。但是，更改 prompt 中是否包含图像或修改 tool use 设置会使缓存失效。

    关于缓存失效的更多详情，请参阅[什么会使缓存失效](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)。
  </Accordion>

  <Accordion title="Prompt Caching 如何影响定价？">
    Prompt Caching 引入了新的定价结构：5 分钟缓存写入比基础输入 token 贵 25%，1 小时缓存写入为基础输入 token 的 2 倍，缓存命中为基础输入 token 价格的一小部分（各模型乘数见[定价](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#pricing)）。
  </Accordion>

  <Accordion title="我可以手动清除缓存吗？">
    目前无法手动清除缓存。已缓存前缀在至少 5 分钟不活动后自动过期。
  </Accordion>

  <Accordion title="如何跟踪缓存策略的有效性？">
    你可以使用 API 响应中的 `cache_creation_input_tokens` 和 `cache_read_input_tokens` 字段监控缓存表现。
  </Accordion>

  <Accordion title="什么会破坏缓存？">
    关于缓存失效的更多详情，包括需要创建新缓存条目的变更列表，请参阅[什么会使缓存失效](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)。
  </Accordion>

  <Accordion title="Prompt Caching 如何处理隐私和数据隔离？">
    Prompt Caching 在设计上采用了严格的隐私和数据隔离措施：

    1. 缓存键使用直到 cache control 点为止的 prompt 的加密哈希生成。这意味着只有具有相同 prompt 的请求才能访问特定缓存。
    
    2. 在 Claude API、Claude Platform on AWS 和 Microsoft Foundry 上，缓存在组织内按 workspace 隔离。在 Bedrock 和 Google Cloud 上，缓存在组织级隔离。在任何情况下，缓存都不会跨组织共享，即使 prompt 相同。详情见[缓存存储与共享](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-storage-and-sharing)。
    
    3. 缓存机制旨在维护每个独特对话或上下文的完整性和隐私。
    
    4. 在 prompt 的任何位置使用 `cache_control` 都是安全的。要让缓存产生读取，把断点放在稳定前缀的末尾：把它放在每次请求都会变化的块上（例如时间戳或用户的任意输入）会每次写入一条新条目，并且永远不会命中。
    
    这些措施确保 Prompt Caching 在提供性能收益的同时维护数据隐私和安全。
  </Accordion>

  <Accordion title="我可以将 Prompt Caching 与 Batches API 一起使用吗？">
    可以，你可以在 [Batches API](https://platform.claude.com/docs/en/build-with-claude/batch-processing) 请求中使用 Prompt Caching。但是，由于异步批处理请求可以并发并以任意顺序处理，缓存命中按尽力而为提供。

    [1 小时缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)可以帮助提高缓存命中。使用它的最经济方式如下：
    
    * 收集一组具有共享前缀的 message 请求。
    * 发送一个批处理请求，其中包含单个带有该共享前缀和 1 小时缓存块的请求。这会将该前缀写入 1 小时缓存。
    * 一旦完成，提交其余请求。你需要监控该作业以知道它何时完成。
    
    这通常优于使用 5 分钟缓存，因为批处理请求通常需要 5 分钟到 1 小时才能完成。
  </Accordion>

  <Accordion title="为什么我在 Python 中看到错误 `AttributeError: 'Beta' object has no attribute 'prompt_caching'`？">
    此错误通常出现在你已升级 SDK 或正在使用过时代码示例时。Prompt Caching 不再需要 beta 前缀。不要使用：

    <CodeGroup>
      ```python Python
      client.beta.prompt_caching.messages.create(**params)
      ```
    </CodeGroup>
    
    而应使用：
    
    <CodeGroup>
      ```python Python
      client.messages.create(**params)
      ```
    </CodeGroup>
  </Accordion>

  <Accordion title="为什么我会看到 'TypeError: Cannot read properties of undefined (reading 'messages')'？">
    此错误通常出现在你已升级 SDK 或正在使用过时代码示例时。Prompt Caching 不再需要 beta 前缀。不要使用：

    直接使用：

  </Accordion>
</AccordionGroup>