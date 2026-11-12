+++
title = "ClaudeCode"
slug = "claudecode"
weight = 11
categories = ["Agent"]
tags = ["Agent", "AI Agents"]
description = "ClaudeCode相关学习笔记与实践要点。"
+++
# 一.架构设计

分为四层架构

### 引擎层:负责调度和思考

关键设计原则:不包含任何的业务逻辑

1. 协调:把用户输入,系统提示词,历史对话拼接在一起
2. 分发:LLM需要调用工具时,找到对应的工具并执行
3. 决策:根据LLM的返回决定时继续循环还是结束对话

该设计的好处是:新增能力只需要新增一个工具,引擎层完全不用改

### 工具层:能力

工具遵循统一的规范,这个规范强制定义了三个安全属性:
1.工具是只读的还是会改东西的
2.它是否具有破坏性,需要额外确认?
3.能不能和其他工具同时执行

### 服务层:

所有层共享的基础设施:
调大模型的API,上下文压缩,MCP协议

### 安全和治理层:

权限系统决定哪些操作需要用户确认,哪些操作可以自动执行;
Hook系统允许工具在执行前后插入自定义行为
Bash安全模块会对shell命令做语法级别的分析,检测命令注入,路径逃逸等危险模式

# 二.Agent工作模式

## 首先回顾React

Thought->Action->Observation(Loop)
存在的问题:Token太浪费;应用层代码太复杂了;为弱模型设计的(当时的模型推理能力不够,但是现在的模型推理能力已经足够强了)

## Claude Code: Tool-Use Loop

![img](https://cdn.xiaolincoding.com//picgo/1775113773385-76a9359b-1c69-42e1-93c2-c1b8a352e540.png)

没有推理步骤(这是因为Opus自己具有推理能力,这是通过Extended Thinking)
该设计的核心哲学是:信任模型的推理能力,保持应用层框架尽可能简单

```
async function* queryLoop(
  params: QueryParams,
  consumedCommandUuids: string[],
): AsyncGenerator<StreamEvent | Message, Terminal> {
  let state: State = { messages, toolUseContext, turnCount: 1, ... }

  while (true) {
    // 步骤 1：压缩上下文（五步从轻到重）
    // 步骤 2：调用大模型 API，流式接收
    for await (const event of streamAPI(params)) {
      yield event  // 流式输出每个 token
    }
    // 步骤 3：分析模型返回
    if (response.stopReason === 'end_turn') break  // 完成了，跳出循环

    // 步骤 4：执行工具调用（并发/串行编排）
    const toolResults = await executeToolCalls(toolUseMessages)

    // 步骤 5：更新 state，继续循环
    state = { ...state, messages: updatedMessages, turnCount: turnCount + 1 }
    continue
  }
}
```

### 优点

1.Extended Thinking让推理在模型内部完成
2.API原生支持tool_use:不需要通过正则表达式从文本中提取[Action].消除了React的格式解析问题
3.end_turn作为天然的终止信号:语义清晰,不需要额外解析

| **维度**   | **ReAct**                     | **Tool-Use Loop**          |
| ---------- | ----------------------------- | -------------------------- |
| 推理方式   | 显式 Thought 文本             | 模型内部 Extended Thinking |
| 工具调用   | 解析文本提取 Action           | API 原生 tool_use          |
| 终止判断   | 检测 「Final Answer」         | API 原生 end_turn          |
| Token 开销 | 每轮要输出 Thought            | 无额外开销                 |
| 编排复杂度 | 高（需要解析 Thought/Action） | 低（只需要 if/else）       |
| 适合场景   | 弱模型 + 简单工具             | 强模型 + 复杂工具集        |

## Plan Mode

先规划,后执行
并不是一个独立得框架,而是在Tool-Use Loop中通过EnterPlanMode和ExitPlanMode两个工具实现的
分为三步:
第一步:模型自主进入或客户手动触发
模型判断为复杂任务,调用EnterPlanMode工具;或用户自己手动触发

第二步:只读探索+设计方法:
权限将为只读,使用只读工具探索代码库,将生成的plans写入.claude/plans/目录
每5轮对话,模型会warning模型,提示他还在Plan Mode

第三步:用户审批后实施
模型调用ExitPlanMode,此时需要用户确认,批准后,权限恢复

核心设计:工具即能力

PlanMode不是一种特殊的模式切换,而是调用了EnterPlanMode和ExitPlanMode这两个工具



# 三.System Prompt的构造

非静态文件,由十几个section拼接,且拼接过程做了缓存优化
源码翻译为了中文,保留了关键术语

## 角色定义与安全红线

```
你是一个交互式代理（interactive agent），帮助用户完成软件工程任务。
请使用下面的指令和可用的工具来协助用户。

重要：你绝对不能为用户生成或猜测 URL，除非你确信这些 URL
是为了帮助用户完成编程任务。你可以使用用户在消息或本地文件中
提供的 URL。

```

安全约束指令

```
重要：允许协助已授权的安全测试、防御性安全研究、CTF 挑战赛
和教育场景。拒绝涉及破坏性技术、DoS 攻击、大规模目标扫描、
供应链攻击或用于恶意目的的检测规避请求。
```

## 行为准则

挑选:

write before read

```
一般来说，不要对你没有阅读过的代码提出修改建议。如果用户
要求你查看或修改某个文件，先读一遍它。在提出修改建议之前，
先理解现有代码。
```

关于代码风格:less is more

```
不要在用户要求之外添加功能、重构代码或进行"改进"。修一个 bug
不需要顺手清理周围的代码。一个简单功能不需要额外的可配置性。

不要为一次性操作创建辅助函数、工具类或抽象层。
三行相似的代码比一个过早的抽象更好。
```

关于失败处理:

```
如果某个方案失败了，先诊断原因再决定是否换方案——读报错信息、
检查你的假设、尝试有针对性的修复。不要盲目重试完全相同的操作，
但也不要因为一次失败就放弃一个可行的方案。
```

## 操作安全:

从可逆性和影响范围两个维度来判断风险

```
仔细考虑操作的可逆性（reversibility）和影响范围（blast radius）。
一般来说，你可以自由执行本地的、可逆的操作，比如编辑文件或
运行测试。但对于难以撤销、影响共享系统或有风险的操作，
请先和用户确认后再执行。

需要用户确认的高风险操作示例：
- 破坏性操作：删除文件/分支、删表、rm -rf
- 难以逆转的操作：force-push、git reset --hard、修改已发布的 commit
- 对他人可见的操作：推送代码、创建/关闭 PR、发送消息
- 上传到第三方工具：内容可能被缓存或索引，即使删除也无法撤回
```

```
用户批准了某个操作（比如 git push）一次，并不意味着他在所有
场景下都批准这个操作。授权仅对指定的范围有效，不能超出范围。
```

## 工具使用指南:

```
当有专用工具可用时，不要用 Bash 来执行命令。使用专用工具可以
让用户更好地理解和审查你的工作。这一点至关重要：

- 读取文件用 Read 工具，而不是 cat、head、tail 或 sed
- 编辑文件用 Edit 工具，而不是 sed 或 awk
- 创建文件用 Write 工具，而不是 echo 重定向
- 搜索文件用 Glob 工具，而不是 find 或 ls
- 搜索内容用 Grep 工具，而不是 grep 或 rg
```

可审查性:
当模型调用 `Read` 工具读文件时，UI 会清晰地展示「Agent 正在读取 src/index.ts」。但如果模型执行 `cat src/index.ts`，用户看到的只是一条 Bash 命令和一大坨输出，完全不知道 Agent 在干什么。

## Git安全协议:

```
Git 安全协议：
- 绝不修改 git config
- 绝不执行破坏性 git 命令（push --force、reset --hard、
  checkout .、clean -f），除非用户明确要求
- 绝不跳过 hooks（--no-verify），除非用户明确要求
- 绝不 force push 到 main/master 分支，如果用户要求则发出警告

关键：始终创建新的 commit（NEW commit），而不是用 --amend 修改。
当 pre-commit hook 失败时，commit 实际上并没有发生——所以
--amend 会修改上一个（不相关的）commit，可能导致代码丢失。
正确做法是：修复问题后创建一个新的 commit。
```

## 输出风格约束:

```
# 输出效率
直奔重点。先尝试最简单的方案。要极度简洁。
工具调用之间的文字不超过 25 个词。最终回复不超过 100 个词。

先给出答案或行动，而不是推理过程。跳过填充词、开场白和
不必要的过渡句。不要复述用户说过的话——直接做就行。
```

## 环境信息注入

```
# 环境信息
- 主工作目录：/Users/you/my-project
- 是否为 Git 仓库：是
- 操作系统平台：darwin (macOS)
- Shell 类型：zsh
- 当前模型：Claude Opus 4.6 (1M context)
- 知识截止日期：2025 年 5 月
```

## 分割线和三级缓存

__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__ 
三级缓存:
全局缓存(分割线之上,跨组织跨用户共享)->组织缓存(同一组织内跨会话共享)->会话缓存(同一个section在一次会话内只计算一次)

# 四.记忆系统

记忆分类:
user:用户画像
feedback:行为反馈:
rules,why,how to apply
project:项目动态
必须把相对日期转化为绝对日期

reference:外部指针


排除清单:不会被写入记忆系统的内容
**可以从当前代码推导出来的信息，一律不存**

### 存储的方式:索引+独立文件

MEMORY.md文件作为索引被加载到System Prompt中,但是独立记忆文件按需加载
不超过200行(25KB)的轻量目录:通过行数和字节数限制

### 召回方式:通过sonnet做记忆检索

流程

1. 扫描记忆文件的头部信息
2. 拼成清单+用户当前输入,发给Sonnet做选择,Sonnet返回选中文件列表
3. 加载选中的记忆文件,注入上下文

记忆召回的执行时机:
在用户提交信息之后就立刻开始了(并行召回)

# 五.上下文窗口管理

压缩策略:分为五种程度
核心理念:压缩必定有信息的损失,进行层级的压缩策略

### 一.huge tool result存入磁盘

进入message之前,超过50KB的tool result存磁盘,返回预览;
或一条message的总tool result< 200kb,如果超过,选择最大的几个tool result存磁盘

### 二.砍掉远古消息

移除对话开头的老消息,并插入边界标记显式告知模型

### 三.裁剪老的tool result

Micro-Compact
核心思想:随时间衰减,可重新获取的
subagent的tool result永远不会被clear

被裁剪的tool result会被占位文本替代

### 四.读时投影(Read-Time Projection)

在调用API的那一刻,动态计算压缩视图给LLM

### 五.全量摘要

trigger:设置的阈值
1.生成摘要
2.替换旧消息
3.**Post-Compact Restoration（压缩后恢复**)

从文件状态缓存（`fileStateCache`）中找出最近访问过的文件，按最后访问时间排序，挑选最多 5 个、总共不超过 50K Token 的文件内容重新注入。同时恢复活跃的 Skill（不超过 25K Token），如果有进行中的 Plan 也会恢复 Plan 文件

| **层级** | **手段**       | **信息损失** | **API 开销**        | **触发条件**      |
| -------- | -------------- | ------------ | ------------------- | ----------------- |
| 第 1 层  | 大结果存磁盘   | 几乎为零     | 零                  | 工具结果超 50KB   |
| 第 2 层  | 砍掉远古消息   | 低           | 零                  | 消息过时          |
| 第 3 层  | 清理老工具输出 | 中低         | 零                  | 缓存过期/数量超限 |
| 第 4 层  | 读时投影压缩   | 中           | 低                  | 上下文达 90%      |
| 第 5 层  | 全量摘要       | 高           | 高（一次 API 调用） | 上下文达 ~93%     |
