+++
title = "Graph Engineering"
slug = "graph-engineering"
weight = 21
categories = ["Agent"]
tags = ["Agent", "AI Agents"]
description = "Graph Engineering相关学习笔记与实践要点。"
+++
按照任务之间的依赖关系,用graph来编排整个流程
而loop可以理解为一个节点的循环图

![img](https://cdn.xiaolincoding.com//picgo/adfd1df4_loop-as-smallest-graph.png)

# 工作原理

组成:
节点,边,状态

节点:agent或代码或一次简单操作

边:
负责决定下一步执行哪个节点
确定性边:由提前写进代码的固定规则决定
模型决策边:交给模型判断

状态:
字段固定的任务状态表

```
{
  "backend": {"status": "done", "artifact": "api/export.js"},
  "frontend": {"status": "running"},
  "tests": {"status": "pending"},
  "tokens_used": 12000
}
```

