+++
title = "Prompt Caching"
slug = "prompt-caching"
weight = 60
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "Prompt Caching相关学习笔记与实践要点。"
+++
# Prompt Caching

使用cache_control来缓存提示词前缀,使用自动缓存或者使用显示缓存断点:具有5分钟或者1h的存活时间的断点

Prompt caching允许你从提示词中的特定前缀继续处理,来优化API的使用

- **[Automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)**: Add a single `cache_control` field at the top level of your request. The system automatically applies the cache breakpoint to the last cacheable block and moves it forward as conversations grow. Best for multi-turn conversations where the growing message history should be cached automatically.

  ```
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

  

- **[Explicit cache breakpoints](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)**: Place `cache_control` directly on individual content blocks for fine-grained control over exactly what gets cached.

其中都有breakpoint的存在,由此可知breakpoint的作用时为显式划分缓存地边界

我刚去学习了一下机制:
首先.
有一个消息队列,在它的最前面有形如:
system prompt,tools,agent.md(项目级别文档,看自己的harness规定)等等(这些是看harness规定地),
然后每次新的对话,就会在消息队列中新增内容,并且在automatic的情况下,就会不断地移动断点来显式标注prompt prefix地边界,这是客户端的内容
然后发送给服务端后,在推理过程中,会从前缀开始一个token一个token地进行比对,命中的部分就会复用KV cache中已有的部分
而未命中的部分就会创建新的KV
Prefix Cache 是连续的：从 Prompt 开头开始匹配；第一个 token mismatch 出现后，该缓存链在这里截断，后续内容需要重新 Prefill

下面有个例子,自己看

上面算是题外话,接下来继续:

## How prompt caching works

## How prompt caching works

When you send a request with prompt caching enabled:

1. The system checks if a prompt prefix, up to a specified cache breakpoint, is already cached from a recent query.
2. If found, it uses the cached version, reducing processing time and costs.
3. Otherwise, it processes the full prompt and caches the prefix once the response begins.
   但是并不是全面重新cache哦

缓存的生命周期是从这条请求的开始就开始计算了,而不是从response开始计算,一般默认是5分钟
那有人就会问了(其实是我):我早上开了一个会话,下午继续问.缓存是不是就失效了?是的
那么还有人就要问:TTL五分钟,我一次会话都不止
实际上,只要你有新的information产生并会先hit 然后创建新的cache内容或者你不断地hit cache,它的生命周期会一直延续下去,比如你不断调用工具之类的,so don't worry
不过如果你觉得5分钟太短了,可以有1h的,不过那是另外的价钱

## Automatic caching

### How automatic caching works in multi-turn conversations

With automatic caching, the cache point moves forward automatically as conversations grow. Each new request caches everything up to the last cacheable block, and previous content is read from cache.

| Request   | Content                                                      | Cache behavior                                               |
| --------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| Request 1 | System + User(1) + Asst(1) + **User(2)** ◀ cache             | Everything written to cache                                  |
| Request 2 | System + User(1) + Asst(1) + User(2) + Asst(2) + **User(3)** ◀ cache | System through User(2) read from cache; Asst(2) + User(3) written to cache |
| Request 3 | System + User(1) + Asst(1) + User(2) + Asst(2) + User(3) + Asst(3) + **User(4)** ◀ cache | System through User(3) read from cache; Asst(3) + User(4) written to cache |

### TTL support

y default, automatic caching uses a 5-minute TTL. You can specify a 1-hour TTL at 2x the base input token price:

```
{ "cache_control": { "type": "ephemeral", "ttl": "1h" } }
```

### Combining with block-level caching

自动缓存与[显式缓存断点（explicit cache breakpoints）](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)兼容。当两者一起使用时，**自动缓存断点会占用 4 个可用缓存断点槽位中的一个**

### what stays the same

自动缓存使用相同的底层缓存基础设施。其**定价、最低 Token 数量要求、上下文顺序要求，以及 20 个 block 的回溯窗口**，都与显式缓存断点的规则相同。

### Edge cases

- If the last block already has an explicit `cache_control` with the same TTL, automatic caching is a no-op.
- If the last block has an explicit `cache_control` with a different TTL, the API returns a 400 error.
- If 4 explicit block-level breakpoints already exist, the API returns a 400 error (no slots left for automatic caching).
- If the last block is not eligible as an automatic cache breakpoint target, the system silently walks backwards to find the nearest eligible block. If none is found, caching is skipped.

## Explicit cache breakpoints

 This is useful when you need to cache different sections that change at different frequencies, or need fine-grained control over exactly what gets cached.
适用于你想要控制缓存的block

### How automatic prefix checking works

#### Three core principle

- **Cache writes happen only at your breakpoint.**
- **Cache reads look backward for entries that prior requests wrote**
-  **The lookback window is 20 blocks.**

简言之:只在断点处写入;会向前回溯(指的是在不匹配的情况下,镶向前回溯);回溯窗口为20个Block(最多回溯20个窗口,如果超过了.就会停止检查)

**Example: Lookback in a growing conversation**

You append new blocks each turn and set `cache_control` on the final block of each request:

- **Turn 1:** 10 blocks, breakpoint on block 10. No prior cache entries exist. The system writes an entry at block 10.
- **Turn 2:** 15 blocks, breakpoint on block 15. Block 15 has no entry, so the system walks back to block 10 and finds the turn-1 entry. Cache hit at block 10; the system processes only blocks 11 through 15 fresh and writes a new entry at block 15.
- **Turn 3:** 35 blocks, breakpoint on block 35. The system checks 20 positions (blocks 35 through 16) and finds nothing. The turn-2 entry at block 15 is one position outside the window, so there is no cache hit. Adding a second breakpoint at block 15 starts a second lookback window there, which finds the turn-2 entry.

**核心要点：** 将 `cache_control` 放在**跨请求保持不变的、最后一个 block** 上，这样你希望共享同一个缓存的请求就可以复用该缓存。

在不断增长的对话中，只要每一轮新增的内容少于 **20 个 block**，将缓存断点放在最后一个 block 上就可以正常工作：之前的内容不会发生变化，因此下一次请求的回溯机制能够找到上一次请求写入的缓存。

对于带有**变化后缀**的提示词（例如时间戳、每次请求特有的上下文、用户当前发送的消息），应该将缓存断点放在**静态前缀的末尾**，而不是放在会发生变化的 block 上。

#### When to use multiple breakpoints

最多4个断点,应用情景如下:

- Cache different sections that change at different frequencies (for example, tools rarely change, but context updates daily)
- Have more control over exactly what gets cached
- Ensure a cache hit when a growing conversation pushes your breakpoint 20 or more blocks past the last cache write

对于一次write,超过20个block会导致`miss

### Understanding cache breakpoints cost

断点本身不付费
付费的是:缓存读写和常规输入

## Caching strategies and considerations

### Limitations:

the minimum cacheable prompt length is:

| Minimum cacheable length | 模型                                                         |
| ------------------------ | ------------------------------------------------------------ |
| **512**                  | Claude Fable 5.1、Claude Mythos 5.1、Claude Opus 5、Claude Fable 5、Claude Mythos 5 |
| **1,024**                | Claude Opus 4.8、Claude Sonnet 5、Claude Sonnet 4.6、Claude Sonnet 4.5、Claude Opus 4.1、Claude Opus 4、Claude Sonnet 4 |
| **2,048**                | Claude Mythos Preview、Claude Opus 4.7、Claude Haiku 3.5     |
| **4,096**                | Claude Opus 4.6、Claude Opus 4.5、Claude Haiku 4.5           |

To verify whether a prompt was cached, check the [response usage fields](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#tracking-cache-performance): if both `cache_creation_input_tokens` and `cache_read_input_tokens` are 0, the prompt was not cached (likely because it did not meet the minimum length requirement).

### what can be cached

- Tools: Tool definitions in the `tools` array
- System messages: Content blocks in the `system` array
- Text messages: Content blocks in the `messages.content` array, for both user and assistant turns
- Images & Documents: Content blocks in the `messages.content` array, in user turns
- Tool use and tool results: Content blocks in the `messages.content` array, in both user and assistant turns

### what cannot be cached

- Thinking blocks cannot be cached directly with `cache_control`. However, thinking blocks CAN be cached alongside other content when they appear in previous assistant turns. When cached this way, they DO count as input tokens when read from cache.

- Sub-content blocks (like [citations](https://platform.claude.com/docs/en/build-with-claude/citations)) themselves cannot be cached directly. Instead, cache the top-level block.

  In the case of citations, the top-level document content blocks that serve as the source material for citations can be cached. This allows you to use prompt caching with citations effectively by caching the documents that citations will reference.

- Empty text blocks cannot be cached.

### What invalidates the cache

Modifications to cached content can invalidate some or all of the cache.

| What changes                                              | Tools cache    | System cache   | Messages cache | Impact                                                       |
| --------------------------------------------------------- | -------------- | -------------- | -------------- | ------------------------------------------------------------ |
| **Tool definitions**                                      | ✘              | ✘              | ✘              | Modifying tool definitions (names, descriptions, parameters) invalidates the entire cache |
| **Web search toggle**                                     | ✓              | ✘              | ✘              | Enabling/disabling web search modifies the system prompt     |
| **Citations toggle**                                      | ✓              | ✘              | ✘              | Enabling/disabling citations modifies the system prompt      |
| **Speed setting**                                         | ✓              | ✘              | ✘              | Switching between [`speed: "fast"` and standard speed](https://platform.claude.com/docs/en/build-with-claude/fast-mode) invalidates system and message caches |
| **Tool choice**                                           | ✓              | ✓              | ✘              | Changes to `tool_choice` parameter only affect message blocks |
| **Images**                                                | ✓              | ✓              | ✘              | Adding/removing images anywhere in the prompt affects message blocks |
| **Thinking parameters**                                   | Model-specific | Model-specific | ✘              | The thinking configuration (mode, and `budget_tokens` in extended mode) is rendered into the prompt, so changing it always invalidates message blocks; tool and system caches are also invalidated on models that render the configuration ahead of them. See [Thinking and prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-prompt-caching). |
| **Effort setting**                                        | Model-specific | Model-specific | ✘              | Changing the [`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort) value always invalidates message blocks, with the same model-specific effect on tool and system caches as thinking parameters. Setting effort explicitly to the model's default is equivalent to omitting it and does not invalidate. On models that support [per-message effort](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta), an effort change carried in a `role: "system"` message inside `messages` leaves the cached prefix intact. |
| **Non-tool results passed to extended thinking requests** | ✓              | ✓              | Model-specific | On Opus 4.5+ and Sonnet 4.6+, thinking blocks are preserved by default, so the cache remains valid (✓). On earlier Opus/Sonnet models and all Haiku models, all previously-cached thinking blocks are stripped from context, and any messages that follow those thinking blocks are removed from the cache (✘). For more details, see [Caching with thinking blocks](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#caching-with-thinking-blocks). |
| **Dropped thinking blocks**                               | ✓              | ✓              | ✘              | When the API drops a Claude Fable 5.1 or Claude Mythos 5.1 thinking block that isn't [preserved](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-thinking) on that request (for example, one you replay to an earlier model), the cached prefix changes from that block's position onward on that request. Blocks the receiving model can read, passed back unchanged, keep the cache intact. |

### Tracking cache preformance

```
total_input_tokens = cache_read_input_tokens + cache_creation_input_tokens + input_tokens
```

计费则是在对应的部分乘上price

### **Understanding the token breakdown**

### The `input_tokens` field represents only the tokens that come **after the last cache breakpoint** in your request - not all the input tokens you sent.

To calculate total input tokens:

```
total_input_tokens = cache_read_input_tokens + cache_creation_input_tokens + input_tokens
```

**Spatial explanation:**

- `cache_read_input_tokens` = tokens before breakpoint already cached (reads)
- `cache_creation_input_tokens` = tokens before breakpoint being cached now (writes)
- `input_tokens` = tokens after your last breakpoint (not eligible for cache)

**Example:** If you have a request with 100,000 tokens of cached content (read from cache), 0 tokens of new content being cached, and 50 tokens in your user message (after the cache breakpoint):

- `cache_read_input_tokens`: 100,000
- `cache_creation_input_tokens`: 0
- `input_tokens`: 50
- **Total input tokens processed:** 100,050 tokens

This is important for understanding both costs and rate limits, as `input_tokens` will typically be much smaller than your total input when using caching effectively.

### Caching with thinking blocks

thinking blocks在不同cache策略下的缓存方法:
在auto:alongside other content
不能直接缓存,和其他内容一起,比如tool call

**Input token counting:**当think block在缓存中被读,就会被视为input_token

### Cache storage and sharin

Prompt caching uses [workspace](https://platform.claude.com/docs/en/manage-claude/workspaces)-level isolation. 
 Caches are isolated between organizations.
 Caches are also isolated per workspace within an organization 
**Exact matching:** Cache hits require 100% identical prompt segments, including all text and images up to and including the block marked with cache control.
**Output token generation:** Prompt caching has no effect on output token generation. The response you receive is identical to what you would get if prompt caching were not used.(显而易见的,只是费用有区别罢了)

### Best practices for effective caching

To optimize prompt caching performance:

- Start with [automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching) for multi-turn conversations. It handles breakpoint management automatically.
- Use [explicit block-level breakpoints](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints) when you need to cache different sections with different change frequencies.
- Cache stable, reusable content like system instructions, background information, large contexts, or frequent tool definitions.
- Place cached content at the prompt's beginning for best performance.
- Use cache breakpoints strategically to separate different cacheable prefix sections.
- Place the breakpoint on the last block that stays identical across requests. For a prompt with a static prefix and a varying suffix (timestamps, per-request context, the incoming message), that is the end of the prefix, not the varying block.
- Regularly analyze cache hit rates and adjust your strategy as needed.

### Optimizing for different use cases(泛话,懒得看)

对话式智能体（Conversational agents）： 降低长对话的成本和延迟，尤其适用于包含较长指令或上传文档的对话。

编程助手（Coding assistants）： 通过在提示词中保留代码库的相关部分，或代码库的摘要版本，提升代码自动补全和代码库问答的效果。

大型文档处理（Large document processing）： 将完整的长篇材料（包括图片）放入提示词中，而不会增加响应延迟。

详细的指令集（Detailed instruction sets）： 通过共享大量指令、流程和示例，让 Claude 的响应更加符合要求。开发者通常会在提示词中加入一两个示例，但借助提示词缓存，可以通过加入 20 个以上不同的高质量答案示例，获得更好的性能。

智能体工具调用（Agentic tool use）： 提升涉及多次工具调用和迭代式代码修改的场景的性能，因为每一步通常都需要发起一次新的 API 请求。

与书籍、论文、文档、播客文字稿及其他长篇内容对话： 通过将完整文档嵌入提示词，让任何知识库都变得生动，并允许用户向其提问。

### Troubleshooting common issues(也是,懒得看)

If experiencing unexpected behavior:



[Cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics) (beta) has the API compare consecutive requests and report exactly where the prompt prefix diverged, which automatically handles many of the steps in this list.

- Ensure cached sections are identical across calls. For explicit breakpoints, verify that `cache_control` markers are in the same locations
- Check that calls are made within the cache lifetime (5 minutes by default)
- Verify that `tool_choice`, image usage, the thinking configuration, and `output_config.effort` remain consistent between calls
- Validate that you are caching at least the minimum number of tokens for your model and platform (see [Cache limitations](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-limitations))
- Confirm your breakpoint is on a block that stays identical across requests. Cache writes happen only at the breakpoint, and if that block changes (timestamps, per-request context, the incoming message), the prefix hash never matches. The lookback does not find stable content behind the breakpoint; it only finds entries that earlier requests wrote at their own breakpoints
- Verify that the keys in your `tool_use` content blocks have stable ordering as some languages (for example, Swift, Go) randomize key order during JSON conversion, breaking caches
- Use [cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics) to have the API compare consecutive requests and report which part of the prompt diverged

## 1-hour cache duration

### Mixing different TTLs

You can use both 1-hour and 5-minute cache controls in the same request, but with an important constraint: Cache entries with longer TTL must appear before shorter TTLs (that is, a 1-hour cache entry must appear before any 5-minute cache entries).

## Pre-warming the cache

load your system prompt or tool definitions into the prompt cache before a user triggers a real request. 

### How it works

在请求中设置 `max_tokens: 0`。API 会将你的提示词读入模型，并在任何 `cache_control` 断点处写入缓存，然后立即返回，不生成任何输出。响应中的 `content` 数组为空，`stop_reason` 为 `"max_tokens"`，并且包含完整的 `usage` 信息。

将 `cache_control` 断点放在与后续请求共享的最后一个 block 上（通常是系统提示词或工具定义），而不是占位用户消息上。否则，缓存条目会以占位内容作为键，后续请求就无法命中该缓存。

同时，预热请求也应使用与后续请求相同的 `thinking` 配置和 `output_config.effort`。这些值会被渲染到提示词中（参见[什么会使缓存失效（What invalidates the cache） ](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#what-invalidates-the-cache)），因此，如果预热请求使用了不同的配置，就可能写入一个真实流量永远无法命中的缓存条目。

这意味着应使用**[显式缓存断点（explicit cache breakpoint） ](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)，而不是[自动缓存（automatic caching） ](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)**，因为自动缓存会将断点放在最后一个 block 上，而在这里，最后一个 block 正是占位消息。

占位用户消息可以是任何包含非空白字符的字符串（示例中使用 `"warmup"`）；其内容会被读入模型，但不会得到回答。

### Typical usage pattern

Fire a pre-warm request when your application starts (or on a scheduled interval), then send real user requests after the pre-warm completes:

### Limitation

A `max_tokens: 0` request is rejected with an `invalid_request_error` if any of the following are set, since each implies output that a zero-token budget cannot produce:

- `stream: true`
- [Extended thinking](https://platform.claude.com/docs/en/build-with-claude/extended-thinking) (`thinking.type: "enabled"`)
- [Structured outputs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs) (`output_config.format`)
- `tool_choice` of `{"type": "tool", ...}` or `{"type": "any"}`

`max_tokens: 0` is also rejected inside a [Message Batches](https://platform.claude.com/docs/en/build-with-claude/batch-processing) request. Pre-warming targets time-to-first-token, which does not apply to batch processing, and a cache entry written during batch processing would likely expire before the follow-up request runs.

### Data retention

Prompt caching (both automatic and explicit) is ZDR eligible. Anthropic does not store the raw text of your prompts or Claude's responses.

KV (key-value) cache representations and cryptographic hashes of cached content are held in memory only and are not stored at rest. Cached entries have a minimum lifetime of 5 minutes (standard) or 1 hour (extended), after which they are promptly, though not immediately, deleted. Cache entries are isolated between organizations and, on the Claude API, Claude Platform on AWS, and Microsoft Foundry, between workspaces within an organization.

符合ZDR(零数据保留),KV cache和加密哈希值仅保存在内存中,不会持久化,最短生命周期为5min或者1h
缓存条目在不同组织上相互隔离