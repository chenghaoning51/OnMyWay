+++
title = "Claude上下文"
slug = "claude-context-reference"
weight = 60
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "Claude上下文相关学习笔记与实践要点。"
+++
# 上下文窗口

## context rot:随着上下文token数地增长,准确性和召回率会下降的现象

## 对于一个request包含的内容:

1. tools:能够给模型提供tools,包含其名称,描述,参数
2. System prompt:系统提示词
3. 一些harness设置的信息,比如ClaudeCode的CLAUDE.md或者codex的AGENTS.md等等
4. user message: prompt,tool calling,thinking block,tool result等等

## 区分三个概念:

input_tokens;cache_read_input_tokens;cache_creation_input_token

这和prompt caching还有price有关

## 带thinking的上下文窗口

thinking tokens是max_tokens的子集

关于assistant turn中的think blocks是否保留在上下文由模型决定
不过现在大部分的模型都是全量保留
不过在context_editing中你可以在通过设置来清楚think blocks腾出更多的上下文空间

对于启用了剥离thinking blocks的模型:

- thinking blocks会作为上一轮assistant turn的output,但是不会作为下一轮的user turn的input
- 计费:think blocks作为输出计费,如果被保留,在下一轮对话中也会作为上下文输出,按输入再次计费

## 上下文的感知(context awareness):

### 工作原理:

之前:每个request的system prompt中会包含总的上下文窗口
每次工具调用之后,API会向Claude提供剩余用量的更新
之后:
不会收到这些注入的标签了
通过task_budgets给模型一个显示预算

## 用压缩管理上下文:

server-side compaction时最常见的管理上下文的方式
对于更为专业的需求,在context-editing中提供了额外的策略:

- tool result clearing: 清楚工具调用的结果,可通过设置也清楚工具调用的请求信息
- thinking blocks clearing:在extending thinking时清楚thinking blocks

# Compaction

server-side Compaction是管理上下文的最常见的方式,他会自动处理上下文管理

when:

压缩会在上下文窗口的大小接近上限时自动摘要较久的上下文

适用于:

- 基于聊天的多轮对话
- 需要大量后续工作,且可能超出上下文窗口的面向任务的prompt

## 压缩如何工作的

当快要到达对话设定的阈值的时候,会自动触发上下文压缩:

1. 检测输出的token是否达到你设定的阈值
2. 生成当前对话的摘要
3. 创建包含该摘要的compaction block
4. 使用压缩后的上下文进行回复

## 基本用法:

在message API请求的context_management.edits中添加compact_20260112的策略来启用缓存

## 参数

| 参数                     | 类型    | 默认值                                      | 说明                                                         |
| ------------------------ | ------- | ------------------------------------------- | ------------------------------------------------------------ |
| `trigger`                | object  | `{"type": "input_tokens", "value": 150000}` | 何时触发压缩。`input_tokens` 是唯一支持的触发类型。`value` 必须至少为 50,000 tokens。 |
| `pause_after_compaction` | boolean | `false`                                     | 生成压缩摘要后是否暂停                                       |
| `instructions`           | string  | `null`                                      | 自定义摘要 prompt。提供后会完全替换默认 prompt。             |
| `type`                   | string  | Required                                    | 必须为 `"compact_20260112"`                                  |

### 触发配置:

使用trigger参数配置何时触发压缩

### 自定义摘要指令:

默认的prompt因模型而异,但是可以通过instruction参数提供自定义的指令
而且它不会补充默认的指令,而是完全代替它

### 压缩后暂停:

使用pause_after_compaction参数设置,这可以使得在继续生成回复之前添加额外的content block(例如保留最近的消息或者特定的指令导向消息)

启用后,API在生成compaction block后会返回带有compaction stop reason的消息


## 处理compaction block:

触发压缩后,会在压缩完成后assistant回复的开头返回一个compaction block
长时间运行的对话可能会存在多次compaction,最后一个compaction block反应了prompt的最终状态

### 回传compaction block:

你必须在后续的request中回传compaction block,才能以缩短后的prompt继续对话
最简单的做法是:把整个响应content追加到你的message中

当API收到compaction block时,之前的所有的content block都会被忽略,你可以:

- 在列表中保留原始message,让API处理移除已经压缩的内容
- 手动丢弃已经压缩的内容我

如果你编写自己的 `instructions`，需告知模型摘要必须保留什么；见 [Tell the model what to preserve in compaction summaries](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#tell-the-model-what-to-preserve-in-compaction-summaries)。

### 流式输出:

compaction的流式传输方式与text block不同:

1. 你会先收到一个content_block_start事件
2. 收到一条包含完整摘要内容的content_block_delta(无中间流式片段)
3. 然后时cintent_block_stop事件

### Prompt caching:

你可以在compaction block上添加cache control的breakdown来缓存摘要后的内容

### 通过System prompt最大化缓存命中:

发生压缩时,摘要会称为需要写入缓存的新内容,如果没有额外的缓存断点,会使已经缓存的system prompt失效

为了最大化缓存命中率,会在system prompt的末尾添加一个cache_control的断点,使得system_prompt和对话分开缓存,因此在发生压缩时:

- system prompt缓存依旧有效,从缓存读取
- 将摘要作为新的缓存条目读入

### 了解用量:

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

iteration数组显示每次采样的迭代用量
发生压缩时,你会看到一次compaction迭代,随后是主要的message迭代
最顶层的input_tokens和output_tokens不包含压缩迭代的用量,因此在计算总的用量时,请对usage.iteration的每一个迭代进行求和(包括compaction迭代)

## 与其他功能结合:

### 服务端工具:

使用服务端工具（例如 web search）时，会在每次采样迭代开始时检查压缩触发条件。根据触发阈值和生成的输出量，单次请求内可能发生多次压缩。

### Token计数

token 计数端点（`/v1/messages/count_tokens`）会应用 prompt 中已有的 `compaction` block，但不会触发新的压缩。用它来检查先前压缩后的有效 token 数：

## 当前限制:

- 摘要使用同一模型:
- 定义了tools时压缩可能失败:当请求包含tools时,模型偶尔会在内部摘要步骤中调用工具,而不是撰写摘要,发生这种情况时,会响应中会返回一个content: null的compaction block
  为了防止这种情况,会在instruction中明确告知模型不要调用工具

# Context editing:

概述:server-side compaction是最常见的上下文管理措施
而本章中的策略适用于需要更加精细控制需要clear哪些内容的特定场景
允许你有选择性地清楚特定地内容,不仅仅是为了优化成本,也是为了主动筛选模型所见地内容
主要由下面三种策略:

1. tool result clear:
2. think block clear:用于开启了extended thinking时管理think block
3. 客户端SDK压缩(不打算看)

## 服务端策略:

主要分为两种:tool_result clear和thinking block clear

### Tool result clear:

用于清理工具调用地结果(和工具调用:需要配置开启)
激活后,API会清理最旧的工具结果,将其替换为占位文本,表示已经被移除
也可以将clear_tool_inputs设置为true,同时清理tool result和tool call

### Thinking block clear:

对于开启extended thing时启用
现在的大部分模型都默认保留think block,并且作为后续的input

### context editing和Prompt Caching:

- tool result clear:会使已经缓存的prompt失效,所以应该清理足够多的token使得物有所值,可以使用clear_at_least规定清理token的最少数量
- think block clear:同样的,缓存会在清理发生处失效,常见是将thinking block keep

## tool result clear usage:

最常见:使用仅指定策略(即不清除tool call),其他使用默认值

### 高级配置:其他参数定义清楚行为

```
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

可以配置的选项有:

| 配置选项            | 默认值             | 说明                                                         |
| ------------------- | ------------------ | ------------------------------------------------------------ |
| `trigger`           | 100,000 输入 token | 定义上下文编辑策略何时激活。一旦 prompt 超过此阈值，便开始清除。你可以用 `input_tokens` 或 `tool_uses` 指定此值。 |
| `keep`              | 3 次工具使用       | 定义清除发生后保留多少对近期的工具使用/结果。API 先移除最旧的工具交互，保留最近的交互。 |
| `clear_at_least`    | 无                 | 确保每次策略激活时至少清除指定数量的 token。如果 API 无法至少清除指定数量，则不会应用该策略。这有助于判断上下文清除是否值得打断你的 prompt 缓存。 |
| `exclude_tools`     | 无                 | 其工具使用和结果永远不应被清除的工具名称列表。适用于保留重要上下文。 |
| `clear_tool_inputs` | `false`            | 控制是否连同工具结果一起清除工具调用参数。默认情况下，仅清除工具结果，同时保持 Claude 原始的工具调用可见。 |

## think block clear:

### 可配置的选项:

keep:
定义要保留的多少个含think block的assistant turn使用{type: "thinking_turns", value: N}.(管理上下文)
或者直接使用keep: all来保留所有的think blocks(最大化缓存命中)

## 组合策略:

限制:当使用组合策略时,clear_thinking_20251015比放在edits数组的第一位


## 上下文编辑响应

你可以使用context_management的响应字段来查看哪些上下文编辑已经应用于你的request,已经有关已清楚内容和输入token的有用统计信息
例如:

```
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

对于stream响应,相关的信息在最终的message_delta

```
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

## Token count:

用于支持上下文管理,让你预览在context edit后prompt使用多少token

```

  print(f"Original tokens: {response.context_management.original_input_tokens}")
  print(f"After clearing: {response.input_tokens}")
  print(
      f"Savings: {response.context_management.original_input_tokens - response.input_tokens} tokens"
  )
```

响应显示context editing之后的token和清楚发生之前的original_input_tokens

## 与memory tool一起使用

当context到达被清除的阈值时,在被清理之前,收到自动警告以保存重要信息,将对话历史和其他信息保存到memory中

- 保留重要上下文
- 维持长时间的工作流
- 按需访问信息

# Prompt Caching

允许你使用prompt prefix匹配来优化API的token用量

对于重复性任务和包含一致元素的prompt会显著降低处理时间和成本

有两种方法来启用Prompt Caching

- automatic cache:在请求的顶层添加单个cache_control字段,系统会自动将缓存的断点应用到最后一个可缓存的block
- 显式缓存断点:将cache_control放在content block上

最简单的方式是使用自动缓存:
使用自动缓存时，系统会缓存直到并包括最后一个可缓存块的全部内容

Prompt Caching怎么工作:

1. 系统检查prompt prefix,查看是否能够查询到
2. 如果能够找到,就直接复用
3. 否则处理完整的prompt

一般来说,缓存的TTL为5min(由模型决定)或1h(需要设置开启,且price更贵)

TTL(生命周期):从写入或者读取该条缓存条目开始而非响应结束的时刻
**Prompt Caching缓存完整的前缀**:
引用整个prompt---tools,system和messages,知道并包括使用cache_control的block

## Automatic Caching:

usage:在单个请求体顶层添加 cache_control字段
将缓存断点应用到最后一个可缓存的block

### 自动缓存在多轮对话中怎么工作?

随着对话的进行,断点会自动向前移动,到新的请求的最后一个可缓存的block的
而先前的内容通过缓存读取
所以不需要跟随对话去更新cache_control标记

### TTL支持:

默认5min,可开启1h,价格不同

### 与显式缓存结合:

两者是可以兼容的,这个时候,自动缓存断点会占用四个可用断点槽位中的一个
常见用法:
用显式缓存断点缓存system prompt;用自动缓存断点处理对话
将stable prompt和variable prompt分开进行缓存

### 边界情况

* 如果最后一个块已经带有相同 TTL 的显式 `cache_control`，自动缓存为 no-op。
* 如果最后一个块带有不同 TTL 的显式 `cache_control`，API 返回 400 error。
* 如果已经存在 4 个显式块级断点，API 返回 400 error（没有剩余槽位给自动缓存）。
* 如果最后一个块不适合作为自动缓存断点目标，系统会静默向后查找最近的合格块。如果找不到，则跳过缓存。

## 显式缓存断点

更加精细地控制缓存
usage:将cache_control放在具体的block上

## 组织你的prompt:

将stable prompt放在prompt开头,是cache_control参数标记在可复用内容的结尾便于缓存
prompt prefix的顺序:
tools,system,messages

## 自动前缀检查如何工作:

三条核心原则:(这个只针对采取这种算法的模型成立)

1. 缓存写入只发生在你的断点处
2. 缓存读取会向后查找先前请求写入的条目
3. 回看窗口为20块 注意此处为block而非记录哦,但是不是在20块结束就停止,也是会继续向前读条目

## 缓存策略和注意事项

### 缓存限制:

可缓存Prompt的最短长度,小于这个长度,即使有cache_control也不会缓存

### 哪些内容可以缓存:

* 工具：`tools` 数组中的工具定义
* 系统消息：`system` 数组中的内容块
* 文本消息：`messages.content` 数组中的内容块，适用于 user 和 assistant 两轮
* 图像和文档：`messages.content` 数组中的内容块，位于 user 轮
* 工具使用和工具结果：`messages.content` 数组中的内容块，适用于 user 和 assistant 两轮

### 哪些内容不能缓存:

* Thinking 块不能用 `cache_control` 直接缓存。但是，当 thinking 块出现在先前的 assistant 轮中时，它们可以与其他内容一起被缓存。以这种方式缓存时，从缓存读取时它们会计入输入 token。

* 子内容块（例如 [citations](https://platform.claude.com/docs/en/build-with-claude/citations)）本身不能直接缓存。应改为缓存顶层块。

  对于 citations，作为 citations 源材料的顶层文档内容块可以缓存。这样你可以通过缓存 citations 将引用的文档，有效地将 Prompt Caching 与 citations 一起使用。

* 空文本块不能缓存。

### 哪些会使缓存失效:

| 变更内容                                    | Tools 缓存 | System 缓存 | Messages 缓存 | 影响                                                         |
| ------------------------------------------- | ---------- | ----------- | ------------- | ------------------------------------------------------------ |
| **工具定义**                                | ✘          | ✘           | ✘             | 修改工具定义（名称、描述、参数）会使整个缓存失效             |
| **Web search 开关**                         | ✓          | ✘           | ✘             | 启用/禁用 web search 会修改 system prompt                    |
| **Citations 开关**                          | ✓          | ✘           | ✘             | 启用/禁用 citations 会修改 system prompt                     |
| **速度设置**                                | ✓          | ✘           | ✘             | 在 [`speed: "fast"` 与标准速度](https://platform.claude.com/docs/en/build-with-claude/fast-mode) 之间切换会使 system 和 message 缓存失效 |
| **Tool choice**                             | ✓          | ✓           | ✘             | 对 `tool_choice` 参数的更改只影响 message 块                 |
| **图像**                                    | ✓          | ✓           | ✘             | 在 prompt 任意位置添加/移除图像会影响 message 块             |
| **Thinking 参数**                           | 因模型而异 | 因模型而异  | ✘             | thinking 配置（模式，以及 extended mode 中的 `budget_tokens`）会被渲染进 prompt，因此更改它总会使 message 块失效；在把该配置渲染在它们之前的模型上，tool 和 system 缓存也会失效。参见 [Thinking and prompt caching](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-prompt-caching)。 |
| **Effort 设置**                             | 因模型而异 | 因模型而异  | ✘             | 更改 [`output_config.effort`](https://platform.claude.com/docs/en/build-with-claude/effort) 值总会使 message 块失效，对 tool 和 system 缓存的模型相关影响与 thinking 参数相同。将 effort 显式设为模型默认值等价于省略它，不会使缓存失效。在支持[逐条消息 effort](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta) 的模型上，通过 `messages` 内 `role: "system"` 消息携带的 effort 变更会保持缓存前缀完好。 |
| **传入 extended thinking 请求的非工具结果** | ✓          | ✓           | 因模型而异    | 在 Opus 4.5+ 和 Sonnet 4.6+ 上，thinking 块默认被保留，因此缓存仍然有效（✓）。在更早的 Opus/Sonnet 模型以及所有 Haiku 模型上，所有先前已缓存的 thinking 块会从上下文中剥离，跟随这些 thinking 块的任何消息也会从缓存中移除（✘）。更多详情见 [Caching with thinking blocks](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#caching-with-thinking-blocks)。 |
| **被丢弃的 thinking 块**                    | ✓          | ✓           | ✘             | 当 API 丢弃一个在该请求上未被[保留](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-thinking) 的 Claude Fable 5.1 或 Claude Mythos 5.1 thinking 块时（例如，你把它重放到更早的模型），该请求上从该块位置起的缓存前缀会发生变化。接收模型能够读取、且原样传回的块会保持缓存完好。 |

### 理解token分解

  `input_tokens` 字段只表示请求中**最后一个缓存断点之后**的 token——并非你发送的全部输入 token。

### 缓存存储和共享

Prompt Caching使用workspace级别隔离


## 预热缓存

在用户的真实请求之前,把system prompt或者tools等加载进prompt cache中
降低TTFT

### 工作原理:

在请求中设置 `max_tokens: 0`。API 将你的 prompt 读入模型，并在任何 `cache_control` 断点处写入缓存，然后立即返回而不生成任何输出。响应包含空的 `content` 数组、`stop_reason: "max_tokens"`，以及完整填充的 `usage` 块。
将 `cache_control` 断点放在与后续请求共享的最后一个块上
这意味着应使用[显式缓存断点](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#explicit-cache-breakpoints)而不是[自动缓存](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching)，因为自动缓存会把断点放在最后一个块上，而这里最后一个块就是占位符。占位用户消息可以是任何含非空白内容的字符串（此处示例使用 `"warmup"`）

# Mid-conversation system messages and tool changes

## 基础内容

System指令通常放在顶层的System字段当中,非常适合Prompt Caching
Mid-conversation system message可以在不改变顶层System字段的情况下,追加{role: system}指令,且不会将其视为text文本而是视为system指令

## Mid-conversation tool change

tool数组在prefix中的位置比顶层的system字段还要靠前,编辑它会使缓存失效
Mid-conversation tool change机制允许你不需要把工具列表固定为整段对话生命周期内不变,而是可以在turn之间更改向模型提供哪些工具:
预先在tools中声明完整的工具集,然后使用tool_addition和tool_removal块,在对话中提供工具或者撤回工具,而tools数组本身不改变
tool_addition和tool_removal是role: system消息的content block
每个块的tool字段引用一项工具而不是定义工具:{"type": "tool_reference", "name": "..."}
tools中生命的某项工具从对话开始就会提供给模型,除非声明时哎呦defer_loading: true,就会被保留直到tool_addition将其呈现出来
此外tool_addition也可以重新提供之前被tool_removal的工具

## 何时使用mid-conversation system message:

会话中的mid-conversation把指令加在消息历史的末尾

## 工作原理

指令冲突时,较后的system message优先于较前的,相应的,mid-conversation system message优先级高于顶层system字段
`role: "system"` 消息还可以携带 `output_config.effort`，从下一个 `user` turn 起更改 [effort](https://platform.claude.com/docs/en/build-with-claude/effort) 级别(此处的effort为占位符,具体为论文low,high等等)

### system message的位置:

在user turn(或者是server tool result结尾的assistant)之后,并且必须是messages中的最后一项或者紧接着的一个assistant turn.
放在交付tool result的user之后,下一个turn之前

### 放在tool result之后

```
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

此模式用于转达来自该对话最终用户本人的输入。不要用它传递工具输出、检索到的文档或其他第三方内容；将这些内容放在 `tool_result` 块中（参见 [限制](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#limitations)）。

### 限定当前turn的system message:

使用clear_at字段,它有两个取值:

- "never":该消息在包含它的每次请求中都会在其位置渲染
- "next_user_message":限定当前turn的,其文本仅在message中其后灭有role: user消息时渲染
  此外,仅携带tool_result的user消息也算用户消息

一旦存在更后恶的user_message,该消息就会被清除,仍留在数组中但是不渲染也不占输入


限定当前turn的消息的规则:

- 应该逐字重发已经清除的消息而不是更改clear_at值
- type仅限于文本
- 其block上不能有cache_control
- 位置规则依然生效,无论是否被清除
- assistant turn不会清除它,只有user message会清除它
- token count更碎渲染内容,被清除的消息不会增加user.input_token,也不会增加token计数
- 导出,在被清除之后就不被渲染

## 限制

- 不能作为第一条消息,毕竟你为什么不放在顶层的system字段中呢?
- 放置的位置收到约束
- 限制在当前turn的system的type仅限为文本
- 不要放置在不受信任的地方

# Build an orchestration mode

编排模式是一个会话级别的开关:当开启时,对于每一个任务都是最大级别的effort(agent的思考程度),并将工作默认fan-out给并行的子代理

该模式不是API参数,是由文档中的已有的组件构成的:

1. 1.effort级别:最大的effort的取值
2. a refresher:一条mid-conversation system message告知模式的开启,并且每隔几个对话带一行刷新提醒,并在关闭模式的时候发出通知
3. 工具描述中的持续性授权

note:fan-out会成本的增加成本
实际上使用subagent就是很烧钱

## 设置循环

三个参数:
`MAX_CONCURRENT` 限制同时运行的子代理数量;
`MAX_TOTAL_SUBTASKS` 限制模型在单次 Workflow 调用中可以排队的数量;
当设置了环境变量 `DOC_TEST_MODE` = TRUE 时，该检查会把循环限制为单轮，以便自动化文档 harness 验证文件能够编译并迅速结束，而无需跑完整编排
通过常量来控制effort的等级(实际上就是最高的effort),fan-out的形态和refresher的频率

## 定义模式refresher和notice(包括ENTER和EXIT)

这些message都刻意地写的很短,他们切换模式并且指向工具描述(workflow工具)--重量级的指令就在那
ENTER只在开启模式时发送一次,refresh则每隔几个turns发送一次,exit_notice则只在模式关闭的时候发送一次

## 在工具描述中授予持续性权限

Workflow工具承载真正的行为契约:
opt-in规则(指的是进入编排模式的规则是需要用户主动同意的),模式开启期间适用的持续性授权,用于确定fan-out规模的粒度指引,还有模式可以采取的质量检测模式如:验证波、完备性批评者、多阶段分步

而子代理则会得到一个report_finging工具,使其结果JSON结构化
bash工具则是Anthropic定义的bash_20250124,在本地运行

Workflow_tool定义非常的长,有兴趣自己去看一看

## 在本地运行bash工具

为什么会强调是本地运行呢?
强调你harness的运行环境,比如Windows,Linux,云服务器等等

Bash处理器运行带有timeout的命令,并且捕获合并后的stdout和stderr并截断结果,防止失控命令淹没上下文
命令的运行环境就是你启动模式对应的文件目录
而当你设置了DOC_TEST_MODE= TRUE时,harness会改为给bash一个小型的一次性目录,在退出时直接删除

## 运行一个子代理Subagent

每一个workflow的子任务都会变成带bash工具的小型代理循环,并且effort等级于主agent相等
每次API调用都有按请求的超时上限,所以连接中断只会让一个子代理降级,而不会卡住整个运行

## 将结果写入jouornal,方便重跑时continue

启动子代理冲头开始的成本很高,一个小型的基于内容寻址的journal使其幂等:
在fan-out subagent之前,现在本地的JSON文件中寻找它的prompt的SHA-256,如果已经有记录了就返回该结果.中断运行后再跑,就只有没有完成的子任务会被重新计算
journal会在多次运行中去重,但是不会在单次fan-out内去重
如果你想从头再来,那你就删掉journal

## 先fan-out,再验证

fan-out 最多接受 `MAX_TOTAL_SUBTASKS` 条 prompt，经 journal 运行，同时进行中的不超过 `MAX_CONCURRENT` 个,并隔离失败,使得一个损坏的子代理降级为字符串,而不是使得整个运行失败
第一波fan-out完成之后,会复用同一条子代理路径,视图反驳每一条结果

## 用Mid-conversation的system message切换模式

代理先追加用户信息,再追加本轮的system message,这样更适合于prompt caching

## 迈向生产级Harness

- 带沙箱的编排脚本
- 持久journaling
- 预算强制

# Cache diagnostics



在没有Cache diagnostic的情况下,缓存失效的唯一信号是usage.cache_read_input_tokens = 0
Cache diagnostic通过API对比两次请求,告诉你他们在哪处分叉(（model、system prompt、tools 或消息历史）),而你需要做的仅仅是传入上一次响应的ID
解析:通过分析请求的前缀结构,来查看前后两次请求的前缀最开始的不匹配处也就是分叉处

## How to work

当beta header存在,API会给每个request存储一份fingerprint,且将其与id建立起key-value的关系,而在下一次的请求中,将该 `id` 作为`diagnostics.previous_message_id` 传入
然后API会给新的request创建一个新的fingerprint,通过id访问前一个请求的fingerprint和当前请求的fingerprint进行对比
对比针对的是请求的结构,与缓存实际命中无关,所以结合起来使用可以帮助你分析为什么缓存失效了
fingerprint的内容包括:
哈希和token数量估计(绝对不包含原始的prompt),保存时间有限且scope为你的workspace

## 基本用法:

每一次turn都发送beta header,第一次传入的id为null,后续每一次请求传入上一次响应中的id

## Stream:

在stream中,diagnostic出现在message_start事件上
message_start事件携带完整的diagnostic字段

## 在对话循环中贯穿diagnostic

## 响应格式:

响应message上的diagnostic可能有以下四种状态


| 取值                           | 含义                                                         |
| ------------------------------ | ------------------------------------------------------------ |
| 字段缺失                       | 请求未包含 `diagnostics`，或缺少 beta header。               |
| `null`                         | 要么 `previous_message_id` 为 `null`（第一 turn，没有可对比的内容），要么对比已完成且未发现分叉。 |
| `{"cache_miss_reason": null}`  | 响应序列化时对比仍在进行。响应启动非常快时可能出现这种情况。将其视为尚无结论，并在下一 turn 再检查。 |
| `{"cache_miss_reason": {...}}` | 附带了 `cache_miss_reason`。对于 `*_changed` 类型，它标识第一个分歧点；`previous_message_not_found` 和 `unavailable` 表示未产生对比结果。 |

当cache miss!= null时,形态如下:


```
{
  "id": "msg_01Xyz...",
  "type": "message",
  "role": "assistant",
  "content": [{ "type": "text", "text": "..." }],
  "usage": {
    "input_tokens": 42,
    "cache_read_input_tokens": 0,
    "cache_creation_input_tokens": 41850,
    "output_tokens": 210
  },
  "diagnostics": {
    "cache_miss_reason": {
      "type": "system_changed",
      "cache_missed_input_tokens": 41850
    }
  }
}
```

## 缓存未命中原因类型

| 类型                         | 含义                                                         | 需要改什么                                                   |
| ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `model_changed`              | `model` 与上一次请求不同（例如路由器、A/B 测试或回退选择了不同的 model）。缓存是按 model 隔离的。 | 在使用缓存的对话中保持 model 不变。                          |
| `system_changed`             | `system` 参数不同。通常是时间戳、request ID 或其他每次请求都会变的值被插入到了 system prompt 中。 | 将 system prompt 做成逐字节稳定的常量，并把动态数据移到缓存断点之后的第一条 `user` 消息中。 |
| `tools_changed`              | `tools` 数组不同：turn 之间添加、删除或重排了 tools，或者 tool 的 `input_schema` JSON 序列化不稳定。 | 每一 turn 以固定顺序发送相同的 tool 列表，并使用确定性序列化的 schema（例如对 key 排序）。 |
| `messages_changed`           | model、system 和 tools 都匹配，但 `messages` 中更早的某条被改动、重排或删除，而不是追加。通常是对话历史被截断或编辑，或在重发时 assistant turn 和 `tool_result` 块被以不同方式重新序列化。 | 将历史视为只追加；原样回传 assistant `content` 和 tool 结果。 |
| `previous_message_not_found` | 所提供的 `previous_message_id` 没有对应的已存储 fingerprint。这并不证明你的请求发生了变化。通常是上一次请求未携带 beta header、来自不同的 workspace，或距离发送已经过了太久。 | 每一 turn 都发送 beta header，并让连续 turn 在时间上尽量靠近。 |
| `unavailable`                | 本次请求没有可用的 diagnostic 信息。包括 `model`、`system` 和 `tools` 都匹配，但另一个会影响 prompt 的请求参数（`tool_choice`、`thinking`、`context_management`、`output_config`、`output_format`，或当前生效的 `anthropic-beta` header 集合）不同，以及超长对话中分歧点超出对比范围的情况。你的请求已正常处理。 | 在使用缓存的对话生命周期内，保持会影响 prompt 的请求参数不变。若问题持续，按提示词缓存页面 [排查常见问题](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#troubleshooting-common-issues) 下的手动检查处理。 |

note:

  四种 `*_changed` 类型还会附带一个 `cache_missed_input_tokens` 整数：估计有多少 input token 落在分歧点之后，让你对损失了多少可缓存前缀有个量级感。该值由 tokenization 之前的字节长度推导，因此应视为量级指标而非计费数字。它可能与 `usage.input_tokens` 不同（偶尔还会更大）。

## 结合usage解读diagnostic

`diagnostics` 回答「我的请求变了吗？
`usage.cache_read_input_tokens` 回答「缓存命中了吗？」
两者结合可惜分析缓存未命中的原因

| agnostics 结果                          | 缓存读取 token | 解读                                                         |
| --------------------------------------- | -------------- | ------------------------------------------------------------ |
| `null`                                  | 高             | 符合预期。你的前缀稳定且缓存命中。                           |
| `null`                                  | 低或为零       | 请求匹配，但缓存条目已不再可用。考虑缩短 turn 之间的间隔，或使用 [1 小时缓存 TTL](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)。 |
| `cache_miss_reason` 为 `*_changed` 类型 | 低或为零       | 你这边的 bug。请求发生了变化；按 `type` 所示原因修复。       |
| `cache_miss_reason` 为 `*_changed` 类型 | 高             | 少见。变化发生在 prompt 较后位置，但更早的 `cache_control` 断点仍然命中。值得修复，但影响较小。 |

# Token counting

作用:在你把message发给Claude之前确定其中的token数量

## 

## 如何统计 message tokens

[token counting](https://platform.claude.com/docs/en/api/messages-count-tokens) endpoint 接受与创建 message 相同的结构化输入列表，包括对 system prompt、[tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview)、[images](https://platform.claude.com/docs/en/build-with-claude/vision) 和 [PDFs](https://platform.claude.com/docs/en/build-with-claude/pdf-support) 的支持。响应中包含输入 tokens 的总数。

对于 Messages API 会接受、但本 endpoint 不接受的少数输入，该 endpoint 会返回 `invalid_request_error`：例如 web search、web fetch、code execution 和 tool search 等 [server tools](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools)（[advisor tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool) 除外的所有 server tool）、[MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector)，以及 `source` 为 `url` 或 `file` 的 `image` 或 `document` blocks。统计图片和 PDF 时请以 base64 发送。对于使用 server tools 或 MCP servers 的请求，Messages API 响应会在其 `usage` 对象中报告所用 tokens。

<Note>
  Token 计数是一个**估计**。在某些情况下，创建 message 时实际使用的输入 tokens 数量可能有小幅差异。

  Token 计数可能包含 Anthropic 为系统优化自动添加的 tokens。**系统添加的 tokens 不会向你计费**。计费只反映你的内容。
</Note>