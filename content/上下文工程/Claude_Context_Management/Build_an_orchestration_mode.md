+++
title = "Build An Orchestration Mode"
slug = "build-an-orchestration-mode"
weight = 30
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "Build An Orchestration Mode相关学习笔记与实践要点。"
+++
# Build an orchestration mode

Build a session-level mode that grants standing consent for multiagent fan-out, switched on and off with mid-conversation system messages.

会话级别的;持续性凭证;multiagent;mid-conversation

编排模式(orchestration mode)是一种会话级开关:当他开启时,model will pay most efforts to every request,先自行见检查和分析任务,然后默认将工作拆分给几个并发的子智能体
It is not an API parameter. It is built entirely from documented pieces

1. 1.An effort level: requests run at a documented effort value such as Max,there no other level higher than it
2. A mode reminder: a mid-conversation system message tells the model the mode is active, 每个几次对话发送一行通知
   当推出时,会发出退出通知
3. Standing consent(持续授权) in the tool description:该模式开启时,对于每一个实质性的任务,都应该在不经过询问的情况下自己设计和运行一套工作流程

该模式会造成成本的增加,原因有二:Max effort level;Multi-agents,subagents

## Ser up the loop

MAX_CONCURRENT限制并发的subagents的数量
MAX_TOTAL_SUBTASKS在一次工作流中的排队的任务的数量
当DOC_TEST_MODE开启时,会将循环次数限制为一次,这样地自动化文本测试框架就可以快速完成编译并快速结束,而不需要运行完整地编排流程
但是在运行个人的用例时,请不要开启或者leave it unset,不然你就会进入文档测试模式

## Define the mode reminder

这些reminders都很简短,他们切换模式并且指向tool description
完整的文本只在刚开启时发送一次;the refresher每隔几轮对话发一次;退出通知只在退出的时候发送

```
MODE_ENTER = (
    "Orchestration mode is on: optimize for the most exhaustive, correct answer rather than "
    "the fastest one. Use the Workflow tool on every substantive task, sized to the problem's "
    "natural decomposition rather than the maximum the tool allows. See the Workflow tool's "
    "description for standing consent, granularity guidance, and quality patterns. Work solo "
    "only on conversational or trivial turns."
)
MODE_REFRESH = (
    "Orchestration mode is still on. Use the Workflow tool; see its standing consent section."
)
MODE_EXIT = (
    "Orchestration mode is off. The Workflow tool's standard opt-in rule applies again."
)
```

## Grant standing consent in the tool description

Workflow工具承载了真正的行为约定(behavioral contract):包括准入规则,持续授权,模型可以采用的质量保障模式等等
subagent还会获得一个report_findings工具,将他们的结果以JSON结构化的形式返回;而bash工具则是anthropic定义的bash_20250124工具,在本地运行

```
WORKFLOW_TOOL = {
    "name": "Workflow",
    "description": (
        "Orchestrate a multiagent workflow: split a large task into independent subtasks "
        "and run them as parallel agents, then collect their results.\n\n"
        "Opt-in: only use this tool when the user explicitly asks for a workflow, or when a "
        "system message confirms that orchestration mode is on.\n\n"
        "Quality patterns: adversarial verification (a second wave of agents checks the first "
        "wave's findings against the source), a completeness critic (one agent hunts for what "
        "the others missed), and multiphase sequencing (understand, design, implement, and "
        "review as separate workflow calls, reading results between phases). A useful default "
        "is hybrid: scout inline first to discover the work-list, then fan out over it.\n\n"
        "Granularity: scope each subtask to a distinct concern, component, or question rather "
        "than per line or per file section. Scale the count to what the user asked for: a "
        "focused review of a module of a few hundred lines rarely needs more than about ten "
        "subtasks; a broad audit of a large codebase can justify more.\n\n"
        "Standing consent: while a system message confirms orchestration mode is on, that "
        "opt-in is standing. Author and run a workflow for every substantive task by default, "
        "and lean toward verifying findings adversarially. Work solo only on conversational "
        "turns or trivial mechanical edits. When a system message says the mode is off, "
        "revert to the opt-in rule above."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "subtasks": {
                "type": "array",
                "items": {"type": "string"},
                "description": "Independent subtask prompts to run as parallel agents",
            }
        },
        "required": ["subtasks"],
    },
}

BASH_TOOL = {"type": "bash_20250124", "name": "bash"}

REPORT_TOOL = {
    "name": "report_findings",
    "description": (
        "Report the final findings for your subtask. Call this exactly once, when you are "
        "done investigating; it ends your task."
    ),
    "input_schema": {
        "type": "object",
        "properties": {
            "summary": {"type": "string", "description": "Two or three sentences of synthesis"},
            "findings": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "claim": {"type": "string", "description": "The finding, one sentence"},
                        "evidence": {
                            "type": "string",
                            "description": "How it was verified (file, line, or command output)",
                        },
                        "severity": {"type": "string", "enum": ["high", "medium", "low", "info"]},
                    },
                    "required": ["claim", "evidence", "severity"],
                },
            },
        },
        "required": ["summary", "findings"],
    },
}
```

## Run the bash tool locally

bash处理器运行命令并带运行超时时间,捕获合并后的stderr和stdout并且截断输出,以防止单次输出占满上下文窗口
命令会在启动的文件夹内运行
当DOC_TEST_MODE开启时,框架会给bash命令提供一个临时的,小型的测试目录,并且在退出时删除
没有沙箱,
示例每次调用都会在一个全新的子shell中运行,而不是维持持久化对话
而在生产环境中的agent则应该接入到一个长期运行的subshell

## Run one subagent

每个workflow的子任务都会称为一个独立的小型的带有bash工具的agent循环,并且effort与主循环相同
每个请求都会设置一个单独的超时时间,这样即使链接中断也只是子agent受影响而不会让整个工作流瘫痪停滞

```
def run_subagent(model: str, prompt: str) -> str:
    """One subagent: a small nested agent loop with the bash tool plus report_findings.
    Subagents inherit the main loop's effort level."""
    subagent_system = (
        "You are one agent in a larger parallel fan-out, assigned a single subtask. "
        "Investigate it directly, using bash to check facts rather than guessing, and finish "
        "by calling report_findings exactly once. Return findings, not narration."
    )
    messages = [{"role": "user", "content": prompt}]
    for _ in range(MAX_SUBAGENT_TURNS):
        with client.messages.stream(
            model=model,
            max_tokens=64000,
            system=subagent_system,
            output_config={"effort": EFFORT},
            tools=[BASH_TOOL, REPORT_TOOL],
            messages=messages,
            timeout=REQUEST_TIMEOUT_SECONDS,
        ) as stream:
            response = stream.get_final_message()
        messages.append({"role": "assistant", "content": response.content})
        if response.stop_reason == "pause_turn":
            continue
        if response.stop_reason != "tool_use":
            text = "".join(block.text for block in response.content if block.type == "text")
            if response.stop_reason == "max_tokens":
                text += "\n\n(warning: subagent response was truncated at max_tokens)"
            return text
        tool_results = []
        report = None
        for block in response.content:
            if block.type != "tool_use":
                continue
            if block.name == "report_findings":
                report = json.dumps(block.input, indent=2)
                output, is_error = "Findings recorded.", False
            elif block.name == "bash":
                output, is_error = handle_bash_block(block)
            else:
                output, is_error = f"unknown tool: {block.name}", True
            tool_results.append(
                {
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": output,
                    "is_error": is_error,
                }
            )
        if report is not None:
            return report
        messages.append({"role": "user", "content": tool_results})
    return "(subagent hit the turn limit before finishing)"
```

## Journal results so reruns resume(记录结果这样重新运行时可以接着执行)

该模式会开启许多子agent,重启的成本很高.而一个基于内容寻址的日志会使他具有幂等性(idempotent)
在分发智能体之前,先计算器prompt的SHA-256,并且在本地的JSON文件中查找这个哈希值,如果存在,则直接返回之前的结果
如果运行过程被中断,也只有那些从未被完成的子任务才会被重启
该日志会在不同的运行之间去重,但是不会在同一次fan-out中去重
如果想要重头开始执行,只需要删除这个日志文件即可

## Fan out,then verify

扇出最多接受 `MAX_TOTAL_SUBTASKS` 个 prompt，并通过日志（journal）运行这些任务，同时最多允许 `MAX_CONCURRENT` 个任务处于执行中（PHP 版本则是顺序执行）。
它会**隔离各个子任务的失败**：某个子智能体出错时，只会将其降级为一个错误字符串，而不会导致整个运行流程终止。
第一轮执行完成后，会进行**第二轮扇出**，并复用相同的子智能体执行路径，对第一轮的每个结果进行尝试反驳：
每个验证器（verifier）都会根据**原始来源重新推导和核实这些结论**；如果无法确定，则默认判定为**“反驳（refuted）”**。
最终，**原始结果和对应的验证结论（verdict）都会返回给编排器（orchestrator）**，由编排器综合考虑两者。

## Toggle the mode with mid-conversation system messages

通过 mid-conversation来切换模式
先追加user_message,然后才是system-message(可能full text,也可能是定时的refresher,也可能是退出通知)
并且这满足了它的位置限制:
某个user turn之后(role: user的tool call也可以视为user turn),对应的assistant之前.或者最后面:
原因之前有,主要是为了prompt caching
