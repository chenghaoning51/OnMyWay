+++
title = "Mid-conversation"
slug = "mid-conversation"
weight = 50
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "Mid-conversation相关学习笔记与实践要点。"
+++
# Mid-conversation system messages and tool changes

> 原文：[Mid-conversation system messages and tool changes](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)

在对话进行到一半时更改 system 指令或工具可用性，同时不使此前已缓存的 prefix 失效。

> 关于 zero data retention (ZDR) 如何适用于本功能，参见 [API and data retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)。

System 指令通常放在顶层 `system` 字段中，位于对话里所有 message 之前。这个位置非常适合 [prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)：system prompt 属于稳定的 prefix，因此后续 turn 可以命中 cache。但如果你是在会话进行到一半才发现需要某条指令，这个位置就不合适了——因为修改顶层 `system` 字段会改变 prompt 的最开头，从而使其后全部内容的 cache 失效。

Mid-conversation system messages 补上了这个缺口。你不再去改顶层 `system` 字段，而是在新指令开始生效的那个对话位置，追加一条 `{"role": "system"}` message。cached prefix 保持不变，下一次请求仍会从 cache 读取它；同时，新指令仍按 system instruction 生效，而不是普通的 user 文本。

> Mid-conversation system messages 可用于 Claude API、[Claude in Amazon Bedrock](https://platform.claude.com/docs/en/build-with-claude/claude-in-amazon-bedrock) 以及 [Google Cloud](https://platform.claude.com/docs/en/build-with-claude/claude-on-vertex-ai)。
>
> 该功能适用于 Claude Fable 5.1、[Claude Mythos 5.1](https://anthropic.com/glasswing)、Claude Fable 5、[Claude Mythos 5](https://anthropic.com/glasswing)、Claude Opus 4.8 和 Claude Opus 5。使用 mid-conversation system messages **不需要** beta header。Claude Sonnet 5 不支持此功能，请改用顶层 `system` 字段。
>
> [Mid-conversation tool changes](#mid-conversation-tool-changes) 目前处于 beta，需要 `mid-conversation-tool-changes-2026-07-01` 这个 beta header。可用模型与平台同上：Claude API、Amazon Bedrock 和 Google Cloud。
>
> [Turn-scoped system messages](#turn-scoped-system-messages)（`clear_at`）目前处于 beta，需要 `mid-conversation-system-clear-at-2026-08-21` 这个 beta header；可用模型与平台与 mid-conversation system messages 相同。

## Mid-conversation tool changes

`tools` 数组在 hashed request prefix 中的位置比顶层 `system` 字段还要靠前，因此改动它会使整段对话的 [prompt cache](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 失效。Mid-conversation tool changes 是 mid-conversation system messages 在工具侧的对应能力：不必把工具列表在整段对话生命周期内写死，而是可以在 turn 与 turn 之间改变向模型提供哪些工具——先在 `tools` 里一次性声明完整工具集，再通过 `tool_addition` 和 `tool_removal` 这两个 block，从对话中的某个位置起向模型提供某工具，或将其撤回。`tools` 数组本身始终不变，因此 cached prefix 保持完好。

`tool_addition` 和 `tool_removal` 是 `role: "system"` message 的 `content` 数组中的 content block，可以与同一条 message 里的 `text` block 混用。该 message 的放置规则与任意 mid-conversation system message 相同（参见 [Limitations](#limitations)），变更从该位置起向后生效。每个 block 的 `tool` 字段是**引用**工具，而不是**定义**工具：`{"type": "tool_reference", "name": "..."}` 指向请求 `tools` 数组中已声明的工具；[MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector) 工具可以用 `mcp_tool_reference`（`server_name` 和 `name`）逐个引用，也可以用 `mcp_toolset_reference`（`server_name`）引用整个 toolset。引用一个未在 `tools` 中声明的名字会返回 400 错误。

`tools` 中声明的每个工具从对话一开始就会提供给模型，除非声明时带上 `defer_loading: true`——后者会把它扣住，直到某条 `tool_addition` block 把它亮出来。`tool_addition` 也可以重新提供此前被 `tool_removal` 撤回的工具。

> 原文示例覆盖 cURL / CLI / Python / TypeScript / C# / Go / Java / PHP / Ruby。下文以 Python 为代表；其余语言的请求结构相同。使用本功能时需带上 beta header `mid-conversation-tool-changes-2026-07-01`。

```python
client = anthropic.Anthropic()

response = client.beta.messages.create(
    model="claude-opus-5",
    max_tokens=1024,
    betas=["mid-conversation-tool-changes-2026-07-01"],
    # 完整工具集在一开始就声明，且之后不再改动，因此 cached prefix 保持完好。
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
        # 从这一位置起撤回 get_weather。该 block 按名字引用工具，而不是去改 `tools`，
        # 因此更早的 turn 仍逐字节相同，cache 仍然命中。
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

Mid-conversation tool changes 目前处于 beta。使用时请在请求中带上 beta header `mid-conversation-tool-changes-2026-07-01`。

## When to use a mid-conversation system message

[Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 按如下顺序对 request prefix 做哈希：先 `tools`，再 `system`，再 `messages`。要命中 cache，prefix 必须与最近一次请求**逐字节完全一致**，直到 cache breakpoint 为止。

这个顺序意味着顶层 `system` 字段几乎位于 hashed prefix 的最开头。对它的任何改动——哪怕只是追加一句话——都会得到不同的 hash，于是这次请求会 miss cache：system prompt 本身，以及其后所有已缓存的 message，都无法复用。

Mid-conversation system messages 让你把指令加在 message history 的**末尾**。新指令之前的一切都没有改动，因此已有的 cache entry 仍然匹配，只有这条新 message 会作为 fresh input 被处理。

以下几种情况尤其值得这样做：

* **会话中途的 policy 或 persona 变更。** 一段很长的 agentic session 已经缓存了几十个 turn，这时才需要加上新约束（例如 “from now on, write all SQL as parameterized queries”）。若把它写进顶层 `system` 字段，整段历史都要重新处理。
* **必须具备权威性的 per-turn 上下文。** 你想注入一条 freshness note、session deadline，或工具可用性变更，并且希望它带有 system 级别的权重；同时它变化太频繁，不适合放进 cached prefix。
* **不应越积越多的 per-turn reminder。** harness 在每批 tool result 之后提醒模型（例如 “request independent reads together”、“the user hasn't heard from you in a while”），并且希望模型只看到最新的那一份。[Turn-scoped system message](#turn-scoped-system-messages) 只在一个 turn 内渲染，之后不再消耗 token，也不必从 history 里删除任何内容。
* **应用层观察到的状态变化。** 你的应用注意到某些事实，希望 Claude 按 operator 级别对待：磁盘上的文件变了、用户切换了 auto-approve 设置、可用工具变了，或剩余 token budget 掉到阈值以下。
* **不应打断 agentic loop 的用户输入。** 用户在 Claude 仍在为上一次请求执行工具时输入了 follow-up。把它作为 system message 接在下一条 tool result 之后转发，可以让 Claude 把新输入并入正在进行的工作，而不是把它当成一次需要立刻切换过去的全新请求。参见 [Placement after tool results](#placement-after-tool-results)。
* **授予 standing permission 的 mode 切换。** 会话级 mode 可以用 mid-conversation system message 为某项昂贵能力授予 standing consent（持续性授权），例如自动启动 multiagent workflow；每隔若干 turn 发一条简短 refresher，mode 关闭时再发一条退出通知。完整示例见 [Build an orchestration mode](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-effort-example)。

上述所有情况，你也可以把指令放进普通 `user` message，而 Claude 确实会遵循出现在 user turn 中的指令。差别在于优先级：`user` message 被视为来自终端用户，`system` message 被视为来自你——应用的 operator。两者冲突时，system 指令优先。因此，对于即便终端用户提出不同要求也应继续成立的 operator 级事实与约束，请使用 `system` role。Mid-conversation system message 能保住这种 operator 级优先级，又不必付出改动顶层 `system` 字段所带来的 cache miss 成本。

## How it works

向 `messages` 数组追加一条 `"role": "system"` 的 message。`content` 可以用纯字符串，也可以用 content block，与 `user` 或 `assistant` turn 相同。该指令从对话中的这个位置起向后生效。指令冲突时，后出现的 system message 优先于更早的；对跟随其后的那些 turn 而言，mid-conversation system messages 也优先于顶层 `system` 字段。

对整段对话都应生效的指令，仍然可以写在顶层 `system` 字段。Mid-conversation system messages 留给那些稍后才变得相关的指令，或那些你希望追加、同时又不想让 cached prefix 失效的指令。

`role: "system"` message 还可以携带 `output_config.effort`，从下一个 `user` turn 起改变 [effort](https://platform.claude.com/docs/en/build-with-claude/effort) 级别。该能力在 Claude API 与 Google Cloud 上的 Claude Fable 5.1、Claude Mythos 5.1 和 Claude Opus 5 处于 beta，需要 `mid-conversation-output-config-2026-07-01` 这个 beta header。参见 [Per-message effort](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta)。

```python
client = anthropic.Anthropic()

response = client.messages.create(
    model="claude-opus-5",
    max_tokens=1024,
    # 自动 prompt caching：每次请求都会缓存截至目前的对话，
    # 下一次请求则从 cache 读取未改动的 prefix。
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
        # reviewer 在会话中途意识到：所有建议还必须满足团队严格的 typing 政策。
        # 把指令追加在这里，更早的 turn 仍逐字节相同，
        # 因此上一次请求缓存下来的 prefix 仍会从 cache 读取。
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

这个例子通过顶层 `cache_control` 字段启用了 [automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)。Prompt caching 是 opt-in 的：如果请求既没有 `cache_control` 字段（无论是 automatic，还是 [explicit breakpoint](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)），就不会有任何内容被缓存，每次请求都按常规 input token 价格为整段对话付费。启用 caching 后，追加这条 system message 不会改动已经缓存的那些 turn，因此携带新指令的那次请求仍会从 cache 读取它们，而不是重新处理。Caching 还要求对话达到 [minimum cacheable prompt length](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-limitations)；像上面这样短的例子会低于该阈值，所以在对话变长之前，`cache_creation_input_tokens` 和 `cache_read_input_tokens` 都会保持为 0。

一条 mid-conversation system message 必须紧跟在某个 `user` turn 之后（或紧跟在以 server tool result 结尾的 `assistant` turn 之后），并且它要么是 `messages` 的最后一项，要么紧跟着一个 `assistant` turn。携带 `tool_result` block 的 `user` message 也算：在 agentic loop 中，你可以把 system message 紧接在 tool result 之后、Claude 的下一 turn 之前。任何其他位置——包括夹在 `assistant` 的 `tool_use` block 与回答它的 `tool_result` 之间——都会返回 400 错误。

### Placement after tool results

在 [agentic loop](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview) 中，system message 应放在投递 tool result 的那条 `user` message 之后。你的应用也可以在这里转发用户在 Claude 工作期间输入的内容，从而在不重启当前 turn 的情况下吸收新上下文：

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

把 system content 写成**上下文**，而不是一条覆盖用户意图的命令。陈述事实（“new input arrived from the user: X”、“the remaining token budget is now Y”），然后让 Claude 据此行动。Claude 被训练为抵制那些看起来与用户作对的指令，这种保护对 system role 同样生效，因此 “ignore what the user said” 这类措辞，效果不如直接说明发生了什么变化。

这种模式用于转发**本段对话终端用户**的输入。不要用它传递 tool output、检索到的文档或其他第三方内容；那些内容应放在 `tool_result` block 中（参见 [Limitations](#limitations)）。

### Turn-scoped system messages

若要把一条 `role: "system"` message 限定在当前 turn，设置它的 `clear_at` 字段。该字段只有两个取值：

* `"never"`（默认）：只要请求里包含这条 message，它就会在其所在位置渲染。省略该字段效果相同。
* `"next_user_message"`：这条 message 是 **turn-scoped** 的。只有当 `messages` 中它后面还没有 `role: "user"` message 时，其文本才会被渲染。这里，只携带 `tool_result` block 的 user message 也算 user message。一旦后面出现了更新的 user message，该条就会被 **cleared**：它仍留在数组中，但不再渲染任何内容，也不再消耗 input token——本次请求以及之后每一次都是如此。

Turn-scoped system messages 目前处于 beta。请带上 [beta header](https://platform.claude.com/docs/en/api/beta-headers) `mid-conversation-system-clear-at-2026-08-21`。不带该 header 时，`clear_at` 会被当作未知字段而拒绝。

```json
{
  "role": "system",
  "clear_at": "next_user_message",
  "content": "First privately list what you need next; then request every item that doesn't depend on another's result in this one response."
}
```

主要用途是 tool loop 中的 per-turn reminder。每次希望模型看到这条提醒时，就把它追加在 `tool_result` message 之后，更早的副本原样留着。模型只会看到位于最后一条 user message 之后的那些副本，因此 reminder 不会越积越多。`messages` 中更早的内容没有任何改动，所以 [prompt cache](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 仍然匹配。在 Claude Fable 5.1 上，这样做还能让后续 [thinking block 保持有效](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation)：删除更早的 reminder 会改变那些 block 之前的对话，导致 conversation check 失败；而被 cleared 的 message 仍留在数组中，对话保持不变。

下面这次请求是 agent loop 中较后的一步。`messages[3]` 在更早的那次请求中被渲染过，当时它是数组的最后一项。一旦存在 `messages[5]`（一条更后的 user message），`messages[3]` 就被 cleared：cleared message 仍留在数组中，因此 `messages[4]` 里 thinking block 之前的对话没有变化，但模型不再看到它的文本。`messages[6]` 和 `messages[7]` 都会按顺序渲染。

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

Turn-scoped message 的规则：

* **按原文原样重新发送已 cleared 的 message。** 一条 cleared message 仍是 conversation history 的一部分。按当前状态重建它（新的 token 计数、时间戳）、因为它冗余而丢掉它、或改它的 `clear_at` 值，都等于在编辑更早的 message。Prompt cache 会从该点起 miss；在 Claude Fable 5.1 上，它之后产生的每一个 thinking block 都会通不过 [conversation check](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation)。
* **只允许文本。** `content` 是一个或多个 `text` block（或字符串）。在 turn-scoped message 上使用 `tool_addition`、`tool_removal` 会返回 400 错误，`output_config` 同样不行。这些内容请用另一条不带 `clear_at` 的 `role: "system"` message。
* **其 block 上不能带 `cache_control`。** Cleared message 从不参与 cache key，因此打在它上面的 breakpoint 永远无法匹配。请像示例那样，把 breakpoint 放在前一个 user turn 的最后一个 block 上。顶层 [automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) 字段在选择 breakpoint 时会跳过 turn-scoped message。在把某条 message cleared 掉的那次请求上，可复用的 cached prefix 止于它之前的那个 user turn，因此只有「该 message 与新的 user message 之间」那一个 assistant turn 会被重新处理。
* **放置规则始终生效**，无论是否已被 cleared。Turn-scoped message 必须跟在 `user` turn 之后（或以 server tool result 结尾的 `assistant` turn 之后），并且位于 `assistant` turn 之前或作为数组末项，与任意 mid-conversation system message 相同。位于数组末尾的那一条始终会渲染。若它后面直接跟另一条 `user` message，得到的是 400 错误，而不是一条 cleared message：请把同一轮 tool 的全部 result 放进**一条** user message，再把 reminder 接在它后面。
* **Assistant turn 不会把它 cleared。** 该 message 之后若是一条 prefilled 或 [paused](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons#pause-turn) 的 assistant turn，或一次 server-side tool loop，都不会新增 user message，因此在那次续写上它仍会渲染。若要在 client-side tool loop 中让 reminder 持续可见，请在每条 `tool_result` message 之后再追加一次。
* **Token 计数以实际渲染为准。** Cleared message 不会计入 `usage.input_tokens`，也不会计入 [token count](https://platform.claude.com/docs/en/build-with-claude/token-counting)。
* **导入的 history。** 若你一次性构造整份 transcript（few-shot 示例、迁移过来的对话），一条 turn-scoped message 后面如果已经既有 assistant turn 又有 user message，那么从第一次请求起它就是 cleared 的，永远不会渲染。对于你正在沿用的 per-turn reminder，这正是正确状态。只有希望模型在每次请求都看到的 message，才不要设置 `clear_at`。

校验错误如下：

```text
messages.3.clear_at: Extra inputs are not permitted
messages.3.clear_at: clear_at is only permitted on role 'system' messages
messages.3.clear_at: Input should be 'next_user_message' or 'never'
messages.3: a turn-scoped system message supports text blocks only (clear_at: 'next_user_message')
messages.3: output_config is not permitted on a turn-scoped system message (clear_at: 'next_user_message')
messages.3.content.0: cache_control is not permitted on a turn-scoped system message (clear_at: 'next_user_message')
```

第一条是未带 beta header 时返回的错误。在 Amazon Bedrock 和 Google Cloud 上，按 [Beta headers](https://platform.claude.com/docs/en/api/beta-headers) 所述传入 beta 值。

通过 SDK 使用时，在 `messages` 里那条 `role: "system"` 条目上设置 `clear_at`，并发送 beta header。下面的例子在 user turn 之后追加一条 turn-scoped reminder；下一次请求中，一旦出现更后的 user message，这条 reminder 仍留在数组里，但不再渲染：

```python
client = anthropic.Anthropic()

response = client.beta.messages.create(
    model="claude-fable-5-1",
    max_tokens=4096,
    messages=[
        {
            "role": "user",
            "content": "Draft a short status update on the database migration for the team channel.",
        },
        # Turn-scoped reminder：本 turn 会渲染；一旦后面出现更新的 user message，就会被 cleared。
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

## Combining with prompt caching

Mid-conversation system messages 与 [prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 就是为一起使用而设计的：

* **显式启用 caching。** 只有请求包含 `cache_control` 时才会发生 caching——可以是顶层 [automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) 字段，也可以是某个 content block 上的 [explicit breakpoint](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)。Mid-conversation system message 本身不会创建 cache entry；若不启用 caching，也就没有可保全的节省。
* **照常缓存稳定的 prefix。** 把 `cache_control` 放在跨请求保持不变的最后一个 block 上，无论那是顶层 `system` 字段的末尾、工具定义的末尾，还是 message history 中某个稳定位置。
* **把 system message 追加在 breakpoint 之后。** 因为它位于 cached prefix 之后，不会改变 prefix hash，cache 仍然命中。
* **Mid-conversation system message 本身也可被缓存。** 一旦它进入对话，就成为稳定 history 的一部分。下一 turn 你可以把 cache breakpoint 移过它（或依赖 [automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) 自动前移），这条 system message 就会像其他 turn 一样从 cache 读取。

避免编辑或删除已经发送过的 mid-conversation system message。与改动更早的任意 message 一样，这会从该点起使 cache 失效。在 Claude Fable 5.1 上，它还会使之后每一个 assistant turn 中的 [thinking block](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation) 失效。只应对单个 turn 生效的指导，请使用 [turn-scoped system message](#turn-scoped-system-messages)，并把它留在原位。若指令需要演进，请追加一条新的 system message，而不是改写旧的。连续的 system message 会被接受，并视为同一个 system section，整体仍遵循同一套放置规则。

## Limitations

* **不能作为第一条 message。** 携带 content 的 `system` message 不能是 `messages` 的第一项。从一开始就应生效的指令，请使用顶层 `system` 字段。
* **放置位置受限。** 携带 content（`text`、`tool_addition` 或 `tool_removal` block）的 `system` message 必须紧跟在 `user` turn 之后（包括携带 `tool_result` block 的 `user` turn），或紧跟在以 server tool result 结尾的 `assistant` turn 之后，并且必须位于 `assistant` turn 之前或作为数组末项。它不能夹在 `tool_use` block 与对应的 `tool_result` 之间。放在其他位置会返回 400 错误。有一个例外：`tool_addition` 和 `tool_removal` block **不能**紧接在 [paused](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons#pause-turn) 的 `assistant` turn（即以 server tool result 结尾的那条）之后，尽管 `text` block 可以；请先恢复被 pause 的 turn，再在下一条 `system` message 中发送工具变更。一条 `content` 为空、只设置 [`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta) 的 message 在其所在位置不渲染任何内容，可以出现在 `messages` 的任意位置，包括第一项，或夹在 `assistant` turn 与 `user` turn 之间。连续的 `system` message 会被一并判定，因此若在一条仅含 effort 的 message 旁边再加一条带文本的 message，整组都会按「带 content」的规则处理。
* **Turn-scoped message 只能是文本，且必须按原文原样重发。** `clear_at: "next_user_message"` 的 message 不能携带 `tool_addition`、`tool_removal`、`output_config` 或 `cache_control`；一旦被 cleared，后续请求必须把它逐字节原样留在 `messages` 中。参见 [Turn-scoped system messages](#turn-scoped-system-messages)。
* **不要放入不可信内容。** Claude 把 system content 当作 operator 指令并会遵循它。不要把对话之外的文本——例如原始 tool output、检索到的文档或网页内容——直接放进 system message；那样会赋予这些文本 operator 级权威。把那些数据放在 `tool_result` block 中，并继续遵循 [Mitigate jailbreaks and prompt injections](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks)。

## Related

| 文档 | 说明 |
| --- | --- |
| [Prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) | Caching 如何工作、breakpoint 放在哪里，以及如何读取 cache usage 字段。 |
| [Cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics) | 当预期的 cache hit 没有发生时，精确定位两次请求从哪里开始分叉。 |
| [Using the Messages API](https://platform.claude.com/docs/en/build-with-claude/working-with-messages) | Message 结构、多轮对话，以及 `system` 字段。 |
| [Prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) | 如何写有效的 prompt 与 system 指令。 |
| [Tool use with Claude](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview) | `tool_use` 与 `tool_result` block 在 `messages` 数组中的结构。 |
