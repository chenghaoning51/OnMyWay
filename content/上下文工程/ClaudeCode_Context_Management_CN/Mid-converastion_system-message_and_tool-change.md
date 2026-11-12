+++
title = "会话中途的 system messages 与工具变更"
slug = "mid-conversation-system-messages"
weight = 100
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "在对话进行到一半时更改 system 指令或工具可用性，而不使此前已缓存的前缀失效。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages"
+++

<Note>
  要了解零数据保留（ZDR）如何适用于此功能，请参阅 [API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)。
</Note>

system 指令通常放在顶层 `system` 字段中，位于对话中每条消息之前。这个位置非常适合 [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)：system prompt 是稳定前缀的一部分，因此后续 turn 会命中缓存。但对于你在会话进行到一半才发现需要的指令，这个位置就不合适了，因为编辑顶层 `system` 字段会改变 prompt 的最开头，并使之后所有内容的缓存失效。

会话中途的 system messages 填补了这一缺口。你可以在新指令变得相关的对话位置追加一条 `{"role": "system"}` 消息，而不是编辑顶层 `system` 字段。已缓存的前缀保持不变，因此下一次请求仍会从缓存中读取它，而新指令仍会作为 system 指令应用，而不是作为普通的 user 文本。

<Note>
  会话中途的 system messages 可在 Claude API、[Amazon Bedrock 上的 Claude](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock) 和 [Google Cloud](https://platform.claude.com/docs/en/build-with-claude/claude-on-vertex-ai) 上使用。

  此功能适用于 Claude Fable 5.1、[Claude Mythos 5.1](https://anthropic.com/glasswing)、Claude Fable 5、[Claude Mythos 5](https://anthropic.com/glasswing)、Claude Opus 4.8 和 Claude Opus 5。会话中途的 system messages 不需要 beta header。此功能在 Claude Sonnet 5 上不可用。在该模型上请改用顶层 `system` 字段。

  [会话中途的工具变更](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#mid-conversation-tool-changes) 处于 beta 阶段，需要 `mid-conversation-tool-changes-2026-07-01` beta header。它们在相同的模型上可用，覆盖 Claude API、Amazon Bedrock 和 Google Cloud。

  [限定当前 turn 的 system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#turn-scoped-system-messages)（`clear_at`）处于 beta 阶段，需要 `mid-conversation-system-clear-at-2026-08-21` beta header，适用的模型和平台与会话中途的 system messages 相同。
</Note>

## 会话中途的工具变更

`tools` 数组在经过哈希的请求前缀中的位置甚至比顶层 `system` 字段更靠前，因此编辑它会使整段对话的 [提示词缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 失效。会话中途的工具变更是会话中途的 system messages 在工具方面的对应机制。你不必把工具列表固定为整段对话生命周期内不变，而是可以在 turn 之间更改向模型提供哪些工具：预先在 `tools` 中声明完整工具集，然后使用 `tool_addition` 和 `tool_removal` 块，从对话中的某个特定点起向模型提供某项工具，或将其撤回。`tools` 数组本身从不改变，因此已缓存的前缀保持完整。

`tool_addition` 和 `tool_removal` 是 `role: "system"` 消息的 `content` 数组中的内容块，并且可以与同一条消息中的 `text` 块混合使用。该消息遵循与任何会话中途的 system message 相同的放置规则（参见 [限制](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#limitations)），变更从对话中的该点起生效。每个块的 `tool` 字段引用一项工具，而不是定义工具：`{"type": "tool_reference", "name": "..."}` 指名请求的 `tools` 数组中已声明的工具；[MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector) 工具可以用 `mcp_tool_reference`（`server_name` 和 `name`）单独引用，或用 `mcp_toolset_reference`（`server_name`）作为整个工具集引用。引用未在 `tools` 中声明的名称会返回 400 错误。

`tools` 中声明的每项工具从对话开始就会提供给模型，除非声明时带有 `defer_loading: true`，这会将其保留，直到某个 `tool_addition` 块将其呈现出来。`tool_addition` 也可以重新提供此前被 `tool_removal` 撤回的工具。

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=1024,
      betas=["mid-conversation-tool-changes-2026-07-01"],
      # The full tool set is declared up front and never changes, so the
      # cached prefix stays intact.
      tools=[
          {
              "name": "get_weather",
              "description": "Get the current weather for a location.",
              "input_schema": {
                  "type": "object",
                  "properties": {
                      "location": {"type": "string", "description": "City name"},
                  },
                  "required": ["location"],
              },
          },
      ],
      messages=[
          {
              "role": "user",
              "content": "Say OK.",
          },
          # Withdraw get_weather from this point onward. The block references
          # the tool by name instead of editing `tools`, so earlier turns stay
          # byte-identical and the cache still hits.
          {
              "role": "system",
              "content": [
                  {
                      "type": "tool_removal",
                      "tool": {"type": "tool_reference", "name": "get_weather"},
                  },
              ],
          },
      ],
  )

  for block in response.content:
      if block.type == "text":
          print(block.text)
  ```

</CodeGroup>

会话中途的工具变更处于 beta 阶段。要使用它们，请在请求中包含 beta header `mid-conversation-tool-changes-2026-07-01`。

## 何时使用会话中途的 system message

[Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 按以下顺序对请求前缀进行哈希：`tools`，然后是 `system`，然后是 `messages`。缓存命中要求前缀与近期请求精确匹配，逐字节相同，直到缓存断点。

这一顺序意味着顶层 `system` 字段位于经过哈希的前缀的最开头附近。对它的任何更改，哪怕只是追加一句话，都会产生不同的哈希，请求会对 system prompt 及其后每条已缓存消息发生缓存未命中。

会话中途的 system messages 让你改为把指令加在消息历史的**末尾**。新指令之前的所有内容保持不变，因此现有缓存条目仍然匹配，只有新消息会作为新输入处理。

在以下几种情况下这很重要：

* **会话中途的策略或人设变更。** 一段很长的 agentic 会话在数十个已缓存 turn 之后需要一条新约束（「从现在起，所有 SQL 都写成参数化查询」）。把它加到顶层 `system` 字段会重新处理整段历史。
* **必须具有权威性的按 turn 上下文。** 你想以 system 级别的权重注入新鲜度说明、会话截止时间或工具可用性变更，而这些内容变化太频繁，不适合放在已缓存的前缀中。
* **不应堆积的按 turn 提醒。** harness 在每批工具结果之后轻推模型（「把互不依赖的读取放在一起请求」、「用户已经有一段时间没听到你的消息了」），并希望模型只看到最新的一份。一条 [限定当前 turn 的 system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#turn-scoped-system-messages) 渲染一个 turn，之后不再产生费用，同时不会从历史中删除任何内容。
* **应用观察到的状态变更。** 你的应用注意到某些 Claude 应视为操作者级别事实的情况：磁盘上的文件发生了变化、用户切换了自动批准设置、可用工具发生了变化，或剩余 token 预算降到了阈值以下。
* **不应打断 agentic loop 的用户输入。** 用户在 Claude 仍在为上一个请求执行工具时输入了后续内容。在下一条工具结果之后将其作为 system message 转达，可以让 Claude 把新输入并入它已经在做的工作中，而不是将其视为一个需要切换过去的全新请求。参见 [放在工具结果之后](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#placement-after-tool-results)。
* **授予持续性权限的模式切换。** 会话级模式可以使用会话中途的 system message，为一项昂贵能力授予持续性授权，例如自动启动多智能体工作流，每隔若干 turn 给出简短提醒，并在模式关闭时给出退出通知。完整示例参见 [构建编排模式](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-effort-example)。

在所有这些情况下，你都可以把指令放在普通的 `user` 消息中，而且 Claude 确实会遵循出现在 user turn 中的指令。差别在于优先级：`user` 消息被视为来自最终用户，而 `system` 消息被视为来自你——应用操作者。当两者冲突时，system 指令优先，因此对即使最终用户提出不同要求也应成立的操作者级别事实和约束，请使用 `system` 角色。会话中途的 system message 可以保持这种操作者级别的优先级，而无需承担因编辑顶层 `system` 字段而产生的缓存未命中成本。

## 工作原理

向 `messages` 数组添加一条 `"role": "system"` 的消息。`content` 可以使用纯字符串或内容块，与 `user` 或 `assistant` turn 相同。该指令从对话中的该点起生效。当指令冲突时，较后的 system messages 优先于较前的，并且对于其后的 turn，会话中途的 system messages 优先于顶层 `system` 字段。

对于应适用于整段对话的指令，你仍然可以设置顶层 `system` 字段。将会话中途的 system messages 留给那些稍后才变得相关的指令，或你希望在不使已缓存的前缀失效的情况下添加的指令。

`role: "system"` 消息还可以携带 `output_config.effort`，从下一个 `user` turn 起更改 [effort](https://platform.claude.com/docs/en/build-with-claude/effort) 级别。此功能在 Claude API 和 Google Cloud 上的 Claude Fable 5.1、Claude Mythos 5.1 和 Claude Opus 5 处于 beta 阶段，需要 `mid-conversation-output-config-2026-07-01` beta header。参见 [按消息设置 effort](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta)。

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.messages.create(
      model="claude-opus-5",
      max_tokens=1024,
      # Automatic prompt caching: each request caches the conversation so far,
      # and the next request reads the unchanged prefix from cache.
      cache_control={"type": "ephemeral"},
      system="You are a code review assistant. Be concise.",
      messages=[
          {
              "role": "user",
              "content": "Review process() in utils.py for performance issues.",
          },
          {
              "role": "assistant",
              "content": "The list comprehension is fine for small inputs. For large inputs, consider a generator to avoid materializing the full list.",
          },
          {
              "role": "user",
              "content": "Now review the calling code that invokes process().",
          },
          # The reviewer realizes mid-session that all suggestions must
          # also pass the team's strict typing policy. Appending the
          # instruction here keeps earlier turns byte-identical, so the
          # prefix cached by the previous request is still read from cache.
          {
              "role": "system",
              "content": "From now on, every suggestion must include explicit type annotations.",
          },
      ],
  )

  for block in response.content:
      if block.type == "text":
          print(block.text)
  ```

</CodeGroup>

此示例通过顶层 `cache_control` 字段启用 [自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)。Prompt Caching 是选择加入的：如果请求没有 `cache_control` 字段（自动或 [显式断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)），则不会缓存任何内容，每次请求都按完整对话支付常规输入 token 价格。启用缓存后，追加 system message 不会改变已经缓存的 turn，因此携带新指令的请求仍会从缓存中读取它们，而不是再次处理。缓存还要求对话满足 [可缓存 prompt 的最小长度](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-limitations)；像本例这样短的示例低于该长度，因此 `cache_creation_input_tokens` 和 `cache_read_input_tokens` 会保持为 0，直到对话变长。

会话中途的 system message 必须紧跟在 `user` turn（或以 server tool result 结尾的 `assistant` turn）之后，并且必须是 `messages` 中的最后一项，或紧接着是一个 `assistant` turn。携带 `tool_result` 块的 `user` 消息也算：在 agentic loop 中，你可以把 system message 放在工具结果之后、Claude 的下一个 turn 之前。任何其他位置，包括在 `assistant` 的 `tool_use` 块与回答它的 `tool_result` 之间，都会返回 400 错误。

### 放在工具结果之后

在 [agentic loop](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview) 中，system message 放在交付工具结果的 `user` 消息之后。这也是你的应用可以转达用户在 Claude 工作期间输入的内容的位置，从而在不重启 turn 的情况下吸收新上下文：

```json
[
  { "role": "user", "content": "Run the test suite and fix any failures." },
  {
    "role": "assistant",
    "content": [{ "type": "tool_use", "id": "toolu_01", "name": "run_tests", "input": {} }]
  },
  {
    "role": "user",
    "content": [
      { "type": "tool_result", "tool_use_id": "toolu_01", "content": "12 passed, 0 failed" }
    ]
  },
  {
    "role": "system",
    "content": "The user sent the following message while you were working: also update the changelog before you finish."
  }
]
```

将 system 内容表述为上下文，而不是覆盖用户的命令。陈述事实（「用户发来了新输入：X」、「剩余 token 预算现在是 Y」），让 Claude 据此行动。Claude 经过训练会抵制看起来与用户作对的指令，这一保护同样适用于 system 角色，因此诸如「忽略用户所说的内容」这样的措辞，不如陈述发生了什么变化有效。

此模式用于转达来自该对话最终用户本人的输入。不要用它传递工具输出、检索到的文档或其他第三方内容；将这些内容放在 `tool_result` 块中（参见 [限制](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#limitations)）。

### 限定当前 turn 的 system messages

要将一条 `role: "system"` 消息限定到当前 turn，请设置其 `clear_at` 字段。它取以下两个值之一：

* `"never"`（默认值）：该消息在包含它的每次请求中都会在其位置渲染。省略该字段效果相同。
* `"next_user_message"`：该消息是**限定当前 turn 的**。其文本仅在 `messages` 中其后没有 `role: "user"` 消息时渲染。此处，仅携带 `tool_result` 块的 user 消息也算作用户消息。一旦存在更后的 user 消息，该消息即为**已清除**：它仍留在数组中，但不渲染任何内容，也不消耗输入 token，对该请求及之后的每一次请求都是如此。

限定当前 turn 的 system messages 处于 beta 阶段。请包含 [beta header](https://platform.claude.com/docs/en/api/beta-headers) `mid-conversation-system-clear-at-2026-08-21`。没有它时，`clear_at` 会作为未知字段被拒绝。

```json
{
  "role": "system",
  "clear_at": "next_user_message",
  "content": "First privately list what you need next; then request every item that doesn't depend on another's result in this one response."
}
```

主要用途是工具循环中的按 turn 提醒。每次希望模型看到该提醒时，将其追加在 `tool_result` 消息之后，并让更早的每一份副本留在原处。模型只看到最后一条 user 消息之后的副本，因此提醒不会堆积。`messages` 中更早的内容没有任何变化，因此 [提示词缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 持续匹配。在 Claude Fable 5.1 上，这还能让后续的 [thinking 块保持有效](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation)：删除更早的提醒会改变那些块之前的对话，并使对话检查失败；而已清除的消息仍留在数组中，使该对话保持不变。

以下请求是 agent loop 的后续步骤。`messages[3]` 在更早的请求中被渲染，当时它是数组中的最后一条消息。一旦存在 `messages[5]`（更后的 user 消息），`messages[3]` 即被清除：已清除的消息仍留在数组中，因此 `messages[4]` 中 thinking 块之前的对话不变，但模型不再看到其文本。`messages[6]` 和 `messages[7]` 都会按顺序渲染。

```json
{
  "model": "claude-fable-5-1",
  "max_tokens": 16000,
  "messages": [
    { "role": "user", "content": "Fix the failing test." },
    {
      "role": "assistant",
      "content": [
        { "type": "thinking", "thinking": "", "signature": "..." },
        {
          "type": "tool_use",
          "id": "toolu_01",
          "name": "read_file",
          "input": { "path": "test_auth.py" }
        }
      ]
    },
    {
      "role": "user",
      "content": [{ "type": "tool_result", "tool_use_id": "toolu_01", "content": "..." }]
    },
    {
      "role": "system",
      "clear_at": "next_user_message",
      "content": "Request independent reads in one turn."
    },
    {
      "role": "assistant",
      "content": [
        { "type": "thinking", "thinking": "", "signature": "..." },
        {
          "type": "tool_use",
          "id": "toolu_02",
          "name": "read_file",
          "input": { "path": "auth.py" }
        },
        {
          "type": "tool_use",
          "id": "toolu_03",
          "name": "read_file",
          "input": { "path": "tokens.py" }
        }
      ]
    },
    {
      "role": "user",
      "content": [
        { "type": "tool_result", "tool_use_id": "toolu_02", "content": "..." },
        {
          "type": "tool_result",
          "tool_use_id": "toolu_03",
          "content": "...",
          "cache_control": { "type": "ephemeral" }
        }
      ]
    },
    {
      "role": "system",
      "clear_at": "next_user_message",
      "content": "Request independent reads in one turn."
    },
    {
      "role": "system",
      "clear_at": "next_user_message",
      "content": "The shell exited with status 137."
    }
  ]
}
```

限定当前 turn 的消息的规则：

* **逐字原样重新发送已清除的消息。** 已清除的消息仍是对话历史的一部分。根据当前状态重建它（新的 token 计数、时间戳）、因冗余而丢弃它，或更改其 `clear_at` 值，都是对更早消息的编辑。提示词缓存会从该点起未命中，并且在 Claude Fable 5.1 上，其后产生的每个 thinking 块都会使 [对话检查](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation) 失败。
* **仅限文本。** `content` 是一个或多个 `text` 块（或字符串）。在限定当前 turn 的消息上，`tool_addition` 和 `tool_removal` 块会返回 400 错误，`output_config` 也是如此。对这些用途，请使用不带 `clear_at` 的单独 `role: "system"` 消息。
* **其块上不得有 `cache_control`。** 已清除的消息永远不会成为缓存键的一部分，因此其上的断点永远无法匹配。请像示例那样，把断点放在前一个 user turn 的最后一个块上。顶层 [自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) 字段在选取断点时会跳过限定当前 turn 的消息。在清除某条消息的那次请求上，可复用的已缓存前缀结束于它之前的 user turn，因此只有该消息与新 user 消息之间的那一个 assistant turn 会被重新处理。
* **放置规则仍然适用**，无论是否已清除。限定当前 turn 的消息必须跟在 `user` turn（或以 server tool result 结尾的 `assistant` turn）之后，并位于 `assistant` turn 之前或作为数组的结尾，与任何会话中途的 system message 一样。作为数组结尾的那条始终会渲染。直接后跟另一条 `user` 消息的则是 400 错误，而不是已清除的消息：把一轮工具的所有结果放在一条 user 消息中，提醒放在其后。
* **Assistant turn 不会清除它。** 该消息之后的预填充或 [paused](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons#pause-turn) assistant turn，或服务端工具循环，都不会添加 user 消息，因此该消息在那次续写上仍会渲染。要在客户端工具循环中让提醒保持可见，请在每条 `tool_result` 消息之后再次追加它。
* **Token 计数跟随渲染内容。** 已清除的消息不会增加 `usage.input_tokens`，也不会增加 [token 计数](https://platform.claude.com/docs/en/build-with-claude/token-counting)。
* **导入的历史。** 在你一次性构建的转录中（few-shot 示例、迁移过来的对话），一条其后已经有 assistant turn 和 user 消息的限定当前 turn 的消息，会从第一次请求起就被清除，并且从不渲染。这对你要沿用的按 turn 提醒来说是正确状态。仅在模型应在每次请求中都看到的消息上不设置 `clear_at`。

校验错误如下：

```text wrap
messages.3.clear_at: Extra inputs are not permitted
messages.3.clear_at: clear_at is only permitted on role 'system' messages
messages.3.clear_at: Input should be 'next_user_message' or 'never'
messages.3: a turn-scoped system message supports text blocks only (clear_at: 'next_user_message')
messages.3: output_config is not permitted on a turn-scoped system message (clear_at: 'next_user_message')
messages.3.content.0: cache_control is not permitted on a turn-scoped system message (clear_at: 'next_user_message')
```

第一条是未带 beta header 时返回的错误。在 Amazon Bedrock 和 Google Cloud 上，按 [Beta headers](https://platform.claude.com/docs/en/api/beta-headers) 中的说明传递 beta 值。

通过 SDK，在 `messages` 中的 `role: "system"` 条目上设置 `clear_at` 并发送 beta header。以下示例在 user turn 之后追加一条限定当前 turn 的提醒；在下一次请求中，一旦存在更后的 user 消息，该提醒仍留在数组中但不再渲染：

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  response = client.beta.messages.create(
      model="claude-fable-5-1",
      max_tokens: 4096,
      messages=[
          {
              "role": "user",
              "content": "Draft a short status update on the database migration for the team channel.",
          },
          # Turn-scoped reminder: renders for this turn, then clears once a later user message exists.
          {
              "role": "system",
              "clear_at": "next_user_message",
              "content": "The reader is on call: keep this reply under 50 words.",
          },
      ],
      betas=["mid-conversation-system-clear-at-2026-08-21"],
  )

  for block in response.content:
      if block.type == "text":
          print(block.text)
  ```

</CodeGroup>

## 与 Prompt Caching 结合使用

会话中途的 system messages 与 [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 被设计为一起使用：

* **显式启用缓存。** 仅当请求包含 `cache_control` 时才会发生缓存，可以是顶层 [自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) 字段，或内容块上的 [显式断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)。会话中途的 system message 本身不会创建缓存条目，未启用缓存时也就没有可保留的节省。
* **照常缓存稳定前缀。** 将 `cache_control` 放在跨请求保持不变的最后一个块上，无论那是顶层 `system` 字段的末尾、工具定义的末尾，还是消息历史中的某个稳定点。
* **在断点之后追加 system message。** 因为它位于已缓存的前缀之后，不会改变前缀哈希，缓存仍然命中。
* **会话中途的 system message 本身也可缓存。** 一旦它进入对话，就成为稳定历史的一部分。在下一个 turn，你可以把缓存断点移到它之后（或依赖 [自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) 来完成），该 system message 就会像任何其他 turn 一样从缓存中读取。

避免编辑或删除已经发送的会话中途的 system message。与对更早消息的任何其他更改一样，这会使缓存从该点起失效。在 Claude Fable 5.1 上，它还会使之后每个 assistant turn 中的 [thinking 块](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation) 失效。对于只应适用于一个 turn 的指引，请使用 [限定当前 turn 的 system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#turn-scoped-system-messages) 并保持其原位。如果指令需要演进，请追加一条新的 system message，而不是改写旧的。连续的 system messages 会被接受并视为单个 system 区段，该区段作为整体遵循相同的放置规则。

## 限制

* **不能作为第一条消息。** 携带内容的 `system` 消息不能是 `messages` 中的第一项。对于从一开始就适用的指令，请使用顶层 `system` 字段。
* **放置位置受约束。** 携带内容（`text`、`tool_addition` 或 `tool_removal` 块）的 `system` 消息必须紧跟在 `user` turn（包括携带 `tool_result` 块的 `user` turn）或以 server tool result 结尾的 `assistant` turn 之后，并且必须位于 `assistant` turn 之前或作为数组的结尾。它不能位于 `tool_use` 块与其 `tool_result` 之间。放在其他位置会返回 400 错误。有一个例外：`tool_addition` 和 `tool_removal` 块不被接受紧跟在 [paused](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons#pause-turn) 的 `assistant` turn（以 server tool result 结尾的 turn）之后，但 `text` 块可以；请先恢复 paused 的 turn，然后在下一条 `system` 消息中发送工具变更。`content` 为空、仅设置 [`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta) 的消息在其位置不渲染任何内容，并且可被接受在 `messages` 中的任何位置，包括第一条，或位于 `assistant` turn 与 `user` turn 之间。连续的 `system` 消息会被一起判断，因此在仅含 effort 的消息旁边添加一条携带文本的消息，会使整组遵循内容规则。
* **限定当前 turn 的消息仅限文本，并逐字原样重新发送。** `clear_at: "next_user_message"` 消息不携带 `tool_addition`、`tool_removal`、`output_config` 或 `cache_control`，一旦已清除，它必须在后续请求中逐字节相同地留在 `messages` 中。参见 [限定当前 turn 的 system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#turn-scoped-system-messages)。
* **不是放置不受信任内容的地方。** Claude 将 system 内容视为操作者指令并遵循它。不要将来自对话之外的文本（例如原始工具输出、检索到的文档或网页内容）直接放在 system message 中；这样做会赋予该文本操作者级别的权限。将这些数据放在 `tool_result` 块中，并继续遵循 [缓解 jailbreak 与 prompt injection](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks)。

## 相关内容

<CardGroup cols={2}>
  <Card title="Prompt Caching" icon="bolt" href="https://platform.claude.com/docs/en/build-with-claude/prompt-caching">
    缓存如何工作、断点放在哪里，以及如何读取缓存用量字段。
  </Card>

  <Card title="缓存诊断" icon="magnifying-glass" href="https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics">
    当预期的缓存命中未发生时，查明两条请求究竟在何处分叉。
  </Card>

  <Card title="使用 Messages API" icon="message" href="https://platform.claude.com/docs/en/build-with-claude/working-with-messages">
    消息结构、多轮对话以及 `system` 字段。
  </Card>

  <Card title="Prompt 最佳实践" icon="text" href="https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices">
    编写有效的 prompt 和 system 指令。
  </Card>

  <Card title="在 Claude 中使用工具" icon="wrench" href="https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview">
    `tool_use` 和 `tool_result` 块在 `messages` 数组中的结构。
  </Card>
</CardGroup>
