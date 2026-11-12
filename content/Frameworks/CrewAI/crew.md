+++
title = "Crew"
slug = "crew"
weight = 12
categories = ["Frameworks", "CrewAI"]
tags = ["CrewAI", "Agent"]
description = "Crew相关学习笔记与实践要点。"
+++
# Crew

## 概念:

代表一组协作工作的agent,共同完成一系列的任务

## 属性

必须:tasks,agents
剩下的均为可选,请自行前往官网查阅

## 创建crew

两种方法:YAML配置(推荐)和直接再代码中定义

### YAML中配置

继承自CrewBase并使用装饰器定义agent,task和本身的类

@agent,@taks,@crew,@before_kickoff,@after_kickoff

#### 几种装饰器的概述

- `@CrewBase`: 将类标记为船员基类。
- `@agent`: 表示返回 `Agent` 对象的方法。
- `@task`: 表示返回 `Task` 对象的方法。
- `@crew`: 表示返回 `Crew` 对象的方法。
- `@before_kickoff`: (可选) 标记在船员启动前执行的方法。
- `@after_kickoff`: (可选) 标记在船员完成执行后执行的方法。

### 直接代码定义

## CrewOutput

CrewAI框架中crew的输出封装再CrewOutput类中,提供了一种结构化的方法来访问crew的执行结果,包括原始字符串,JSON和Pydantic模型等各种格式
包含的内容:最终任务输出的结果,token使用情况以及单个任务的输出

### 属性

| 属性               | 参数           | 类型                       | 描述                                                        |
| :----------------- | :------------- | :------------------------- | :---------------------------------------------------------- |
| **原始**           | `raw`          | `str`                      | 船员的原始输出。这是输出的默认格式。                        |
| **Pydantic**       | `pydantic`     | `Optional[BaseModel]`      | 表示船员结构化输出的 Pydantic 模型对象。                    |
| **JSON 字典**      | `json_dict`    | `Optional[Dict[str, Any]]` | 表示船员 JSON 输出的字典。                                  |
| **任务输出**       | `tasks_output` | `List[TaskOutput]`         | `TaskOutput` 对象的列表，每个对象代表船员中一个任务的输出。 |
| **Token 使用情况** | `token_usage`  | `Dict[str, Any]`           | token 使用情况摘要，提供关于语言模型在执行期间性能的洞察。  |

### 方法或者属性

| 方法/属性                  | 描述                                                         |
| :------------------------- | :----------------------------------------------------------- |
| **json**                   | 如果输出格式为 JSON，则返回船员输出的 JSON 字符串表示。      |
| **to_dict 转换为字典格式** | 将 JSON 和 Pydantic 输出转换为字典。                         |
| **str 字符串**             | 返回船员输出的字符串表示，优先级为 Pydantic，然后是 JSON，最后是原始。 |

### 访问输出

通过crew对象的output属性访问输出


## 访问Crew日志

通过将 `output_log_file` 设置为 `True(布尔值)` 或 `file_name(字符串)`，您可以实时查看船员执行日志。支持将事件记录为 `file_name.txt` 和 `file_name.json` 两种格式。如果设置为 `True(布尔值)`，将保存为 `logs.txt`。

## 记忆利用

通过存储和回忆执行记忆,来强化执行能力

## 缓存利用

利用缓存存储执行结果,减少重复任务的执行来提供流程效率

## Crew使用指标

通过usage_metrics属性来查看执行所有任务的LLM使用指标

## 执行流程

顺序流程
层级流程:一个管理器进行协调

### 启动crew

使用kickoff()方法启动process

### 几种不同的启动方式

kickoff(),kickoff_for_each(),kickoff_async(),kickoff_for_each_asych()

- `kickoff()`: 根据定义的流程启动执行过程。
- `kickoff_for_each()`: 对集合中提供的每个输入事件或项目顺序执行任务。
- `kickoff_async()`: 异步启动工作流程。
- `kickoff_for_each_async()`: 对提供的每个输入事件或项目并发执行任务，利用异步处理。

### 从特定的任务重放

CLI命令replay重放

CrewAI 中的重放功能允许您使用命令行界面 (CLI) 从特定任务重放。通过运行命令 `crewai replay -t <task_id>`，您可以指定重放过程的 `task_id`。