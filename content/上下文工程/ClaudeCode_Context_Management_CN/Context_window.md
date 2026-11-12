+++
title = "上下文窗口"
slug = "context-windows"
weight = 80
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "了解上下文窗口如何工作、extended thinking 和工具调用如何计入其中，以及如何在对话增长时管理上下文。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/context-windows"
+++

随着对话增长，你最终会接近上下文窗口限制。对于长时间运行的对话和 agentic 工作流，[服务端压缩（server-side compaction）](https://platform.claude.com/docs/en/build-with-claude/compaction) 是上下文管理的主要策略。

## 上下文窗口如何工作

“上下文窗口”（context window）指语言模型在生成回复时可参考的全部文本，包括回复本身。这不同于语言模型训练所用的大规模语料，而是模型的“工作记忆”。更大的上下文窗口让模型能够处理更复杂、更长的 prompt，但更多上下文并不自动意味着更好。随着 token 数量增长，准确性和召回会下降，这一现象称为 *context rot*。因此，策选上下文中有什么，与可用空间有多大同样重要。

<Tip>
  关于长上下文为何会退化以及如何围绕它进行工程设计，见 [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)。
</Tip>

下图说明了 API 请求的标准上下文窗口行为1：

![Diagram of turns accumulating in the context window until the conversation approaches the token limit](https://platform.claude.com/docs/images/context-window.svg)

*1 诸如 [claude.ai](https://claude.ai/) 之类的聊天界面也可以按滚动的“先进先出”方式管理上下文窗口。*

* **token 逐步累积：** 随着对话按 turn 推进，每条 user message 和 assistant 回复都会在上下文窗口中累积，且先前的 turn 会被完整保留。

* **上下文窗口容量：** 上下文窗口（[最多 1M tokens，取决于模型](https://platform.claude.com/docs/en/build-with-claude/context-windows#context-window-sizes-by-model)）保存对话历史，加上 Claude 新生成的输出。

* **输入-输出流程：** 每个 turn 包括：

  * **输入阶段：** 包含全部先前对话历史加上当前 user message
  * **输出阶段：** 生成一段文本回复，该回复会成为下一 turn 输入的一部分

请求中的所有内容都计入上下文窗口：system prompt、`messages` 中的每条消息（包括工具结果、图片和文档），以及你的工具定义。Claude 为本 turn 生成的输出（包括其 extended thinking）也计入。每次响应都会在 `usage` 字段中报告该请求消耗了什么。如果你使用 [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)，输入计数会拆分到 `input_tokens`、`cache_read_input_tokens` 和 `cache_creation_input_tokens`，这三项都计入窗口。要在发送前估算请求，使用 [token counting API](https://platform.claude.com/docs/en/build-with-claude/token-counting)。

## 各模型的上下文窗口大小

Claude Fable 5.1、Claude Mythos 5.1、Claude Fable 5、Claude Mythos 5、Claude Opus 5、Claude Opus 4.8、Claude Opus 4.7、Claude Opus 4.6、Claude Sonnet 5、Claude Sonnet 4.6 和 [Claude Mythos Preview](https://anthropic.com/glasswing) 具有 1M-token 上下文窗口。对其中任一模型的单次请求最多可生成 128k 输出 tokens（`max_tokens`）。其他 Claude 模型，包括 Claude Sonnet 4.5，具有 200k-token 上下文窗口。

对每个具有 1M-token 上下文窗口的模型，1M 是默认值：你不需要 beta header，长上下文请求按 [标准定价](https://platform.claude.com/docs/en/about-claude/pricing#long-context-pricing) 计费。

单次请求最多可包含 600 张图片或 PDF 页（对具有 200k-token 上下文窗口的模型为 100）。如果你发送大量图片或大型文档，可能会在达到 token 限制之前先达到 [请求大小限制](https://platform.claude.com/docs/en/api/overview#request-size-limits)。

各模型上下文窗口大小列表见 [模型对比](https://platform.claude.com/docs/en/models/overview#latest-models-comparison) 表。

## 带 thinking 的上下文窗口

使用 [thinking](https://platform.claude.com/docs/en/build-with-claude/thinking) 时，所有输入和输出 tokens（包括 thinking tokens）都计入上下文窗口限制，在多 turn 情况下有一些细微差别。

thinking tokens 是你的 `max_tokens` 参数的子集，按输出 tokens 计费，并计入速率限制。使用 [adaptive thinking](https://platform.claude.com/docs/en/build-with-claude/thinking) 时，Claude 会动态决定其 thinking 分配，因此 thinking token 用量会因请求而异。

先前 assistant turn 中的 thinking blocks 是否留在上下文窗口中取决于模型。在 Claude Opus 4.5 及之后的 Opus 模型、Claude Sonnet 4.6 及之后的 Sonnet 模型、Claude Fable 5.1、Claude Mythos 5.1、Claude Fable 5、Claude Mythos 5 和 Claude Mythos Preview 上，API 默认保留先前的 thinking blocks，它们像其他输入 tokens 一样计入上下文窗口。在更早的 Opus 和 Sonnet 模型以及所有 Haiku 模型上，当你把先前的 thinking blocks 传回时，API 会自动从对话历史中剥离它们，从而为对话内容保留 token 容量。各模型默认值见 [thinking block 按模型的保留策略](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-block-preservation-by-model)。要向任一方向覆盖默认值，使用 [thinking block 清除](https://platform.claude.com/docs/en/build-with-claude/context-editing#thinking-block-clearing)。

下图展示了在会剥离先前 thinking blocks 的模型上启用 thinking 时如何管理 tokens：

![Diagram of thinking on a model that strips previous thinking blocks: each turn's thinking block is generated in the output and not carried into later turns' input](https://platform.claude.com/docs/images/context-window-thinking.svg)

* **剥离 thinking blocks：** 在会剥离先前 thinking blocks 的模型上，thinking blocks（深灰色所示）在每个 turn 的输出阶段生成，但不会作为后续 turn 的输入 tokens 向前携带。你不需要自己剥离 thinking blocks：如果你把它们传回，Claude API 会自动剥离。
* **计费：** thinking tokens 在生成时作为输出 tokens 计费一次。在会保留先前 thinking blocks 的模型上，被保留的 blocks 随后会成为后续请求输入的一部分，并像对话历史的其余部分一样作为输入 tokens 计费。

<Note>
  你可以在 [Thinking](https://platform.claude.com/docs/en/build-with-claude/thinking) 指南中阅读更多关于上下文窗口与 thinking 的内容。
</Note>

## 带 thinking 和工具调用的上下文窗口

下图说明了在会剥离先前 thinking blocks 的模型上，将 thinking 与工具调用结合时如何管理 tokens：

![Diagram of thinking with tool use: thinking is kept with its tool result, then dropped on the next user turn on models that strip previous thinking blocks](https://platform.claude.com/docs/images/context-window-thinking-tools.svg)

<Steps>
  <Step title="第一 turn 的结构">
    * **输入组成部分：** 工具配置和 user message
    * **输出组成部分：** Thinking + 文本回复 + 工具调用请求
    * **token 计算：** 所有输入和输出组成部分都计入上下文窗口，所有输出组成部分都作为输出 tokens 计费。
  </Step>

  <Step title="工具结果处理（turn 2）">
    * **输入组成部分：** 第一 turn 中的每个 block 以及 `tool_result`。你必须把 thinking block 与对应的工具结果一起返回。这是你必须返回 thinking blocks 的唯一情况。
    * **输出组成部分：** 工具结果传回 Claude 之后，Claude 只以文本回复（在下一条 `user` message 之前不会有额外的 thinking，除非启用了 [interleaved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#interleaved-thinking)）。
    * **token 计算：** 所有输入和输出组成部分都计入上下文窗口，所有输出组成部分都作为输出 tokens 计费。
  </Step>

  <Step title="新的 user turn（turn 3）">
    * **输入组成部分：** 上一 turn 的所有输入和输出都会向前携带。已完成的工具调用周期中的 thinking block 不再必须留在上下文中：在会剥离先前 thinking blocks 的模型上，当你把它传回时 API 会自动丢弃它；在会保留先前 thinking blocks 的模型上，它会保留，除非你用 [thinking block 清除](https://platform.claude.com/docs/en/build-with-claude/context-editing#thinking-block-clearing) 将其清除。这也是你加入下一个 `user` turn 的位置。
    * **输出组成部分：** 因为在工具调用周期之外有一个新的 `user` turn，Claude 会生成一个新的 thinking block 并从那里继续。
    * **token 计算：** 在会剥离先前 thinking blocks 的模型上，先前的 thinking tokens 不再计入上下文窗口。所有其他先前的 blocks 仍计入上下文窗口，当前 `assistant` turn 中的 thinking block 也计入。
  </Step>
</Steps>

* **将 thinking 与工具调用一起使用时的注意事项：**

  * 当你提交工具结果时，必须包含伴随该工具请求的整个未经修改的 thinking block，包括其 signature。
  * API 使用加密签名来验证 thinking block 的真实性。如果你修改了 thinking block，API 会返回错误。

<Note>
  大多数当前 Claude 模型支持 [interleaved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#interleaved-thinking)，它让 Claude 可以在工具调用之间思考，包括在收到工具结果之后。在具有 adaptive thinking 的模型上它是自动的；Claude Opus 4.5、Claude Sonnet 4.5 以及更早的 Claude 4 模型需要 `interleaved-thinking-2025-05-14` beta header，Claude Haiku 4.5 不支持它。

  关于将工具与 thinking 一起使用的更多信息，见 [Thinking with tool use](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-with-tool-use)。
</Note>

要减少工具定义本身消耗的上下文，见 [Manage tool context](https://platform.claude.com/docs/en/agents-and-tools/tool-use/manage-tool-context)，或用 [tool search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool) 延迟加载工具定义。

## 上下文感知

Claude Sonnet 5、Claude Sonnet 4.6、Claude Sonnet 4.5 和 Claude Haiku 4.5 具有**上下文感知（context awareness）**：这些模型会在整个对话中跟踪其剩余上下文窗口（它们的“token budget”）。这让模型可以对照剩余空间来管理长时间运行的任务，而不是猜测还剩多少 tokens。上下文感知是自动的：你无需启用任何东西，也永远不要自己发送本节所示的标签。API 会注入它们。

### 工作原理

在每个请求的 system prompt 中，API 会告诉 Claude 其总上下文窗口：

```xml
<budget:token_budget>200000</budget:token_budget>
```

该预算与你的请求可用的上下文窗口匹配：Claude Sonnet 5 和 Claude Sonnet 4.6 为 1M tokens，Claude Sonnet 4.5 和 Claude Haiku 4.5 为 200k tokens。本节示例展示的是具有 200k-token 上下文窗口的模型。

每次工具调用之后，API 会向 Claude 提供剩余容量的更新：

```xml
<system_warning>Token usage: 35000/200000; 165000 remaining</system_warning>
```

图片 tokens 包含在这些预算中。

Claude Opus 4.7 及之后的 Opus 模型、Claude Fable 5.1、Claude Mythos 5.1、Claude Fable 5 和 Claude Mythos 5 不会收到这些注入的标签。在这些模型上，你可以用 [task budgets](https://platform.claude.com/docs/en/build-with-claude/task-budgets) 给模型一个显式预算，该功能处于 beta。

<Tip>
  对于跨越多个会话的 agents，设计你的状态制品，使得新会话开始时上下文恢复很快。[memory tool 的多会话模式](https://platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool#multisession-software-development-pattern) 给出了一种具体做法。另见 [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)。
</Tip>

关于使用上下文感知的 prompting 指导，见 [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#context-awareness-and-multiwindow-workflows)。

## 用压缩管理上下文

如果你的对话经常接近上下文窗口限制，使用 [服务端压缩](https://platform.claude.com/docs/en/build-with-claude/compaction)。压缩会在服务端自动摘要对话的较早部分，使对话可以越过上下文窗口限制继续。它对 Claude 4.6 及之后的模型和 [Claude Mythos Preview](https://anthropic.com/glasswing) 以 beta 提供。

对于更专门的需求，[上下文编辑（context editing）](https://platform.claude.com/docs/en/build-with-claude/context-editing) 提供额外策略：

* **工具结果清除：** 在 agentic 工作流中清除旧的工具结果
* **thinking block 清除：** 在使用 extended thinking 时管理 thinking blocks

已缓存的 prompt 前缀仍然占用上下文窗口：[Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 改变的是你为这些 tokens 支付的费用，而不是它们是否计入。

## 上下文窗口溢出行为

如果仅输入就已经超过模型的上下文窗口，API 在每个模型上都会返回 400 `invalid_request_error`（"prompt is too long"）。

在 Claude 4.5 模型及更新模型上，如果输入 tokens 加上 `max_tokens` 超过上下文窗口大小，API 会接受该请求。如果随后生成到达上下文窗口限制，它会以 `stop_reason: "model_context_window_exceeded"` 停止。在更早的模型上，API 会改为返回 [校验错误](https://platform.claude.com/docs/en/api/errors)。要在那些模型上选择启用 `model_context_window_exceeded` 行为，使用 `model-context-window-exceeded-2025-08-26` beta header。细节见 [Stop reasons and fallback](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons)。

要保持在上下文窗口限制之内，在向 Claude 发送消息之前使用 [token counting API](https://platform.claude.com/docs/en/build-with-claude/token-counting) 估算 token 用量。

## 后续步骤

<CardGroup cols={2}>
  <Card title="压缩" icon="stack" href="https://platform.claude.com/docs/en/build-with-claude/compaction">
    用于管理接近上下文窗口限制的长对话的服务端上下文压缩。
  </Card>

  <Card title="上下文编辑" icon="edit" href="https://platform.claude.com/docs/en/build-with-claude/context-editing">
    随着对话增长，用上下文编辑自动管理对话上下文。
  </Card>

  <Card title="模型对比表" icon="scales" href="https://platform.claude.com/docs/en/models/overview#latest-models-comparison">
    查看模型对比表，了解各模型的上下文窗口大小以及输入/输出 token 定价。
  </Card>

  <Card title="Thinking" icon="settings" href="https://platform.claude.com/docs/en/build-with-claude/thinking">
    为复杂任务为 Claude 提供增强推理，并控制 thinking 内容如何返回。
  </Card>
</CardGroup>
