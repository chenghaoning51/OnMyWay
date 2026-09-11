+++
title = 'Context Management · Context Editing'
slug = "context-editing"
date = 2026-09-06T00:00:00+08:00
lastmod = 2026-09-06T00:00:00+08:00
weight = 4
categories = ['上下文工程']
tags = ['Context Engineering', 'Claude']
description = 'Claude 的 Context Editing：自动清理过时的工具调用结果以管理对话上下文。'
+++

# Context editing

Automatically manage conversation context as it grows with context editing
注意断句

## Overview

The strategies on this page are useful for specific scenarios where you need more fine-grained control over what content is cleared.

更适用于在特定场景中,你需要清楚哪些内容进行更加细粒度的控制

Context editing allows you to selectively clear specific content from conversation history as it grows. Beyond optimizing costs and staying within limits, this is about actively curating what Claude sees: context is a finite resource with diminishing returns, and irrelevant content degrades model focus. Context editing gives you fine-grained runtime control over that curation. For the broader principles behind context management, see [Effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents).

上下文编辑允许你选择性地清楚会话内容

除了控制成本和避免超出限制以外,这也是在主动管理Claude对于上下文的可见性:上下文是一种有限的资源,且存在边界效应;无关内容会导致模型降级和降低注意力

主要提供了三种方法:

- Tool result clearing: 适用于工具调用频繁且旧的工具调用结果不再需要的场景
- Thinking block clear:可有有选择性地保留最近地think block
- Client-side SDK compaction:An SDK-based alternative for summary-based context management (server-side compaction is generally preferred)官方Compaction的替代

| Approach        | Where it runs | Strategies                                                   | How it works                                                 |
| --------------- | ------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **Server-side** | API           | Tool result clearing (`clear_tool_uses_20250919`) Thinking block clearing (`clear_thinking_20251015`) | Applied before the prompt reaches Claude. Clears specific content from conversation history. Each strategy **can be configured independently.** |
| **Client-side** | SDK           | Compaction                                                   | Available in [TypeScript and Ruby SDKs](https://platform.claude.com/docs/en/cli-sdks-libraries/overview) when using [`tool_runner`](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-runner). Generates a summary and replaces full conversation history. See [Client-side compaction](https://platform.claude.com/docs/en/build-with-claude/context-editing#client-side-compaction-sdk). |

## Server-side Strategies

### Tool result clearing

 when conversation context grows beyond your configured threshold
Best  for agentic workflows with heavy tool use and Older tool results are no longer needed once Claude has processed them.

通过清楚oldest tool result并且使用占位文本进行替换来告知模型结果已经被移除
默认情况下,只有results会被移除,但是你也可以在配置文件中将clear_tool_call 甚至为True,这样会同时清楚tool_calls以及调用时的tool use parameters和tool_results

### Think block clearing

The `clear_thinking_20251015` strategy manages `thinking` blocks in conversations when extended thinking is enabled. This strategy gives you control over thinking preservation: you can choose to keep more thinking blocks to maintain reasoning continuity, or clear them more aggressively to save context space.
用于启用了extend_thinking的会话中的think_blocks;
你可以选择保留更多的thinking_block也可以积极清理来节省上下文空间

**Default behavior:** The default varies by model class.

| Model class      | Keep all prior thinking     | Keep only the last turn's thinking  |
| ---------------- | --------------------------- | ----------------------------------- |
| Opus             | Claude Opus 4.5 and later   | Claude Opus 4.1 and earlier         |
| Sonnet           | Claude Sonnet 4.6 and later | Claude Sonnet 4.5 and earlier       |
| Haiku            | (none)                      | All models through Claude Haiku 4.5 |
| Fable and Mythos | All models                  | (none)                              |

You can override the default,if your code runs across multiple models tiers,ser **keep **explicitly rather than relying on the per-model default

With interleaved thinking,there includes multiple thinking blocks

### Context editing happens server-side

Context editing is applied server-side before the prompt reaches Claude. 