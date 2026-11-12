+++
title = "Cache diagnostics"
slug = "cache-diagnostics"
weight = 50
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "通过对比连续请求，精确定位 prompt 前缀的分歧点，从而诊断意外的提示词缓存未命中。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics"
+++

## 兼容性
- 状态：Beta
- [Beta header](https://platform.claude.com/docs/en/api/beta-headers): `cache-diagnosis-2026-04-07`
- [ZDR](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)（零数据保留）: 符合资格（不包括 [Covered Models](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention#model-specific-data-retention-requirements)）
- 平台：Claude API (beta)；在 Claude Platform on AWS、Amazon Bedrock、Google Cloud、Microsoft Foundry 上不可用

[Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching) 能显著降低延迟和成本，但前提是 prompt 的开头必须与近期某次请求逐字节相同。被重排的 tool、插入到 system prompt 中的时间戳，或对更早消息的编辑，都可能悄无声息地使缓存失效。没有 cache diagnostics 时，唯一信号是 `usage.cache_read_input_tokens` 降为零，却无法得知什么发生了变化。

Cache diagnostics 填补了这一缺口。传入上一次响应的 `id`，API 会对比两次请求，并告诉你它们在何处分叉（model、system prompt、tools 或消息历史），从而让你修复根因，而不是猜测。

## Cache diagnostics 如何工作

当 beta header 存在时，API 会为每个请求存储一份轻量 fingerprint，并以响应 `id` 作为键。在下一次请求中，将该 `id` 作为 `diagnostics.previous_message_id` 传入。API 会为新请求重建 fingerprint，与已存储的那份对比，并在响应上附加一个 `diagnostics` 对象，描述第一个分歧点。

对比针对的是请求结构，与缓存是否实际命中无关。关于如何将 `diagnostics` 结果与 `usage.cache_read_input_tokens` 结合使用，见 [结合 usage 解读 diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#reading-diagnostics-alongside-usage)。

Fingerprint 仅包含哈希和 token 数量估计（绝不包含原始 prompt 内容），保留时间有限，作用域限定在你的 organization 和 workspace，且不会用于任何其他目的。

## 基本用法

每一 turn 都发送 beta header。第一 turn 传入 `"previous_message_id": null` 以选择加入，此时没有可供对比的先前消息。后续 turn 传入上一次响应中的 `id`。

<CodeGroup>

  ```python Python
  client = anthropic.Anthropic()

  SYSTEM = "You are an AI assistant analyzing a large document. <document>...</document>"

  # Turn 1: opt in with previous_message_id=None
  r1 = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=1024,
      cache_control={"type": "ephemeral"},
      system=SYSTEM,
      messages=[{"role": "user", "content": "Summarize section 1."}],
      diagnostics={"previous_message_id": None},
      betas=["cache-diagnosis-2026-04-07"],
  )

  # Turn 2: reference the previous response id
  r2 = client.beta.messages.create(
      model="claude-opus-5",
      max_tokens=1024,
      cache_control={"type": "ephemeral"},
      system=SYSTEM,
      messages=[
          {"role": "user", "content": "Summarize section 1."},
          {"role": "assistant", "content": r1.content},
          {"role": "user", "content": "Now summarize section 2."},
      ],
      diagnostics={"previous_message_id": r1.id},
      betas=["cache-diagnosis-2026-04-07"],
  )

  diagnostics = r2.diagnostics
  if diagnostics is None:
      print("No divergence detected.")
  elif diagnostics.cache_miss_reason is None:
      print("Comparison still pending.")
  else:
      print(f"cache_miss_reason: {diagnostics.cache_miss_reason.type}")
  ```

</CodeGroup>

## 流式

在流式响应中，`diagnostics` 出现在 `message_start` 事件上。

<CodeGroup>

  ```python Python
  # Turn 2: stream, referencing the previous response id
  with client.beta.messages.stream(
      model="claude-opus-5",
      max_tokens=1024,
      cache_control={"type": "ephemeral"},
      system=SYSTEM,
      messages=[
          {"role": "user", "content": "Summarize section 1."},
          {"role": "assistant", "content": r1.content},
          {"role": "user", "content": "Now summarize section 2."},
      ],
      diagnostics={"previous_message_id": r1.id},
      betas=["cache-diagnosis-2026-04-07"],
  ) as stream:
      for text in stream.text_stream:
          print(text, end="", flush=True)
      print()
      r2 = stream.get_final_message()

  diagnostics = r2.diagnostics
  if diagnostics is None:
      print("No divergence detected.")
  elif diagnostics.cache_miss_reason is None:
      print("Comparison still pending.")
  else:
      print(f"cache_miss_reason: {diagnostics.cache_miss_reason.type}")
  ```

</CodeGroup>

`message_start` 事件携带完整的 `diagnostics` 字段；可能的取值见 [响应格式](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#response-format)。

## 在对话循环中贯穿 diagnostics

在多 turn 对话中，每一 turn 都将最新响应的 `id` 作为 `previous_message_id` 向前传递。第一次迭代传入 `null` 以选择加入；之后每次迭代传入上一次响应中的 `id`。

<Tabs>
  <Tab title="cURL">
    <Info>
      该工作流不太适合写成一次性的 shell 命令。循环模式见 SDK 各 tab；每一 turn 的 HTTP 请求与 [基本用法](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#basic-usage) 相同。
    </Info>
  </Tab>

  <Tab title="CLI">
    <Info>
      该工作流不太适合写成一次性的 shell 命令。循环模式见 SDK 各 tab；每一 turn 的 CLI 调用与 [基本用法](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#basic-usage) 相同。
    </Info>
  </Tab>

  <Tab title="Python">
    ```python
    client = anthropic.Anthropic()

    SYSTEM = "You are an AI assistant analyzing a large document. <document>...</document>"
    
    messages = []
    prev_id = None
    
    for i, user_message in enumerate(
        ["Summarize section 1.", "Now section 2.", "Now section 3."]
    ):
        messages.append({"role": "user", "content": user_message})
    
        r = client.beta.messages.create(
            model="claude-opus-5",
            max_tokens=1024,
            cache_control={"type": "ephemeral"},
            system=SYSTEM,
            messages=messages,
            diagnostics={"previous_message_id": prev_id},
            betas=["cache-diagnosis-2026-04-07"],
        )
    
        if r.diagnostics is not None and r.diagnostics.cache_miss_reason is not None:
            print(f"Turn {i + 1} cache_miss_reason: {r.diagnostics.cache_miss_reason.type}")
    
        messages.append({"role": "assistant", "content": r.content})
        prev_id = r.id
    ```


## 响应格式

响应 `Message` 上的 `diagnostics` 字段有四种可能状态：

| 取值                           | 含义                                                         |
| ------------------------------ | ------------------------------------------------------------ |
| 字段缺失                       | 请求未包含 `diagnostics`，或缺少 beta header。 |
| `null`                         | 要么 `previous_message_id` 为 `null`（第一 turn，没有可对比的内容），要么对比已完成且未发现分叉。 |
| `{"cache_miss_reason": null}`  | 响应序列化时对比仍在进行。响应启动非常快时可能出现这种情况。将其视为尚无结论，并在下一 turn 再检查。 |
| `{"cache_miss_reason": {...}}` | 附带了 `cache_miss_reason`。对于 `*_changed` 类型，它标识第一个分歧点；`previous_message_not_found` 和 `unavailable` 表示未产生对比结果。 |

当 `cache_miss_reason` 非 null 时，形态如下：

```json
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

`cache_miss_reason` 是以 `type` 为判别字段的联合类型。响应只报告最早的分歧点，因此先修复它；更后面的分歧可能被它挡住。

| 类型                         | 含义                                                         | 需要改什么                                                   |
| ---------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `model_changed`              | `model` 与上一次请求不同（例如路由器、A/B 测试或回退选择了不同的 model）。缓存是按 model 隔离的。 | 在使用缓存的对话中保持 model 不变。        |
| `system_changed`             | `system` 参数不同。通常是时间戳、request ID 或其他每次请求都会变的值被插入到了 system prompt 中。 | 将 system prompt 做成逐字节稳定的常量，并把动态数据移到缓存断点之后的第一条 `user` 消息中。 |
| `tools_changed`              | `tools` 数组不同：turn 之间添加、删除或重排了 tools，或者 tool 的 `input_schema` JSON 序列化不稳定。 | 每一 turn 以固定顺序发送相同的 tool 列表，并使用确定性序列化的 schema（例如对 key 排序）。 |
| `messages_changed`           | model、system 和 tools 都匹配，但 `messages` 中更早的某条被改动、重排或删除，而不是追加。通常是对话历史被截断或编辑，或在重发时 assistant turn 和 `tool_result` 块被以不同方式重新序列化。 | 将历史视为只追加；原样回传 assistant `content` 和 tool 结果。 |
| `previous_message_not_found` | 所提供的 `previous_message_id` 没有对应的已存储 fingerprint。这并不证明你的请求发生了变化。通常是上一次请求未携带 beta header、来自不同的 workspace，或距离发送已经过了太久。 | 每一 turn 都发送 beta header，并让连续 turn 在时间上尽量靠近。 |
| `unavailable`                | 本次请求没有可用的 diagnostic 信息。包括 `model`、`system` 和 `tools` 都匹配，但另一个会影响 prompt 的请求参数（`tool_choice`、`thinking`、`context_management`、`output_config`、`output_format`，或当前生效的 `anthropic-beta` header 集合）不同，以及超长对话中分歧点超出对比范围的情况。你的请求已正常处理。 | 在使用缓存的对话生命周期内，保持会影响 prompt 的请求参数不变。若问题持续，按提示词缓存页面 [排查常见问题](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#troubleshooting-common-issues) 下的手动检查处理。 |

<Note>
  四种 `*_changed` 类型还会附带一个 `cache_missed_input_tokens` 整数：估计有多少 input token 落在分歧点之后，让你对损失了多少可缓存前缀有个量级感。该值由 tokenization 之前的字节长度推导，因此应视为量级指标而非计费数字。它可能与 `usage.input_tokens` 不同（偶尔还会更大）。
</Note>

## 结合 usage 解读 diagnostics

`diagnostics` 回答「我的请求变了吗？」，而 `usage.cache_read_input_tokens` 回答「缓存命中了吗？」。两者结合能告诉你该往哪看。

该矩阵适用于传入了真实 `previous_message_id` 的 turn。第一 turn（`previous_message_id: null`）时，`diagnostics` 始终为 `null`，且 `cache_read_input_tokens` 通常为零，因为缓存正在写入而非读取；无需排查。当 `cache_miss_reason` 为 `null`（对比仍在进行；检查下一 turn），或其 `type` 为 `previous_message_not_found` 或 `unavailable`（未产生对比）时，该矩阵同样不适用。

| Diagnostics 结果                          | 缓存读取 token    | 解读                                                         |
| ----------------------------------------- | ----------------- | ------------------------------------------------------------ |
| `null`                                    | 高                | 符合预期。你的前缀稳定且缓存命中。 |
| `null`                                    | 低或为零          | 请求匹配，但缓存条目已不再可用。考虑缩短 turn 之间的间隔，或使用 [1 小时缓存 TTL](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration)。 |
| `cache_miss_reason` 为 `*_changed` 类型   | 低或为零          | 你这边的 bug。请求发生了变化；按 `type` 所示原因修复。 |
| `cache_miss_reason` 为 `*_changed` 类型   | 高                | 少见。变化发生在 prompt 较后位置，但更早的 `cache_control` 断点仍然命中。值得修复，但影响较小。 |

## 限制

* **Beta：** 该功能处于 beta 期间，字段名和语义可能会变化。
* **仅 Claude API：** 在 Amazon Bedrock 或 Google Cloud 上不可用。
* **保留时间有限：** 用于 `previous_message_id` 查找的 fingerprint 会在短时间后过期。在间隔较近的请求之间运行 diagnostic 对比。
* **同一 workspace：** 上一次请求必须运行在同一 organization 和 workspace。要核对此点，对比两次响应上的 `anthropic-workspace-id` [响应 header](https://platform.claude.com/docs/en/api/overview#response-headers)。
* **对比范围：** 对于超长对话，若唯一变化深藏在消息列表中，响应可能是 `unavailable` 而非精确位置。
* **尽力而为：** Diagnostics 从不阻塞或导致请求失败。若 diagnostic 信息不可用，响应会返回 `unavailable`，或在对比仍在进行时返回 `cache_miss_reason: null`。

## 数据保留

Cache diagnostics 符合 ZDR 资格（qualified）。Anthropic 不会为此功能存储你的 prompt 原文或 Claude 的输出。

为每个请求存储的 fingerprint 仅包含加密哈希和 token 数量估计，以响应 `id` 为键，作用域限定在你的 organization 和 workspace。Fingerprint 会在短时间后过期，且不会用于任何其他目的。

各功能的 ZDR 资格，见 [API 与数据保留](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)。

## 另见

* [Prompt Caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
* [Token counting](https://platform.claude.com/docs/en/build-with-claude/token-counting)
* [Beta headers](https://platform.claude.com/docs/en/api/beta-headers)
