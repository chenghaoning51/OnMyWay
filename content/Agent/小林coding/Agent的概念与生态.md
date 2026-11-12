+++
title = "Agent的概念与生态"
slug = "agent"
weight = 1
categories = ["Agent"]
tags = ["Agent", "AI Agents"]
description = "1.只具有生产能力而不具有执行能力 2.没有记忆,局限于上下文窗口 3.不会用tools 4.不会规划 LLM在循环中自主使用工具的系统(有点太浅了) 针对上面四个问题: 1.function call 2.记忆系统 3.MCP等协议 4.任务规划和拆解能力 1.核心:LLM:理解意图,判断推理 2.规划模块:把复杂任务拆解为可执行..."
draft = false
+++

# Agent的概念与生态

## LLM的弊端:

1.只具有生产能力而不具有执行能力
2.没有记忆,局限于上下文窗口
3.不会用tools
4.不会规划

## Agent:

LLM在循环中自主使用工具的系统(有点太浅了)

针对上面四个问题:
1.function call
2.记忆系统
3.MCP等协议
4.任务规划和拆解能力

### 组成:

1.核心:LLM:理解意图,判断推理
2.规划模块:把复杂任务拆解为可执行的步骤
3.记忆模块:负责存储和检索信息
4.工具模块:与外部世界互动

## Agent和Workflow的区别

Workflow:指LLM和工具通过预定义的代码路径进行编排的系统
Agent:指LLM动态主导自身流程与工具调用的系统,由LLM自主决定如何完成任务

Workflow是预先定义好的,按照固定的顺序执行;agent是由LLM自主动态规划的,且是循环的

### 什么时候用Agent,什么时候用Workflow

**从最简单的方案开始，只在明确需要时才增加复杂度**

如果任务步骤是固定的、可以提前规划好的，或者对可靠性要求很高（比如金融交易、医疗系统），那就用 Workflow。如果任务是开放式的、无法预知所有步骤，或者需要灵活应对各种意外情况，那就用 Agent

在实际过程中,更常见的是混合架构

### Agent有哪些工作模式?

### 模式一:React

Thought -> Action -> Observation
循环工作

优点:透明可审计,灵活
缺点:token消耗量大且有时会陷入循环

### 模式二:Plan-and-Execute

先规划后执行

优点:省钱
缺点:不够灵活

### 模式三:Reflection(做完再检查)

实现方式(完成任务后自我评审)
自我反思或者双agent对话 (一个生成一个评审)

### 模式四:Multi-Agent

目前主流的多 Agent 框架包括 LangGraph、CrewAI、OpenAI Agents SDK 和微软的 AutoGen 等

不要过早的引入多agent框架,有时候强大的单agent就够用了

这几一个多 Agent 系统中，每个 Agent 内部可能用的是 ReAct 模式，整体协作用的是 Multi-Agent 模式，最后还有一个 Reflection 环节来检查质量。模式不是互斥的,往往是组合使用

## Function Call是什么

函数(工具)调用

### 流程

1. 定义函数:name,description,parameters
2. LLM自主判断,并生成结构化响应
3. 执行函数
4. 生成回答

## MCP(Model Context Protocol)

上下文协议,解决了工具的集成问题

提供了统一的标准来连接外部工具或者数据源

### 组成

MCP host:应用
MCP Client:与MCP Server通信
MCP Server:负责对外暴露具体的工具能力和数据资源 

MCP解决了什么问题?
集成和动态发现新能力



## Skills

经验和方法论
**自然语言指令文件**,指导agent在什么场景下,遵照什么方法,遵循什么规范来完成特定任务
通常以SKILL.md形似存在

**Skills 的本质是"知识 + 行为指令"，它通过加载到上下文中来改变 Agent 的思考和行为方式，同时可以驱动 Agent 去调用 Function Call、MCP 工具、执行代码等外部操作**

### Skills的价值:

Skills 的核心价值在于**将专业知识和最佳实践编码成可复用的模块**

## 三者的区别

### 本质区别:

从解决问题上看:从**解决的问题**来看，Function Call 解决的是"LLM 怎么跟外部函数交互"这个最基础的问题。MCP 解决的是"怎么用统一标准管理大量工具"的集成问题。Skills 解决的是"Agent 怎么获得领域专业知识"的知识问题。

从**运行位置**来看，Function Call 的函数在你的应用程序中执行。MCP 的工具在外部的 MCP Server 中执行。Skills 完全在 Agent 的上下文窗口内生效，不涉及任何外部调用。

从**技术本质**来看，Function Call 是一种 API 协议，LLM 输出结构化的调用请求，应用程序执行后返回结果。MCP 是一种通信标准，定义了 Client 和 Server 之间如何发现和调用工具。Skills 是一种提示词扩展，用自然语言编写的行为指令，加载到 Agent 的上下文中。

从**标准化程度**来看，Function Call 在各 LLM 厂商之间格式不统一（OpenAI 和 Anthropic 的格式就不一样）。MCP 是统一的开放标准，跨厂商通用。Skills 目前还没有统一标准，各个 Agent 平台有自己的 Skill 格式。

## 什么是A2A(agent to agent)协议:

涉及多个agent通话

第一个是 **Agent Card（智能体名片）**。每个支持 A2A 的 Agent 都会发布一个 JSON 格式的"名片"，描述自己的身份、能力、擅长的领域、支持的交互方式、认证要求等信息。其他 Agent 通过读取这个名片来了解"这个 Agent 会什么，我能请它帮什么忙"。这就像你在 LinkedIn 上看到一个人的简历，知道他的技能和经验后，才决定要不要跟他合作。

第二个是**任务（Task）**。A2A 中的所有协作都围绕"任务"展开。一个 Client Agent（发起方）创建一个任务，发送给一个 Remote Agent（执行方）。任务有完整的生命周期，从创建、处理中、到完成或失败，每个状态变化都有明确的定义。这让双方能清楚地跟踪任务进展。

第三个是**消息和制品（Message & Artifact）**。Agent 之间通过消息来沟通过程中的信息，通过制品来传递最终结果。比如一个研究 Agent 完成分析后，会把分析报告作为制品返回给请求方。