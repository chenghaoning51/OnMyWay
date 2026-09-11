+++
title = 'Context Management · Compaction'
slug = "context-compaction"
date = 2026-09-06T00:00:00+08:00
lastmod = 2026-09-06T00:00:00+08:00
weight = 2
categories = ['上下文工程']
tags = ['Context Engineering', 'Claude']
description = 'Claude 的 Server-side Compaction：自动压缩会话上下文以突破窗口限制。'
+++

# Compaction

Server-side context compaction for managing long conversations that approaching context window limits

```
Server-side compaction is the recommended strategy for managing context in long-running conversations and agentic workflows. It handles context management automatically, without client-side summarization code.
```

as a conversation grows, response quality degrades,Compaction extends the effective context length for long-running conversations and tasks
compaction replaces older content with a concise summary.

This is ideal for:

- Chat-based, multi-turn conversations where you want users to use one chat for a long period of time
- Task-oriented prompts that require a lot of follow-up work (often tool use) that might exceed the context window

## How compaction works

four steps:

1. Detects when input tokens reach your specified trigger threshold.
2. Generates a summary of the current conversation.
3. Creates a `compaction` block containing the summary.
4. Continues the response with the compacted context.

## Basic usage

Enable compaction by adding the `compact_20260112` strategy to `context_management.edits` in your Messages API request.


## Parameters

| Parameter                | Type    | Default                                     | Description                                                  |
| :----------------------- | :------ | :------------------------------------------ | :----------------------------------------------------------- |
| `type`                   | string  | Required                                    | Must be `"compact_20260112"`                                 |
| `trigger`                | object  | `{"type": "input_tokens", "value": 150000}` | When to trigger compaction. `input_tokens` is the only supported trigger type. `value` must be at least 50,000 tokens. |
| `pause_after_compaction` | boolean | `false`                                     | Whether to pause after generating the compaction summary     |
| `instructions`           | string  | `null`                                      | Custom summarization prompt. Completely replaces the default prompt when provided. |

ps:
type must be "compact_20260112":
if u use Claude API, for sure; but if u def your own compaction function, it change use other value

## Trigger configuration

```
client = anthropic.Anthropic()
messages = [{"role": "user", "content": "Hello, Claude"}]
response = client.beta.messages.create(
    betas=["compact-2026-01-12"],
    model="claude-opus-5",
    max_tokens=4096,
    messages=messages,
    context_management={
        "edits": [
            {
                "type": "compact_20260112",
                "trigger": {"type": "input_tokens", "value": 150000},
            }
        ]
    },
)
```

## Custom summarization instructions

/compaction <instruction>

default instructions:

```
You have written a partial transcript for the initial task above. Please write a summary of the transcript. The purpose of this summary is to provide continuity so you can continue to make progress towards solving the task in a future context, where the raw history above may not be accessible and will be replaced with this summary. Write down anything that would be helpful, including the state, next steps, learnings etc. You must wrap your summary in a <summary></summary> block.
```

Custom instructions don't supplement the default prompt. They replace it completely

On Claude Fable 5.1 and Claude Mythos 5.1, a request with custom `instructions` summarizes from the visible conversation only: earlier thinking blocks are not part of the summarizer's input.

## Pausing after compaction

Use `pause_after_compaction` to pause the API after generating the compaction summary. This allows you to add additional content blocks 

```
 context_management={
        "edits": [{"type": "compact_20260112", "pause_after_compaction": True}]
    }
```

## Enforce a total token budget

When a model works on long tasks with many tool-use iterations, total token consumption can grow significantly. You can combine `pause_after_compaction` with a compaction counter to estimate cumulative usage and gracefully wrap up the task once a budget is reached.

This example appears in the SDK languages only: its value is the budget-tracking logic around the request. The raw request combines the `trigger` from [Trigger configuration](https://platform.claude.com/docs/en/build-with-claude/compaction#trigger-configuration) with `pause_after_compaction` from [Pausing after compaction](https://platform.claude.com/docs/en/build-with-claude/compaction#pausing-after-compaction).

```
client = anthropic.Anthropic()
messages = [{"role": "user", "content": "Hello, Claude"}]
TRIGGER_THRESHOLD = 100_000
TOTAL_TOKEN_BUDGET = 3_000_000
n_compactions = 0

response = client.beta.messages.create(
    betas=["compact-2026-01-12"],
    model="claude-opus-5",
    max_tokens=4096,
    messages=messages,
    context_management={
        "edits": [
            {
                "type": "compact_20260112",
                "trigger": {"type": "input_tokens", "value": TRIGGER_THRESHOLD},
                "pause_after_compaction": True,
            }
        ]
    },
)

if response.stop_reason == "compaction":
    n_compactions += 1
    messages.append({"role": "assistant", "content": response.content})

    # Estimate total tokens consumed; prompt wrap-up if over budget
    if n_compactions * TRIGGER_THRESHOLD >= TOTAL_TOKEN_BUDGET:
        messages.append(
            {
                "role": "user",
                "content": "Please wrap up your current work and summarize the final state.",
            }
        )
```

pause能够允许用户能够塞入自己的判断逻辑,防止超过总预算但是task未停止

## Working with compaction blocks

When compaction is triggered, the API returns a `compaction` block at the start of the assistant response.
The new compaction block will replace the old one

### Passing compaction blocks back

You must pass the `compaction` block back to the API on subsequent requests to continue the conversation with the shortened prompt. 

When the API receives a `compaction` block, **all content blocks before it are ignored**. You can either:

- Keep the original messages in your list and let the API handle removing the compacted content
- Manually drop the compacted messages and only include the compaction block onwards

### Streaming

The compaction block streams differently from text blocks. You receive a `content_block_start` event, followed by a single `content_block_delta` with the complete summary content (no intermediate streaming), and then a `content_block_stop` event.

content_block_start -> content_block_delta -> content_block_stop

content_block_delta has the  complete summary content

### Prompt caching

Compaction works well with [prompt caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching). You can add a `cache_control` breakpoint on compaction blocks to cache the summarized content.

### Maximining cache hits with system prompts

系统提示词的缓存和压缩新写入的内容会分开,这样写入的就只有压缩后的内容,而系统提示词的缓存不会失效,实现的方法是在你的系统提示词的后面打一个断点

When compaction occurs, the summary becomes new content that needs to be written to the cache. Without additional cache breakpoints, this would also invalidate any cached system prompt, requiring it to be re-cached along with the compaction summary.

To maximize cache hit rates, add a `cache_control` breakpoint at the end of your system prompt. This keeps the system prompt cached separately from the conversation, so when compaction occurs:

- The system prompt cache remains valid and is read from cache
- Only the compaction summary needs to be written as a new cache entry

his keeps long system prompts cached across multiple compaction events throughout a conversation.

## Understanding usage

Compaction requires an additional sampling step, which contributes to rate limits and billing. The API returns detailed usage information in the response:

Output

```
{
  "usage": {
    "input_tokens": 23000,
    "output_tokens": 1000,
    "iterations": [
      {
        "type": "compaction",
        "input_tokens": 180000,
        "output_tokens": 3500
      },
      {
        "type": "message",
        "input_tokens": 23000,
        "output_tokens": 1000
      }
    ]
  }
}
```

The `iterations` array shows usage for each sampling iteration. When compaction occurs, you'll see a `compaction` iteration followed by the main `message` iteration. The top-level `input_tokens` and `output_tokens` match the `message` iteration exactly in this example because there is only one non-compaction iteration. The final iteration's token counts reflect the effective context size after compaction.

inerations数组中comapaction部分记录了压缩之前的上下文大小和压缩后的上下文大小,上面的usage和message相同是因为:
上述只有一次非compaction迭代

```
The top-level input_tokens and output_tokens do not include compaction iteration usage. They reflect the sum of all non-compaction iterations. To calculate total tokens consumed and billed for a request, sum across all entries in the usage.iterations array.

If you previously relied on usage.input_tokens and usage.output_tokens for cost tracking or auditing, you'll need to update your tracking logic to aggregate across usage.iterations when compaction is enabled. With the compaction beta enabled, every response includes usage.iterations, even if no compaction occurred. A compaction entry appears only when a new compaction is triggered during the request. Re-applying a previous compaction block incurs no additional compaction cost, and the top-level usage fields remain accurate in that case.
```

顶端的input_token和output_token不包含压缩迭代所产生的使用量,反应的是非压缩迭代的总和
要计算一次实际请求用量,要对usage.iteration中数组中的所有条目求和依赖usage.input_token和usage.output.token来进行成本统计的方式需要转变逻辑结构,转化为对于usage.interation中的每一项进行汇总
在启用compaction Beta之后,每个响应都会柏寒usage.interation,即使没有发生上下文压缩
但是只有出现了compaction,才会在interation中出现compaction条目
重新应用原来已经存在的compaction block不会产生额外的上下文压缩费用

## Combing With other Features

### Server tools

When using server tools (such as web search), the compaction trigger is checked at the start of each sampling iteration. Compaction might occur multiple times within a single request depending on your trigger threshold and the amount of output generated.
系统会在每个迭代之前检查是否需要压缩,这取决于你的设置和产出的数量

###  Token counting

The token counting endpoint (`/v1/messages/count_tokens`) applies existing `compaction` blocks in your prompt but does not trigger new compactions. Use it to check your effective token count after previous compactions
使用现存的compaction块而不会激活compaction,所哟不会产生新的上下文费用

## Current limitations

- **Same model for summarization:** The model specified in your request is used for summarization. There is no option to use a different (for example, cheaper) model for the summary.

有点变态的是,Claudecode会给每一个模型都开新的缓存

- **Compaction might fail when tools are defined:** When your request includes `tools`, the model occasionally calls a tool during the internal summarization step instead of writing a summary. When this occurs, the response contains a `compaction` block with `content: null`. To prevent this, set [`instructions`](https://platform.claude.com/docs/en/build-with-claude/compaction#custom-summarization-instructions) to a prompt that explicitly tells the model not to call tools, for example:
  当你的请求中包含tools是,有时候压缩会因为调用工具而失败
  解决方法:在Instruction中显式地声明不调用工具