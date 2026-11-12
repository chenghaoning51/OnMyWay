+++
title = "Human-in-the-loop"
slug = "human-in-the-loop"
weight = 50
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Human-in-the-loop相关学习笔记与实践要点。"
+++
By checking each tool call against a configurable policy
如果需要暂停,middleware将会issue an interrupt来暂停执行
图状态将会使用LangGraph的persistence layer来保存,因此可以pause and resume later

# Interrupt decision types

| Decision Type | Description                                                  | Example Use Case                                  |
| :------------ | :----------------------------------------------------------- | :------------------------------------------------ |
| ✅ `approve`   | Execute the tool with the original arguments as proposed by the agent. | Send an email draft exactly as written            |
| ✏️ `edit`      | Modify the tool arguments before execution.                  | Change the recipient before sending an email      |
| ❌ `reject`    | Skip executing this tool call entirely and return rejection feedback to the agent. | Deny file deletion and explain why                |
| 💬 `respond`   | Return the human’s message directly as a synthetic tool result, skipping execution, for “ask user” style tools. | Answer an `"ask_user"` prompt with a direct reply |

每个工具可用的决策类型取决于你在`interrupt_on`中配置的策略
使用场景:
Use `reject` when the human is denying the requested action. Use `respond` only when the human is acting as the tool, such as answering an `ask_user` prompt. Do not use `respond` to deny side-effecting tools, because its message is treated as a successful tool result.

# Configurable interrupt

要使用HITL,在`create_agent`时把中间件添加到agent的middleware列表
你可以使用tool actions到允许的决策类型的映射来配置他

```py
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware 
from langgraph.checkpoint.memory import InMemorySaver 


agent = create_agent(
    model="gpt-5.5",
    tools=[write_file, execute_sql, read_data],
    middleware=[
        HumanInTheLoopMiddleware(
            interrupt_on={
                "write_file": True,  # All decisions (approve, edit, reject, respond) allowed
                "execute_sql": {"allowed_decisions": ["approve", "reject"]},  # No editing allowed
                "read_data": False, # Safe operation, no approval needed
            },
            # Prefix for interrupt messages - combined with tool name and args to form the full message
            # e.g., "Tool execution pending approval: execute_sql with query='DELETE FROM...'"
            # Individual tools can override this by specifying a "description" in their interrupt config
            description_prefix="Tool execution pending approval",
        ),
    ],
    # Human-in-the-loop requires checkpointing to handle interrupts.
    # In production, use a persistent checkpointer like AsyncPostgresSaver or MongoDBSaver.
    checkpointer=InMemorySaver(),
)
```

ps:你必须配置一个checkpointer来持久化graph state,
在生产环境中,使用持久性的checkpointerSaver,如[`AsyncPostgresSaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.postgres.aio.AsyncPostgresSaver) 或 [`MongoDBSaver`](https://pypi.ac.cn/project/langgraph-checkpoint-mongodb/),对于测试和原型设计,使用[`InMemorySaver`](https://reference.langchain.org.cn/python/langgraph/checkpoints/#langgraph.checkpoint.memory.InMemorySaver)。

# Conditional interrupts

默认情况下,`interrupt_on`中列出的tools都会暂停以供审查,如果要仅暂停某些调用,在tool的`InterruptConfig`中添加`when`谓词,该谓词接受一个`ToolCallRequest`来返回True以中断或者False以自动批准


```py
from langchain.agents import create_agent
from langchain.agents.middleware import HumanInTheLoopMiddleware, ToolCallRequest
from langgraph.checkpoint.memory import InMemorySaver


def writes_outside_workspace(request: ToolCallRequest) -> bool:
    """Pause writes to paths outside the workspace directory."""
    path = request.tool_call["args"].get("path", "")
    return not path.startswith("/workspace/")


def is_write_query(request: ToolCallRequest) -> bool:
    """Pause SQL that isn't a read-only SELECT."""
    query = request.tool_call["args"].get("query", "")
    return not query.lstrip().upper().startswith("SELECT")


agent = create_agent(
    model="gpt-5.5",
    tools=[write_file, execute_sql, read_data],
    middleware=[
        HumanInTheLoopMiddleware(
            interrupt_on={
                "write_file": {
                    "allowed_decisions": ["approve", "edit", "reject"],
                    "when": writes_outside_workspace,
                },
                "execute_sql": {
                    "allowed_decisions": ["approve", "reject"],
                    "when": is_write_query,
                },
            },
        ),
    ],
    checkpointer=InMemorySaver(),
)
```

评估为False的tool不会pause

# Responding to interrupts

在`version=v2`中,结果时一个带有interrupts属性的`GraphOutput`,该属性包含需要审查的动作,你可以将这些动作提交给审查者,并在提供决策后恢复执行

## Decision types

同上

## Multiple types

当出现多个actions时,根据中断触发的顺序为每个动作提供一个决策

# Streaming with human-in-the-loop

使用stream_event()在agent运行和中断时流式传输实时更新;
stream.message流式传输LLM令牌,使用stream.value检查agent state快照以获取中断

```
from langgraph.types import Command

config = {"configurable": {"thread_id": "some_id"}}

# Stream agent progress and LLM tokens until interrupt
stream = agent.stream_events(
    {"messages": [{"role": "user", "content": "Delete old records from the database"}]},
    config=config,
    version="v3",
)
for message in stream.messages:
    for token in message.text:
        print(token, end="", flush=True)

# Check whether the run paused for human input
if stream.interrupted:
    print(f"\n\nInterrupt: {stream.interrupts}")

# Resume with streaming after human decision
stream = agent.stream_events(
    Command(resume={"decisions": [{"type": "approve"}]}),
    config=config,
    version="v3",
)
for message in stream.messages:
    for token in message.text:
        print(token, end="", flush=True)
```

# Execution lifecycle

middleware定义了一个在模型产生response之后但是在任何的tool call之前的hook

1. The agent invokes the model to generate a response.
2. The middleware inspects the response for tool calls.
3. If any calls require human input, the middleware builds a [HITLRequest](https://reference.langchain.com/python/langchain/agents/middleware/human_in_the_loop/HITLRequest) with `action_requests` and `review_configs` and calls [interrupt](https://reference.langchain.com/python/langgraph/types/interrupt).
4. The agent waits for human decisions.
5. Based on the `HITLResponse` decisions, the middleware executes approved or edited calls, synthesizes [ToolMessage](https://reference.langchain.com/python/langchain-core/messages/tool/ToolMessage)’s for rejected calls, returns human replies directly as [ToolMessage](https://reference.langchain.com/python/langchain-core/messages/tool/ToolMessage)’s for `respond` decisions, and resumes execution.

Custom HITL logic
对于更加复杂的工作流,你可以构建自定义的中断原语哥中间件来实现
