+++
title = "上下文编辑"
slug = "context-editing"
weight = 70
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "随着对话增长，通过上下文编辑自动管理对话上下文。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/context-editing"
+++

<Note>
  要了解零数据保留（ZDR）如何适用于此功能，请参阅 [API 与数据保留](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)。
</Note>

## 概述

<Note>
  对于大多数用例，[服务端压缩（server-side compaction）](https://platform.claude.com/docs/en/build-with-claude/compaction) 是管理长对话上下文的主要策略。本页中的策略适用于需要更精细控制清除哪些内容的特定场景。
</Note>

上下文编辑（context editing）允许你在对话历史增长时有选择地清除特定内容。这不仅是为了优化成本并保持在限制之内，更是为了主动筛选 Claude 所见的内容：上下文是一种收益递减的有限资源，无关内容会降低模型的专注度。上下文编辑让你在运行时对这些筛选进行精细控制。有关上下文管理背后的更广泛原则，请参阅 [有效的上下文工程](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)。本页涵盖：

* **工具结果清除** - 最适合大量使用工具、旧工具结果不再需要的智能体工作流
* **thinking block 清除** - 用于在使用 extended thinking 时管理 thinking block，可选择保留近期 thinking 以维持上下文连续性
* **客户端 SDK 压缩** - 一种基于 SDK 的摘要式上下文管理替代方案（通常更推荐服务端压缩）

| 方法        | 运行位置 | 策略                                                   | 工作原理                                                 |
| --------------- | ------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **服务端** | API           | 工具结果清除（`clear_tool_uses_20250919`） thinking block 清除（`clear_thinking_20251015`） | 在 prompt 到达 Claude 之前应用。从对话历史中清除特定内容。每种策略可独立配置。 |
| **客户端** | SDK           | 压缩                                                   | 在使用 [`tool_runner`](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-runner) 时，[TypeScript 和 Ruby SDK](https://platform.claude.com/docs/en/cli-sdks-libraries/overview) 中可用。生成摘要并替换完整对话历史。参见 [客户端压缩](https://platform.claude.com/docs/en/build-with-claude/context-editing#client-side-compaction-sdk)。 |

## 服务端策略

<Note>
  上下文编辑目前处于 beta，支持工具结果清除和 thinking block 清除。要启用它，请在 API 请求中使用 beta 标头 `context-management-2025-06-27`。

  通过 [反馈表单](https://forms.gle/YXC2EKGMhjN1c4L88) 分享对此功能的反馈。
</Note>

### 工具结果清除

`clear_tool_uses_20250919` 策略会在对话上下文增长超过你配置的阈值时清除工具结果。这尤其适用于大量使用工具的智能体工作流。较旧的工具结果（如文件内容或搜索结果）在 Claude 处理完后便不再需要。

激活后，API 会按时间顺序自动清除最旧的工具结果。API 会将每个被清除的结果替换为占位文本，向 Claude 表明该结果已被移除。默认情况下，仅清除工具结果。你可以通过将 `clear_tool_inputs` 设为 true，选择同时清除工具结果和工具调用（工具使用参数）。

### thinking block 清除

`clear_thinking_20251015` 策略在启用 extended thinking 时管理对话中的 `thinking` block。该策略让你控制 thinking 的保留：你可以选择保留更多 thinking block 以维持推理连续性，或更积极地清除它们以节省上下文空间。

<Tip>
  **默认行为：** 默认值因模型类别而异。

| 模型类别      | 保留所有先前 thinking     | 仅保留上一轮的 thinking  |
| ---------------- | --------------------------- | ----------------------------------- |
| Opus             | Claude Opus 4.5 及更高版本   | Claude Opus 4.1 及更早版本         |
| Sonnet           | Claude Sonnet 4.6 及更高版本 | Claude Sonnet 4.5 及更早版本       |
| Haiku            | （无）                      | 直至 Claude Haiku 4.5 的所有模型 |
| Fable 和 Mythos | 所有模型                  | （无）                              |

  使用此策略可覆盖默认值。如果你的代码会跨多个模型层级运行，请显式设置 `keep`，而不是依赖各模型的默认值。
</Tip>

一个 assistant 对话轮次可能包含多个内容块（例如在使用工具时）以及多个 thinking block（例如使用 [interleaved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#interleaved-thinking) 时）。

### 上下文编辑发生在服务端

上下文编辑在 prompt 到达 Claude 之前于服务端应用。你的客户端应用保持完整、未修改的对话历史。你无需将客户端状态与编辑后的版本同步。继续像往常一样在本地管理完整的对话历史。

在 Claude Fable 5.1 上，服务端上下文管理从不使 thinking block 失效。对更早轮次的客户端编辑会使之后每个 assistant 轮次中的 thinking block 失效。对于 2026 年 8 月 31 日或之后创建的新账户，重放已失效 block 的请求会被拒绝，除非你选择丢弃它。参见 [保持前缀不变](https://platform.claude.com/docs/en/build-with-claude/preserved-thinking#prefix-check)。

### 上下文编辑与 Prompt Caching

上下文编辑与 [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 的交互因策略而异：

* **工具结果清除：** 在内容被清除时会使已缓存的 prompt 前缀失效。为此，应清除足够多的 token，使缓存失效物有所值。使用 `clear_at_least` 参数确保每次至少清除最低数量的 token。每次内容被清除时你会产生缓存写入费用，但后续请求可以复用新缓存的前缀。

* **thinking block 清除：** 当 thinking block **被保留**在上下文中（未被清除）时，prompt 缓存得以保留，从而能够命中缓存并降低输入 token 成本。当 thinking block **被清除**时，缓存会在清除发生处失效。根据你是优先考虑缓存性能还是上下文窗口可用性，配置 `keep` 参数。

## 支持的模型

上下文编辑适用于所有受支持的 Claude 模型。

## 工具结果清除用法

启用工具结果清除的最简单方式是仅指定策略类型。所有其他 [配置选项](https://platform.claude.com/docs/en/build-with-claude/context-editing#configuration-options-for-tool-result-clearing) 使用其默认值：

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=4096,
      messages=[{"role": "user", "content": "Search for recent developments in AI"}],
      tools=[{"type": "web_search_20250305", "name": "web_search"}],
      betas=["context-management-2025-06-27"],
      context_management={"edits": [{"type": "clear_tool_uses_20250919"}]},
  )
  ```

</CodeGroup>

### 高级配置

你可以使用其他参数自定义工具结果清除行为：

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=4096,
      messages=[
          {
              "role": "user",
              "content": "Create a simple command line calculator app using Python",
          }
      ],
      tools=[
          {
              "type": "text_editor_20250728",
              "name": "str_replace_based_edit_tool",
              "max_characters": 10000,
          },
          {"type": "web_search_20250305", "name": "web_search", "max_uses": 3},
      ],
      betas=["context-management-2025-06-27"],
      context_management={
          "edits": [
              {
                  "type": "clear_tool_uses_20250919",
                  # Trigger clearing when threshold is exceeded
                  "trigger": {"type": "input_tokens", "value": 30000},
                  # Number of tool uses to keep after clearing
                  "keep": {"type": "tool_uses", "value": 3},
                  # Optional: Clear at least this many tokens
                  "clear_at_least": {"type": "input_tokens", "value": 5000},
                  # Exclude these tools from being cleared
                  "exclude_tools": ["web_search"],
              }
          ]
      },
  )
  ```

</CodeGroup>

## thinking block 清除用法

启用 thinking block 清除，以便在启用 extended thinking 时有效管理上下文和 Prompt Caching：

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=16000,
      messages=[{"role": "user", "content": "Hello"}],
      betas=["context-management-2025-06-27"],
      context_management={
          "edits": [
              {
                  "type": "clear_thinking_20251015",
                  "keep": {"type": "thinking_turns", "value": 2},
              }
          ]
      },
  )
  ```

</CodeGroup>

### thinking block 清除的配置选项

`clear_thinking_20251015` 策略支持以下配置：

| 配置选项 | 默认值        | 说明                                                  |
| -------------------- | -------------- | ------------------------------------------------------------ |
| `keep`               | 因模型而异 | 定义要保留多少个包含 thinking block 的近期 assistant 轮次。使用 `{type: "thinking_turns", value: N}`（N 必须 > 0）以保留最近 N 轮，或使用 `"all"` 以保留所有 thinking block。Opus 4.5+ 和 Sonnet 4.6+：所有轮次。Fable 和 Mythos 模型：所有轮次。更早的 Opus/Sonnet 以及所有 Haiku：仅上一轮。 |

**配置示例：**

保留最近 3 个 assistant 轮次的 thinking block：

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=16000,
      messages=[{"role": "user", "content": "Hello"}],
      betas=["context-management-2025-06-27"],
      context_management={
          "edits": [
              {
                  "type": "clear_thinking_20251015",
                  "keep": {"type": "thinking_turns", "value": 3},
              }
          ]
      },
  )
  ```

</CodeGroup>

保留所有 thinking block（最大化缓存命中）：

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=16000,
      messages=[{"role": "user", "content": "Hello"}],
      betas=["context-management-2025-06-27"],
      context_management={
          "edits": [
              {
                  "type": "clear_thinking_20251015",
                  "keep": "all",
              }
          ]
      },
  )
  ```

</CodeGroup>

### 组合策略

你可以同时使用 thinking block 清除和工具结果清除：

<Note>
  使用多种策略时，`clear_thinking_20251015` 策略必须列在 `edits` 数组的第一位。
</Note>

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=16000,
      messages=[
          {
              "role": "user",
              "content": "Search for the latest developments in quantum error correction and summarize the key breakthroughs.",
          }
      ],
      tools=[
          {
              "type": "web_search_20250305",
              "name": "web_search",
              "max_uses": 5,
          }
      ],
      betas=["context-management-2025-06-27"],
      context_management={
          "edits": [
              {
                  "type": "clear_thinking_20251015",
                  "keep": {"type": "thinking_turns", "value": 2},
              },
              {
                  "type": "clear_tool_uses_20250919",
                  "trigger": {"type": "input_tokens", "value": 50000},
                  "keep": {"type": "tool_uses", "value": 5},
              },
          ]
      },
  )

  print(response)
  ```

</CodeGroup>

## 工具结果清除的配置选项

| 配置选项 | 默认值              | 说明                                                  |
| -------------------- | -------------------- | ------------------------------------------------------------ |
| `trigger`            | 100,000 输入 token | 定义上下文编辑策略何时激活。一旦 prompt 超过此阈值，便开始清除。你可以用 `input_tokens` 或 `tool_uses` 指定此值。 |
| `keep`               | 3 次工具使用          | 定义清除发生后保留多少对近期的工具使用/结果。API 先移除最旧的工具交互，保留最近的交互。 |
| `clear_at_least`     | 无                 | 确保每次策略激活时至少清除指定数量的 token。如果 API 无法至少清除指定数量，则不会应用该策略。这有助于判断上下文清除是否值得打断你的 prompt 缓存。 |
| `exclude_tools`      | 无                 | 其工具使用和结果永远不应被清除的工具名称列表。适用于保留重要上下文。 |
| `clear_tool_inputs`  | `false`              | 控制是否连同工具结果一起清除工具调用参数。默认情况下，仅清除工具结果，同时保持 Claude 原始的工具调用可见。 |

## 上下文编辑响应

你可以使用 `context_management` 响应字段查看哪些上下文编辑已应用于你的请求，以及有关已清除内容和输入 token 的有用统计信息。

```json Output
{
  "id": "msg_013Zva2CMHLNnXjNJJKqJ2EF",
  "type": "message",
  "role": "assistant",
  "content": [
    // ...
  ],
  "usage": {
    // ...
  },
  "context_management": {
    "applied_edits": [
      // When using `clear_thinking_20251015`
      {
        "type": "clear_thinking_20251015",
        "cleared_thinking_turns": 3,
        "cleared_input_tokens": 15000
      },
      // When using `clear_tool_uses_20250919`
      {
        "type": "clear_tool_uses_20250919",
        "cleared_tool_uses": 8,
        "cleared_input_tokens": 50000
      }
    ]
  }
}
```

对于流式响应，上下文编辑包含在最终的 `message_delta` 事件中：

```json Streaming Response
{
  "type": "message_delta",
  "delta": {
    "stop_reason": "end_turn",
    "stop_sequence": null
  },
  "usage": {
    "output_tokens": 1024
  },
  "context_management": {
    "applied_edits": [
      // ...
    ]
  }
}
```

## Token 计数

[Token 计数](https://platform.claude.com/docs/en/build-with-claude/token-counting) 端点支持上下文管理，让你可以预览在应用上下文编辑后 prompt 将使用多少 token。

<CodeGroup>

  ```python Python
  response = client.beta.messages.count_tokens(
      model="claude-opus-5",
      messages=[{"role": "user", "content": "Continue our conversation..."}],
      betas=["context-management-2025-06-27"],
      context_management={
          "edits": [
              {
                  "type": "clear_tool_uses_20250919",
                  "trigger": {"type": "input_tokens", "value": 30000},
                  "keep": {"type": "tool_uses", "value": 5},
              }
          ]
      },
  )

  print(f"Original tokens: {response.context_management.original_input_tokens}")
  print(f"After clearing: {response.input_tokens}")
  print(
      f"Savings: {response.context_management.original_input_tokens - response.input_tokens} tokens"
  )
  ```

</CodeGroup>

```json Output
{
  "input_tokens": 25000,
  "context_management": {
    "original_input_tokens": 70000
  }
}
```

响应同时显示应用上下文管理后的最终 token 数（`input_tokens`）以及清除发生前的原始 token 数（`original_input_tokens`）。

## 与 memory tool 一起使用

上下文编辑可以与 [memory tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool) 结合使用。当对话上下文接近配置的清除阈值时，Claude 会收到自动警告以保留重要信息。这使 Claude 能够在工具结果或上下文从对话历史中被清除之前，将其保存到 memory 文件中。

这种组合让你可以：

* **保留重要上下文：** Claude 可以在工具结果被清除之前，将其中的必要信息写入 memory 文件
* **维持长时间运行的工作流：** 通过将信息卸载到持久存储，使原本会超出上下文限制的智能体工作流得以进行
* **按需访问信息：** Claude 可以在需要时从 memory 文件中查找先前已清除的信息，而不必将所有内容保留在活动的上下文窗口中

例如，在 Claude 执行大量操作的文件编辑工作流中，随着上下文增长，Claude 可以将已完成的更改摘要写入 memory 文件。当工具结果被清除时，Claude 通过其 memory 系统仍能访问这些信息，并继续有效工作。

要同时使用这两项功能，请在 API 请求中启用它们：

<CodeGroup>

  ```python Python
  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=4096,
      messages=[{"role": "user", "content": "Hello"}],
      tools=[{"type": "memory_20250818", "name": "memory"}],
      betas=["context-management-2025-06-27"],
      context_management={"edits": [{"type": "clear_tool_uses_20250919"}]},
  )
  ```

</CodeGroup>

有关包括命令和示例在内的完整 memory tool 参考，请参阅 [Memory tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool)。

## 客户端压缩（SDK）

<Warning>
  **Anthropic 建议使用服务端压缩，而非 SDK 压缩。** [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction) 能以更低的集成复杂度自动处理上下文管理，提供更好的 token 用量计算，且没有客户端限制。仅当你特别需要在客户端控制摘要过程时，才使用 SDK 压缩。

  TypeScript 和 Ruby SDK 中的 `compaction_control` 参数已弃用，并将在未来版本中移除。启用时 SDK 会发出弃用警告。Python SDK 已在 v1.0 中移除该参数。要在 tool runner 中使用服务端压缩，请在请求的 `context_management` 参数中传入 `compact_20260112` edit。
</Warning>

<Note>
  压缩在使用 [`tool_runner` 方法](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-runner) 时，可在 [TypeScript 和 Ruby SDK](https://platform.claude.com/docs/en/cli-sdks-libraries/overview) 中使用。
</Note>

压缩是一项 SDK 功能，当 token 用量变得过大时，通过生成摘要来自动管理对话上下文。与清除内容的服务端上下文编辑策略不同，压缩指示 Claude 对对话历史进行摘要，然后用该摘要替换完整历史。这使 Claude 能够继续处理原本会超出 [上下文窗口](https://platform.claude.com/docs/en/build-with-claude/context-windows) 的长时间运行任务。

### 压缩的工作原理

启用压缩后，SDK 会在每次模型响应后监控 token 用量：

1. **阈值检查：** SDK 将总 token 计算为 `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens`（缓存 token 字段参见 [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)）。
2. **摘要生成：** 当超过阈值时，会将摘要 prompt 作为 user 轮次注入，Claude 生成包裹在 `<summary></summary>` 标签中的结构化摘要。
3. **上下文替换：** SDK 提取摘要并用它替换整个消息历史。
4. **继续：** 对话从摘要处恢复，Claude 从中断处继续。

### 使用压缩

在 `tool_runner` 调用中添加 `compaction_control`，以在 token 用量超过阈值时启用自动摘要。

<Tabs>
  <Tab title="cURL">
    <Note>
      压缩在 SDK 的 `tool_runner` 辅助方法中于客户端运行，因此没有直接的 HTTP 等价物。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩。
    </Note>
  </Tab>

  <Tab title="CLI">
    <Note>
      CLI 不包含 `tool_runner` 辅助方法。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩，无需 SDK 侧集成。
    </Note>
  </Tab>

  <Tab title="Python">
    <Note>
      在 v1.0 及更高版本中，Python SDK 的 tool runner 不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="TypeScript">
  </Tab>

  <Tab title="C#">
    <Note>
      C# SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Go">
    <Note>
      Go SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Java">
    <Note>
      Java SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="PHP">
    <Note>
      PHP SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Ruby">
  </Tab>
</Tabs>

#### 压缩过程中发生的事情

随着对话增长，消息历史会不断累积：

**压缩前（接近 100k token）：**

```json
[
  { "role": "user", "content": "Analyze all files and write a report..." },
  { "role": "assistant", "content": "I'll help. Let me start by reading..." },
  {
    "role": "user",
    "content": [{ "type": "tool_result", "tool_use_id": "...", "content": "..." }]
  },
  { "role": "assistant", "content": "Based on file1.txt, I see..." },
  {
    "role": "user",
    "content": [{ "type": "tool_result", "tool_use_id": "...", "content": "..." }]
  },
  { "role": "assistant", "content": "After analyzing file2.txt..." }
  // ... 50 more exchanges like this ...
]
```

当 token 超过阈值时，SDK 会注入摘要请求，Claude 生成摘要。然后整个历史被替换：

**压缩后（回到约 2–3k token）：**

```json
[
  {
    "role": "assistant",
    "content": "# Task Overview\nThe user requested analysis of directory files to produce a summary report...\n\n# Current State\nAnalyzed 52 files across 3 subdirectories. Key findings documented in report.md...\n\n# Important Discoveries\n- Configuration files use YAML format\n- Found 3 deprecated dependencies\n- Test coverage at 67%\n\n# Next Steps\n1. Analyze remaining files in /src/legacy\n2. Complete final report sections...\n\n# Context to Preserve\nUser prefers markdown format with executive summary first..."
  }
]
```

Claude 会从这个摘要继续工作，就像它就是原始对话历史一样。

### 配置选项

| 参数                 | 类型    | 必填 | 默认值                                                      | 说明                              |
| ------------------------- | ------- | -------- | ------------------------------------------------------------ | ---------------------------------------- |
| `enabled`                 | boolean | 是      | -                                                            | 是否启用自动压缩   |
| `context_token_threshold` | number  | 否       | 100,000                                                      | 触发压缩的 token 数量 |
| `model`                   | string  | 否       | 与主模型相同                                           | 用于生成摘要的模型    |
| `summary_prompt`          | string  | 否       | 参见 [默认摘要 prompt](https://platform.claude.com/docs/en/build-with-claude/context-editing#default-summary-prompt) | 用于摘要生成的自定义 prompt     |

#### 选择 token 阈值

该阈值决定何时进行压缩。阈值越低，压缩越频繁，上下文窗口越小。阈值越高，允许的上下文越多，但有触及限制的风险。

<Tabs>
  <Tab title="cURL">
    <Note>
      压缩在 SDK 的 `tool_runner` 辅助方法中于客户端运行，因此没有直接的 HTTP 等价物。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩。
    </Note>
  </Tab>

  <Tab title="CLI">
    <Note>
      CLI 不包含 `tool_runner` 辅助方法。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩，无需 SDK 侧集成。
    </Note>
  </Tab>

  <Tab title="Python">
    <Note>
      在 v1.0 及更高版本中，Python SDK 的 tool runner 不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="TypeScript">
  </Tab>

  <Tab title="C#">
    <Note>
      C# SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Go">
    <Note>
      Go SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Java">
    <Note>
      Java SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="PHP">
    <Note>
      PHP SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Ruby">
  </Tab>
</Tabs>

#### 使用不同的模型生成摘要

你可以使用更快或更便宜的模型来生成摘要：

<Tabs>
  <Tab title="cURL">
    <Note>
      压缩在 SDK 的 `tool_runner` 辅助方法中于客户端运行，因此没有直接的 HTTP 等价物。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩。
    </Note>
  </Tab>

  <Tab title="CLI">
    <Note>
      CLI 不包含 `tool_runner` 辅助方法。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩，无需 SDK 侧集成。
    </Note>
  </Tab>

  <Tab title="Python">
    <Note>
      在 v1.0 及更高版本中，Python SDK 的 tool runner 不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="TypeScript">
  </Tab>

  <Tab title="C#">
    <Note>
      C# SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Go">
    <Note>
      Go SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Java">
    <Note>
      Java SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="PHP">
    <Note>
      PHP SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Ruby">
  </Tab>
</Tabs>

#### 自定义摘要 prompt

你可以为特定领域需求提供自定义 prompt。你的 prompt 应指示 Claude 将其摘要包裹在 `<summary></summary>` 标签中。

<Tabs>
  <Tab title="cURL">
    <Note>
      压缩在 SDK 的 `tool_runner` 辅助方法中于客户端运行，因此没有直接的 HTTP 等价物。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩。
    </Note>
  </Tab>

  <Tab title="CLI">
    <Note>
      CLI 不包含 `tool_runner` 辅助方法。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩，无需 SDK 侧集成。
    </Note>
  </Tab>

  <Tab title="Python">
    <Note>
      在 v1.0 及更高版本中，Python SDK 的 tool runner 不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="TypeScript">
  </Tab>

  <Tab title="C#">
    <Note>
      C# SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Go">
    <Note>
      Go SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Java">
    <Note>
      Java SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="PHP">
    <Note>
      PHP SDK 包含 tool runner，但不支持客户端 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)：通过在请求的 `context_management` 参数中传入 `compact_20260112` edit，即可与 tool runner 配合使用。
    </Note>
  </Tab>

  <Tab title="Ruby">
  </Tab>
</Tabs>

### 默认摘要 prompt

内置摘要 prompt 指示 Claude 创建结构化的续写摘要，包括：

1. **任务概述：** 用户的核心请求、成功标准和约束。
2. **当前状态：** 已完成的内容、已修改的文件以及已生成的产物。
3. **重要发现：** 技术约束、已做出的决策、已解决的错误以及失败的方法。
4. **后续步骤：** 所需的具体操作、阻塞项和优先级顺序。
5. **需保留的上下文：** 用户偏好、领域特定细节以及已做出的承诺。

这种结构使 Claude 能够高效恢复工作，而不会丢失重要上下文或重复错误。

<Accordion title="查看完整默认 prompt">
  ```text wrap
  You have been working on the task described above but have not yet completed it. Write a continuation summary that will allow you (or another instance of yourself) to resume work efficiently in a future context window where the conversation history will be replaced with this summary. Your summary should be structured, concise, and actionable. Include:

  1. Task Overview
  The user's core request and success criteria
  Any clarifications or constraints they specified

  2. Current State
  What has been completed so far
  Files created, modified, or analyzed (with paths if relevant)
  Key outputs or artifacts produced

  3. Important Discoveries
  Technical constraints or requirements uncovered
  Decisions made and their rationale
  Errors encountered and how they were resolved
  What approaches were tried that didn't work (and why)

  4. Next Steps
  Specific actions needed to complete the task
  Any blockers or open questions to resolve
  Priority order if multiple steps remain

  5. Context to Preserve
  User preferences or style requirements
  Domain-specific details that aren't obvious
  Any promises made to the user

  Be concise but complete—err on the side of including information that would prevent duplicate work or repeated mistakes. Write in a way that enables immediate resumption of the task.

  Wrap your summary in <summary></summary> tags.
  ```
</Accordion>

### 限制

#### 服务端工具

<Warning>
  在使用 [web search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool) 或 [web fetch](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool) 等服务端工具时，压缩需要特别考虑。
</Warning>

使用服务端工具时，SDK 可能错误计算 token 用量，导致压缩在错误的时间触发。

例如，在 web search 操作之后，API 响应可能显示：

```json Output
{
  "usage": {
    "input_tokens": 63000,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 270000,
    "output_tokens": 1400
  }
}
```

SDK 将总用量计算为 63,000 + 0 + 270,000 + 1,400 = 334,400 token。然而，`cache_read_input_tokens` 值包含服务端工具进行的多次内部 API 调用的累计读取，而非你的实际对话上下文。你的真实上下文长度可能仅为 63,000 的 `input_tokens`，但 SDK 看到的是 334k，从而过早触发压缩。

**变通方法：**

* 使用 [token 计数](https://platform.claude.com/docs/en/build-with-claude/token-counting) 端点获取准确的上下文长度
* 在大量使用服务端工具时避免压缩

#### 工具使用边界情况

当 SDK 在工具使用响应待处理时触发压缩，它会在生成摘要之前从消息历史中移除该 tool use block。如果仍需要，Claude 会在从摘要恢复后重新发出该工具调用。

### 监控压缩

了解压缩何时触发有助于你调整阈值并验证预期行为。

<Tabs>
  <Tab title="cURL">
    <Note>
      压缩在 SDK 的 `tool_runner` 辅助方法中于客户端运行，因此没有直接的 HTTP 等价物。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩。
    </Note>
  </Tab>

  <Tab title="CLI">
    <Note>
      CLI 不包含 `tool_runner` 辅助方法。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)，由 Anthropic 的服务器处理压缩，无需 SDK 侧集成。
    </Note>
  </Tab>

  <Tab title="Python">
    <Note>
      在 v1.0 及更高版本中，Python SDK 的 tool runner 不支持 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)。
    </Note>
  </Tab>

  <Tab title="TypeScript">
    TypeScript SDK 的 `toolRunner` 支持压缩，但不记录事件。通过观察各轮之间 `runner.params.messages.length` 缩小来检测压缩：

  </Tab>

  <Tab title="C#">
    <Note>
      C# SDK 的 tool runner 不支持 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)。
    </Note>
  </Tab>

  <Tab title="Go">
    <Note>
      Go SDK 的 tool runner 不支持 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)。
    </Note>
  </Tab>

  <Tab title="Java">
    <Note>
      Java SDK 的 tool runner 不支持 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)。
    </Note>
  </Tab>

  <Tab title="PHP">
    <Note>
      PHP SDK 的 tool runner 不支持 `compaction_control`。请改用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)。
    </Note>
  </Tab>

  <Tab title="Ruby">
    Ruby SDK 支持在压缩发生时触发的 `on_compact:` 回调。将其添加到你的 `compaction_control` 配置中：

  </Tab>
</Tabs>

### 何时使用压缩

**适合的用例：**

* 处理大量文件或数据源的长时间运行智能体任务
* 积累大量信息的研究工作流
* 具有清晰、可衡量进度的多步骤任务
* 生成在对话之外持久存在的产物（文件、报告）的任务

**不太理想的用例：**

* 需要精确回忆早期对话细节的任务
* 大量使用服务端工具的工作流
* 需要在许多变量之间维持精确状态的任务

## 后续步骤

<CardGroup cols={2}>
  <Card title="压缩" icon="arrows-clockwise" href="https://platform.claude.com/docs/en/build-with-claude/compaction">
    使用服务端压缩管理长对话，这是大多数用例的推荐策略。
  </Card>

  <Card title="Prompt Caching" icon="database" href="https://platform.claude.com/docs/en/build-with-claude/prompt-caching">
    通过缓存 prompt 前缀降低成本和延迟，并了解上下文编辑如何与缓存交互。
  </Card>
</CardGroup>