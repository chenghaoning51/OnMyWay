+++
title = "Agent"
slug = "agent"
weight = 11
categories = ["Frameworks", "CrewAI"]
tags = ["CrewAI", "Agent"]
description = "Agent相关学习笔记与实践要点。"
+++
# Agent

## 概述:

带有特定技能,专业知识和职责的专业团队成员

## 智能体的属性:

最基本的三个
Role,Goal,Backstory
后续全为可选,请自行查阅官网

## 创建智能体

两种方法:
YAML配置(推荐)和直接在代码中定义

### YAML配置(推荐)

在代码中使用YAML配置,需要创建一个继承自CrewBase的工作组类


### 直接代码定义

实例化Agent类直接在代码中创建智能体


## 参数详情:

####  关键参数

- `role`, `goal` 和 `backstory` 是必填项，决定了智能体的行为。
- `llm` 确定使用的语言模型（默认：OpenAI 的 GPT-4）。

#### 记忆与上下文

- `memory`: 启用以保持对话历史。
- `respect_context_window`: 防止 Token 限制问题。
- `knowledge_sources`: 添加特定领域的知识库。

#### 执行控制

- `max_iter`: 给定最佳答案前的最大尝试次数。
- `max_execution_time`: 超时时间（秒）。
- `max_rpm`: API 调用速率限制。
- `max_retry_limit`: 错误重试次数。

#### 代码执行



`allow_code_execution` 和 `code_execution_mode` 已弃用。`CodeInterpreterTool` 已从 `crewai-tools` 中移除。请使用如 [E2B](https://e2b.org.cn/) 或 [Modal](https://modal.com/) 等专用沙箱服务进行安全的代码执行。

- `allow_code_execution` *(已弃用)*: 此前通过 `CodeInterpreterTool` 启用内置代码执行。
- `code_execution_mode` *(已弃用)*: 此前控制执行模式（`"safe"` 用于 Docker，`"unsafe"` 用于直接执行）。

#### 高级功能

- `multimodal`: 启用多模态能力以处理文本和视觉内容。
- `reasoning`: 启用智能体在执行任务前反思并制定计划。
- `inject_date`: 自动将当前日期注入任务描述中。

#### 模板

- `system_template`: 定义智能体的核心行为。
- `prompt_template`: 构建输入格式。
- `response_template`: 格式化智能体响应。

## 智能体工具

可以使用CrewAI和LangChain工具包

## 智能体记忆和上下文

## 上下文窗口管理

### 上下文窗口管理的工作原理

由respect_context_window控制

when context window is too large,
1.自动摘要内容(参数为true)
2.停止执行并且报错(参数为false)

### 大数据量的替代方案

#### 1.RAG工具

#### 2.使用知识源

###  上下文窗口最佳实践

1. **监控上下文使用**: 启用 `verbose=True` 以查看正在运行的上下文管理。
2. **高效设计**: 构建任务以最小化上下文积累。
3. **使用合适的模型**: 选择上下文窗口适合任务的 LLM。
4. **测试两种设置**: 尝试 `True` 和 `False`，看看哪种更适合你的用例。
5. **结合 RAG 使用**: 对于超大数据集，使用 RAG 工具而不是完全依赖上下文窗口。

### 使用Kickoff()进行直接智能体交互

#### 工作原理:

kickoff()允许你直接向智能体发送消息获取回复

#### 参数和返回值

message;response_format