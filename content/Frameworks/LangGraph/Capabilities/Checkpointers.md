+++
title = "Checkpointers"
slug = "checkpointers"
weight = 11
categories = ["Frameworks", "LangGraph"]
tags = ["LangGraph", "Agent"]
description = "Checkpointers相关学习笔记与实践要点。"
+++
Checkpointer在每个super-step之后保存图状态的 snapshot(快照),并且按照thread进行组织

# Why use checkpointers

适用于以下的场景:

- Human-in-the-loop:从interrupt中恢复运行
- Memory:在交互之间保存memory,说直白点就是conversation history
- Time travel:重放之前的图执行来调试或者审批;从外,允许fork(分叉)图状态
- Fault-tolerance:从错误中恢复
- Pending writes:在super-step中途失败时,可以恢复到之前成功的checkpoints

# Core concepts

## Thread

是分配给每个检查点的唯一ID或者标识符
包含一次运行的累计状态;当执行运行时,graph state会被持久化到这个线程中

当适用checkpointer调用graph 时,必须要在configurable中指明thread_id

线程的现状和历史状态都可以被检索.为了持久化,在执行运行之前必须创建一个线程

thread_id是存储和查询 checkpoints的主键

# Checkpoints

线程中特定时间的state叫做checkpoint
是对每个super-step保存的graph state snapshot,由StateSnapshot对象表示

## Super-steps

LangGraph会在每个super-step边界常见checkpoint
resume只能从checkpoint执行

除了超级步骤检查点外，LangGraph 还会持久化**节点（任务）级别**的写入。随着超级步骤中的每个节点完成，其输出将作为链接到进行中检查点的任务条目写入检查点保存器的 `checkpoint_writes` 表中。这些按任务进行的写入支持了[待处理写入](https://docs.langchain.org.cn/oss/python/langgraph/checkpointers#pending-writes)恢复：如果同一超级步骤中的另一个节点失败，已成功节点的写入已经是持久化的，在恢复时无需重新运行。超级步骤完成后，将提交完整的状态快照。

LangGraph 还会持久化超级步骤内单个节点执行的写入。这些写入以任务形式存储并用于容错：如果同一超级步骤中的另一个节点失败，恢复时无需重新计算成功的节点写入。这些任务写入不是完整的 `StateSnapshot` 检查点，因此时间旅行会从超级步骤边界的完整检查点恢复。

## checkpoints namespace

每个检查点都有一个namespace_ns字段,来标识属于哪个图或者子图

- ""(空字符串):属于父(根)图
- "node_name: uuid": 属于给定节点调用的子图;对于嵌套子图，命名空间使用 `|` 分隔符连接（例如 `"outer_node:uuid|inner_node:uuid"`）

你可以在node内部通过config访问checkpoint namespace

```py
from langchain_core.runnables import RunnableConfig

def my_node(state: State, config: RunnableConfig):
    checkpoint_ns = config["configurable"]["checkpoint_ns"]
    # "" for the parent graph, "node_name:uuid" for a subgraph
```

# Get and update state

## Get state

调用graph.get_state(config)查看图的最新状态,会返回一个`StateSnapshot`对象,对应提供的线程ID所关联的最新checkpoint,或者提供特定的checkpoint_id访问特定的checkpoint

```
# get the latest state snapshot
config = {"configurable": {"thread_id": "1"}}
graph.get_state(config)

# get a state snapshot for a specific checkpoint_id
config = {"configurable": {"thread_id": "1", "checkpoint_id": "1ef663ba-28fe-6528-8002-5a559208592c"}}
graph.get_state(config)
```

### StateSnapshot fields

| Field           | Type                     | Description                                                  |
| :-------------- | :----------------------- | :----------------------------------------------------------- |
| `values`        | `dict`                   | State channel values at this checkpoint.                     |
| `next`          | `tuple[str, ...]`        | Node names to execute next. Empty `()` means the graph is complete. |
| `config`        | `dict`                   | Contains `thread_id`, `checkpoint_ns`, and `checkpoint_id`.  |
| `metadata`      | `dict`                   | Execution metadata. Contains `source` (`"input"`, `"loop"`, or `"update"`), `writes` (node outputs), and `step` (super-step counter). |
| `created_at`    | `str`                    | ISO 8601 timestamp of when this checkpoint was created.      |
| `parent_config` | `dict | None`            | Config of the previous checkpoint. `None` for the first checkpoint. |
| `tasks`         | `tuple[PregelTask, ...]` | Tasks to execute at this step. Each task has `id`, `name`, `error`, `interrupts`, and optionally `state` (subgraph snapshot, when using `subgraphs=True`). |

## Get state history

通过调用 [`graph.get_state_history(config)`](https://reference.langchain.org.cn/python/langgraph/graphs/#langgraph.graph.state.CompiledStateGraph.get_state_history)获得对应thread_id的完整图执行历史记录,返回`StateSnapshot`对象列表,按照时间和顺序排序,最新的检查点为第一个元素

### Find a specific checkpoint

通过筛选过滤满足特定条件的checkpoints

## Replay

适用chexkpoint_id可以重新运行该检查点之后的节点,跳过之前的节点

## Update state

适用`update_state`编辑graph state,这会创建一个包含更新值新的checkpoint:如果规定了reducer函数,值会通过reducer函数传递
可以指定as_node来控制更新被视为来自哪个node,这会影响接下来执行哪个node

# Durabilty modes(持久化模式)

提供了三种模式来在性能和数据一致性之间取得平衡

- "exit":只在退出时持久化变更
- "async":在执行下一步的同时异步持久化变更
- "sync":在下一步开始之前同步持久化变更

# Optimize checkpoint storage

[`DeltaChannel`](https://reference.langchain.org.cn/python/langgraph/channels/delta/DeltaChannel) 仅存储增量变更（deltas）而非完整的累积值，大幅降低了对于追加频繁的通道的检查点大小

# Checkpointer libraries

- `langgraph-checkpoint`：检查点保存器基础接口（[`BaseCheckpointSaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.base.BaseCheckpointSaver)）和序列化/反序列化接口（[`SerializerProtocol`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.serde.base.SerializerProtocol)）。包含用于实验的内存中检查点保存器实现（[`InMemorySaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.memory.InMemorySaver)）。LangGraph 自带包含 `langgraph-checkpoint`。
- `langgraph-checkpoint-sqlite`：使用 SQLite 数据库的 LangGraph 检查点保存器实现（[`SqliteSaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.sqlite.SqliteSaver) / [`AsyncSqliteSaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.sqlite.aio.AsyncSqliteSaver)）。非常适合实验和本地工作流。需要单独安装。
- `langgraph-checkpoint-postgres`：使用 Postgres 数据库的高级检查点保存器（[`PostgresSaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.postgres.PostgresSaver) / [`AsyncPostgresSaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.postgres.aio.AsyncPostgresSaver)），在 LangSmith 中使用。非常适合在生产环境中使用。需要单独安装。
- `langchain-azure-cosmosdb`：使用 Azure Cosmos DB for NoSQL 的 LangGraph 检查点保存器实现（[`CosmosDBSaverSync`](https://reference.langchain.org.cn/python/langchain-azure-cosmosdb/) / [`CosmosDBSaver`](https://reference.langchain.org.cn/python/langchain-azure-cosmosdb/)）。非常适合与 Azure 一起在生产环境中使用。支持同步和异步操作，并支持 Microsoft Entra ID 身份验证。需要单独安装。

## Checkpointer interface

- `.put` - 存储包含配置和元数据的检查点。
- `.put_writes` - 存储链接到检查点的中间写入（即[待处理写入](https://docs.langchain.org.cn/oss/python/langgraph/checkpointers#pending-writes)）。
- `.get_tuple` - 获取用于给定配置（`thread_id` 和 `checkpoint_id`）的检查点元组。这用于填充 `graph.get_state()` 中的 `StateSnapshot`。
- `.list` - 列出匹配给定配置和筛选条件的检查点。这用于填充 `graph.get_state_history()` 中的状态历史。

如果检查点保存器与异步图执行一起使用（即通过 `.ainvoke`、`.astream`、`.abatch` 执行图），将使用上述方法的异步版本（`.aput`、`.aput_writes`、`.aget_tuple`、`.alist`）。