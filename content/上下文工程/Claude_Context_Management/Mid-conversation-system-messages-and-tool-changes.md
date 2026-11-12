+++
title = "Mid-conversation-system-messages-and-tool-changes"
slug = "mid-conversation-system-messages-and-tool-changes"
weight = 40
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "Mid-conversation-system-messages-and-tool-changes相关学习笔记与实践要点。"
+++
# Mid-conversation system messages and tool changes

Change system instructions or tool availability partway through a conversation without invalidating the cached prefix that came before them.
在不使缓存失效的情况下,更改系统指令或者工具可用性
system instructions normally live in the top-level system field
it is great for prompt caching: because it is stable prefix
Mid-conversation system message  will not change the cached prefix ,and you append a {"role": "system"},and this instruction is still applied ad system instruction rather than as a ordinary user text

## Mid-conversation tool changes

The tools array sets even earlier than  the top-level system field.
so editing it will make the whole cache invalided 

Mid-conversation tool changes use **tool_addition** and **tool_removal** to offer a tool to model or withdraw it from a specific point in the conversation onward. The tool array never changes , so the prefix stays the same.

**tool_addition** and **tool_removal** are content blocks in the **content** array of **role : "system"** message and they can be mixed with text blocks
The message follows the same placement rules as any mid-conversation system message 

Each block's `tool` field **references** a tool rather than **defining** one: `{"type": "tool_reference", "name": "..."}` names a tool declared in the request's `tools` array, and [MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector) tools can be referenced individually with `mcp_tool_reference` (`server_name` and `name`) or as a whole toolset with `mcp_toolset_reference` (`server_name`). Referencing a name that is not declared in `tools` returns a 400 error.

可以使用defer_loading: true 来使得在tools offer的tool暂时隐藏,知道tool_addition激活它
并且tool_addition可以重新提供之前被 tool_removalde撤回的tool

```
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

1. 是role: system的content块
2. parameter: tool_reference  instead of tool_name

## When to use a mid-conversation system message

prompt caching hashes the requests prefix in order: tools,system,message
Mid-conversation system let you add the instruction at the **end** of the message history instead great for matching the unchanged parts

A few situations where this matters:(随便看看就行)

- **Mid-session policy or persona changes.** A long agentic session needs a new constraint ("from now on, write all SQL as parameterized queries") after dozens of cached turns. Adding it to the top-level `system` field would re-process the entire history.
- **Per-turn context that must be authoritative.** You want to inject a freshness note, a session deadline, or a tool-availability change with system-level weight, and it changes too often to live in the cached prefix.
- **Per-turn reminders that shouldn't pile up.** A harness nudges the model after each batch of tool results ("request independent reads together", "the user hasn't heard from you in a while") and wants the model to see only the newest copy. A [turn-scoped system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#turn-scoped-system-messages) renders for one turn and then costs nothing, without deleting anything from the history.
- **State changes your application observes.** Your application notices something Claude should treat as an operator-level fact: files changed on disk, the user toggled an auto-approve setting, available tools changed, or the remaining token budget dropped below a threshold.
- **User input that should not interrupt an agentic loop.** A user types a follow-up while Claude is still executing tools for the previous request. Relaying it as a system message after the next tool result lets Claude fold the new input into the work it is already doing, instead of treating it as a fresh request to switch to. See [Placement after tool results](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#placement-after-tool-results).
- **Mode switches that grant standing permissions.** A session-level mode can use a mid-conversation system message to grant standing consent to an expensive capability, such as automatically launching multiagent workflows, with a short refresher every several turns and an exit notice when the mode is turned off. For a worked example, see [Build an orchestration mode](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-effort-example).

A mid-conversation system message keeps that operator-level priority without paying the cache-miss cost of editing the top-level `system` field.

## How it works

Add a message with "role" : "system" to the message array
Use a plain string or content blocks for content , the same as a user or assistant turn.

when the later and the earlier conflict, the later will precedence the earlier
mid-conversation system messages take precedence over the top-level `system` field for the turns that follow them

The position:
A mid-conversation system message must immediately follow a `user` turn (or an `assistant` turn ending in a server tool result), and must either be the last entry in `messages` or be immediately followed by an `assistant` turn.
Any other position, including between an `assistant` `tool_use` block and the `tool_result` that answers it, returns a 400 error.

### Placement after tool results

Phrase the system content as context rather than as a command that overrides the user. State the fact ("new input arrived from the user: X", "the remaining token budget is now Y") and let Claude act on it. Claude is trained to resist instructions that appear to work against the user, and that protection still applies to the system role, so language such as "ignore what the user said" is less effective than stating what changed.

### Turn-scoped system messages

要让有个role: system消息只作用与当前伦茨,可以设置它的clear_at,它的两个可选值:
"never":默认值,该小心会包含在它的每一次请求中
next_user_message:限定为当前伦茨的turn-scope,只有当它后面没有role: user的消息是,其文本才会被渲染
而一个只包含tool_result block的用户小心也会被视为role: user消息
一旦后面出现了用户消息,他就会被清楚:它仍然保留在message array但是不会被渲染也不会被计入input_token

主要用途是在 tool loop中提供每一轮次的提醒,这个可以从上面那个(而一个只包含tool_result block的用户小心也会被视为role: user消息)特性进行设计

模型只能看到最后一个user message后的副本,因此消息不会叠加

```
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

Rules for turn-scoped messages:

- **Re-send cleared messages verbatim.** A cleared message is still part of the conversation history. Rebuilding it from current state (a fresh token count, a timestamp), dropping it as redundant, or changing its `clear_at` value is an edit to an earlier message. The prompt cache misses from that point, and on Claude Fable 5.1 every thinking block produced after it fails the [conversation check](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-in-conversation).
- **Text only.** `content` is one or more `text` blocks (or a string). `tool_addition` and `tool_removal` blocks return a 400 error on a turn-scoped message, and so does `output_config`. Use a separate `role: "system"` message without `clear_at` for those.
- **No `cache_control` on its blocks.** A cleared message is never part of a cache key, so a breakpoint on it could never match. Put the breakpoint on the last block of the preceding user turn instead, as the example does. The top-level [automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) field skips turn-scoped messages when it picks a breakpoint. On the request that clears a message, the reusable cached prefix ends at the user turn before it, so only the one assistant turn between that message and the new user message is reprocessed.
- **Placement rules still apply**, cleared or not. A turn-scoped message must follow a `user` turn (or an `assistant` turn ending in a server tool result) and precede an `assistant` turn or end the array, like any mid-conversation system message. One that ends the array always renders. One followed directly by another `user` message is a 400 error, not a cleared message: put all of a tool round's results in one user message and the reminders after it.
- **Assistant turns don't clear it.** A prefilled or [paused](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons#pause-turn) assistant turn after the message, or a server-side tool loop, adds no user message, so the message still renders on that continuation. To keep a reminder in view through a client-side tool loop, append it again after each `tool_result` message.
- **Token counting follows what renders.** A cleared message adds nothing to `usage.input_tokens` or to a [token count](https://platform.claude.com/docs/en/build-with-claude/token-counting).
- **Imported history.** In a transcript you construct in one step (few-shot examples, a migrated conversation), a turn-scoped message that already has an assistant turn and a user message after it is cleared from the first request and never renders. That is the right state for a per-turn reminder you are carrying over. Leave `clear_at` unset only on a message the model should see on every request.

## Combining with prompt caching

对话中途的系统消息（Mid-conversation system messages）与[提示缓存（prompt caching）](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)是专门设计为可以结合使用的：

- **显式启用缓存。** 只有当请求中包含 `cache_control` 时才会发生缓存，这可以是顶层的[自动缓存（automatic caching）](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)字段，也可以是内容块上的[显式缓存断点（explicit breakpoint）](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)。对话中途的系统消息本身不会自动创建缓存条目；如果没有启用缓存，也就没有可以保留的缓存收益。
- **像往常一样缓存稳定前缀。** 将 `cache_control` 放在跨请求保持不变的最后一个内容块上。这个位置可以是顶层 `system` 字段的末尾、工具定义的末尾，或者消息历史中的某个稳定位置。
- **将系统消息追加在缓存断点之后。** 因为它位于已经缓存的前缀之后，所以不会改变前缀的哈希值，缓存仍然可以命中。
- **对话中途的系统消息本身也可以被缓存。** 一旦它进入对话，就会成为稳定历史的一部分。下一轮请求中，你可以将缓存断点向后移动到该系统消息之后（或者依赖[自动缓存（automatic caching）](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)自动将断点移动到那里），这样该系统消息就会像其他对话轮次一样从缓存中读取。

## Limitations

- **Not for the first message.** A `system` message that carries content cannot be the first entry in `messages`. Use the top-level `system` field for instructions that apply from the very start.
- **Placement is constrained.** A `system` message that carries content (`text`, `tool_addition`, or `tool_removal` blocks) must immediately follow a `user` turn (including a `user` turn that carries `tool_result` blocks) or an `assistant` turn ending in a server tool result, and must precede an `assistant` turn or end the array. It cannot sit between a `tool_use` block and its `tool_result`. Placing it elsewhere returns a 400 error. One exception: `tool_addition` and `tool_removal` blocks are not accepted immediately after a [paused](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons#pause-turn) `assistant` turn (one ending in a server tool result), though `text` blocks are; resume the paused turn first, then send the tool change in the next `system` message. A message with empty `content` that only sets [`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta) renders nothing at its position and is accepted anywhere in `messages`, including first or between an `assistant` turn and a `user` turn. Consecutive `system` messages are judged together, so adding a text-carrying message next to an effort-only one makes the whole group follow the content rule.
- **Turn-scoped messages are text-only and re-sent verbatim.** A `clear_at: "next_user_message"` message carries no `tool_addition`, `tool_removal`, `output_config`, or `cache_control`, and once cleared it must stay in `messages` byte-for-byte on later requests. See [Turn-scoped system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#turn-scoped-system-messages).
- **Not a place for untrusted content.** Claude treats system content as operator instructions and follows it. Do not place text from outside the conversation, such as raw tool output, retrieved documents, or web content, directly in a system message; doing so gives that text operator-level authority. Keep that data in `tool_result` blocks and continue to follow [Mitigate jailbreaks and prompt injections](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks).