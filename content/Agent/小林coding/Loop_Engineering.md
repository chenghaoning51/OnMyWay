+++
title = "Loop Engineering"
slug = "loop-engineering"
weight = 51
categories = ["Agent"]
tags = ["Agent", "AI Agents"]
description = "Loop Engineering相关学习笔记与实践要点。"
+++
# Loop Engineering

递归式的目标


## Loop的组成

### 一.自动化

定时或者事件触发

### 二.worktree

允许并发进行
git的worktree机制:给每个agent一个独立的工作目录和独立分支,共享同一份仓库历史,但是物理上互不干扰,各干各的,最后各开各的PR

### 三.Skill

### 四.Connector

基于MCP协议的连接器

### 五.Sub-agent

将产出和评估解耦

### 六.记忆

持久化到磁盘中而不是上下文中

| 部件      | 在 loop 里的职责   | Codex                         | Claude Code              |
| --------- | ------------------ | ----------------------------- | ------------------------ |
| 自动化    | 定时发现和分诊     | Automations 面板 + 分诊收件箱 | 计划任务、`/loop`、hooks |
| worktree  | 隔离并行任务       | 每个线程内置 worktree         | `git worktree`、隔离配置 |
| skill     | 固化项目知识       | Agent Skills                  | Agent Skills             |
| connector | 连接外部工具       | 基于 MCP 的 Connectors        | MCP servers              |
| sub-agent | 分头干活、写查分离 | 配置文件定义子 agent          | 子 agent、agent teams    |
| 记忆      | 追踪进度           | markdown 或接工单系统         | markdown 或接工单系统    |

### [验证仍然归你](https://xiaolinnote.com/agent/engineering/loop-engineering.html#第一盆-验证仍然归你)

loop 无人值守地运行，听起来很美。但换个角度念这句话：**一个无人值守运行的 loop，也是一个无人值守犯错的 loop**。

你睡觉时它在干活，也意味着你睡觉时它在犯错。

就算你按规矩配了负责检查的 sub-agent，也别高兴太早：**检查 agent 嘴里的「done」，只是一个声明，不是一个证明**。它说没问题，和真的没问题，中间还隔着你的眼睛。



### [理解债，越顺滑涨得越快](https://xiaolinnote.com/agent/engineering/loop-engineering.html#第二盆-理解债-越顺滑涨得越快)

第二个问题更隐蔽。loop 交付你没写过的代码越快，「仓库里实际存在的东西」和「你脑子里真正理解的东西」之间的鸿沟就越大。

这有个专门的名字，叫**理解债（Comprehension Debt）**。

它和技术债不一样：技术债是代码烂，理解债是代码可能不烂，**但你不知道它为什么是对的**。出问题的那天，你面对的是一片自己「拥有」但不「理解」的代码。一个顺滑的 loop 不会帮你还这笔债，只会让它涨得更快，除非你坚持去读 loop 产出的东西。

第三个问题最扎心。loop 自己转起来之后，你会发现一个特别舒服的姿势：不再对产出有自己的观点，它给什么就收什么。

这个状态有个专门的名字，叫**认知投降（Cognitive Surrender）**。Osmani 的博客里有一段关于它的原话，非常锋利：

「带着判断力去设计 loop，它是解药；为了逃避思考去设计 loop，它是助燃剂。同一个动作，相反的结果。」



最后还有一笔很现实的账：token 成本。loop 是按循环烧 token 的，sub-agent 每多一个，就多一份模型和工具的开销。比较务实的花法，是把 sub-agent 用在「值得买第二意见」的地方，而不是处处双保险。token 富裕和精打细算这两种人，会设计出两种完全不同的 loop。

