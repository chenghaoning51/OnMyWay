+++
title = "Persistence"
slug = "persistence"
weight = 21
categories = ["Frameworks", "LangGraph"]
tags = ["LangGraph", "Agent"]
description = "Persistence相关学习笔记与实践要点。"
+++
需求:continue a conversation, resume from a interrupt, recover from a failure, remember information across conversations
LangGraph提供了两个互补的持久化系统:

`Checkpointer`将线程的graph state持久化为checkpoints
适用场景:short-term memory,thread -scoped memory

`Stores:`将程序规定的数据持久化到graph state之外
适用场景:long-term memory,across-thread memory

# Quickstart

编译你的 graph with a checkpointer ,a store ,or both

```py
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.store.memory import InMemoryStore

checkpointer = InMemorySaver()
store = InMemoryStore()

graph = builder.compile(checkpointer=checkpointer, store=store)

result = graph.invoke(
    {"messages": [{"role": "user", "content": "Hi, my name is Bob."}]},
    {"configurable": {"thread_id": "thread-1"}},
)
```

# Checkpointer vs store

|                | Checkpointer                                                 | Store                                                        |
| :------------- | :----------------------------------------------------------- | :----------------------------------------------------------- |
| Persists       | Graph state snapshots                                        | Application-defined key-value data                           |
| Scope          | A single thread                                              | Across threads                                               |
| Memory type    | Short-term, thread-scoped memory                             | Long-term, cross-thread memory                               |
| Use for        | Conversation continuity, human-in-the-loop, time travel, and fault tolerance | User preferences, facts, and shared knowledge                |
| Access pattern | Pass a `thread_id` in graph config                           | Read and write items from nodes or application code          |
| Full guide     | [Checkpointers](https://docs.langchain.com/oss/python/langgraph/checkpointers) | [Stores](https://docs.langchain.com/oss/python/langgraph/stores) |

# Troubleshooting common issues

## PostgresSaver:`thread_id`too long

使用(Async)PostgresSaver,`thread_id`存储在一个长度受限的列中,如果长度超出限制,则会报错

解决办法:将thread_id保持在255字符之内

## MemorySaver does not persist between restarts

MemorySaver和InMemorySaver 把checkpoints保存在RAM中,重启时,所有的checkpoints会丢失

解决方法:生产环境中使用可持久化的checkpointer

## Checkpoints growing unboundedly

checkpoints无休止增长可能导致延迟和存储的开销

解决方法:定期清理旧的checkpoints或者设置保留策略

## State access from parent graph to subgraph

子图的state更新时,父图不会立马看到这些更新:因为子图管理自己的checkpoint namespace

解决方法:需要跨图边界的数据,使用Store共享状态,或者配置你的子图谢图父checkpoints

