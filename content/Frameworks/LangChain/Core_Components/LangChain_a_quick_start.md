+++
title = "LangChain A Quick Start"
slug = "langchain-a-quick-start"
weight = 30
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "LangChain A Quick Start相关学习笔记与实践要点。"
+++
一个简单的示例

```
from langchain.agents import create_agent

def get_weather(city: str) -> str:
    """Get weather for a given city."""
    return f"It's always sunny in {city}!"

agent = create_agent(
    model="claude-sonnet-4-6",
    tools=[get_weather],
    system_prompt="You are a helpful assistant",
)

result = agent.invoke(
    {"messages": [{"role": "user", "content": "What's the weather in San Francisco?"}]}
)
print(result["messages"][-1].content_blocks)
```

# Build a real-world agent:

1. Detailed System Prompt
2. Create Tools
3. Model Configuration
4. Conversational memory
5. Deep agents
6. Testing

### 1.Define the system prompt

defines your agent's role and behavior.
Keep it specific and actionable.

### 2.Craete tools

Tools let a model interact with external systems by calling functions you define. Tools can depend on runtime context and also interact with agent memory.

Tools should be well-documented: their name,description,parameters will become part of the model's prompt. LangChain's tool decorator adds metadata and enables runtime injection with the `ToolRunTime` paramete.

### 3.Configure your model

Set up your language model with the right parameters foe your use case

### 4.Add memory

Add memory to your agent to maintain state across interactions. This allows the agent to remember previous conversations and context.

### 5.Create and run the agent

Tow different Frameworks for creating agents:
LangChain agents and deep agents
Use deep agents when you want maximum with minimal setup;
Choose LangChain agents when you need fine-grained contorl.

### 6.Review the results


相较于LangChain, deep agent拥有更多定义好的功能:

1. 使用内置的 [`write_todos`](https://docs.langchain.org.cn/oss/python/deepagents/harness#task-planning) 工具**规划其方法**，以分解研究任务。
2. 通过调用 `fetch_text_from_url` 工具**加载文件**以收集信息。
3. 通过使用文件系统工具（[`grep`](https://docs.langchain.org.cn/oss/python/deepagents/harness#virtual-filesystem-access) 和 [`read_file`](https://docs.langchain.org.cn/oss/python/deepagents/harness#virtual-filesystem-access)）来**管理上下文**。
4. **生成子智能体**：根据需要将复杂的子任务委派给专门的子智能体。

For LangChain agents, you must implement more capabilities to get a similar lever of service and can customize them along the way as needed

In short,deep agent is well-organized and provides many integrated tools
and LangChain can fit custom needs better, but requires implementing more functionalities.

## Trace agent calls

Use LangSmith to trace LLM calls and inspect what is going on inside your agent.

Emmm, you should sign up for  a LangSmith account first.
Besides,you can also set up LangSmith Engine which monitors your traces,detects issues ,and preposes fixes.

