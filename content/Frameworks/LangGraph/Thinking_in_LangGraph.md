+++
title = "Thinking In LangGraph"
slug = "thinking-in-langgraph"
weight = 14
categories = ["Frameworks", "LangGraph"]
tags = ["LangGraph", "Agent"]
description = "Thinking In LangGraph相关学习笔记与实践要点。"
+++
# Thinking in LangGraph

使用LangGraph创建agent时
首先将他拆分为称为`nodes`的离散步骤
然后你要描述每个节点的decisions和transitions
最后你将`nodes`连接起来,通过一个每个节点都可以读写的共享`state`

# Example

```
The agent should:

- Read incoming customer emails
- Classify them by urgency and topic
- Search relevant documentation to answer questions
- Draft appropriate responses
- Escalate complex issues to human agents
- Schedule follow-ups when needed

Example scenarios to handle:

1. Simple product question: "How do I reset my password?"
2. Bug report: "The export feature crashes when I select PDF format"
3. Urgent billing issue: "I was charged twice for my subscription!"
4. Feature request: "Can you add dark mode to the mobile app?"
5. Complex technical issue: "Our API integration fails intermittently with 504 errors"
```

## Stpe1: Map out your workflow as discrete steps

Identifying the distinct steps and build a node(a function that does one specific thing)
Then, sketch how these steps connnect to each other.|

![image-20260923104130267](C:\Users\14152\AppData\Roaming\Typora\typora-user-images\image-20260923104130267.png)

- `Read Email`: Extract and parse the email content
- `Classify Intent`: Use an LLM to categorize urgency and topic, then route to appropriate action
- `Doc Search`: Query your knowledge base for relevant information
- `Bug Track`: Create or update issue in tracking system
- `Draft Reply`: Generate an appropriate response
- `Human Review`: Escalate to human agent for approval or handling
- `Send Reply`: Dispatch the email response

## Step2: Identify what each step needs to do

决定每个`node`需要执行什么操作和它的正常运行需要哪些context

LLM steps: 当需要理解,分析,生成文本或者推理时
Data steps:当你需要从外部数据源检索数据时
Action steps: 当你需要外部操作时
User input steps:需要人工干预时

按照上面三种对于`nodes`进行分类

## Step3: Design your state

`State`是agent中所有节点共享的memory

### what belongs to state:

Include in state:
需要跨步骤持久化吗?需要则存入`state`
Don's  store:
能否从其他数据推导出来,如果可以,没必要存储

### Keep state raw, format prompts on demand

your state raw data, not formatted text. Format prompts inside nodes when you need them

优点:

- 不同的节点可以按需结构化同样的数据
- 不需要更改你的state schema就可以更改prompt的模板
- 调试更清晰:你可以看到每个节点接受了什么样的数据
- 你的agent可以在不改变现有state的情况下不断演进

```
from typing import TypedDict, Literal

# Define the structure for email classification
class EmailClassification(TypedDict):
    intent: Literal["question", "bug", "billing", "feature", "complex"]
    urgency: Literal["low", "medium", "high", "critical"]
    topic: str
    summary: str

class EmailAgentState(TypedDict):
    # Raw email data
    email_content: str
    sender_email: str
    email_id: str

    # Classification result
    classification: EmailClassification | None

    # Raw search/API results
    search_results: list[str] | None  # List of raw document chunks
    customer_history: dict | None  # Raw customer data from CRM

    # Generated content
    draft_response: str | None
    messages: list[str] | None
```

## Steps 4: Build your nodes

A node in LangGraph is just a Python function that takes the current state and returns updates to it.

### Handle error appropriately

| Error Type                                                   | Who Fixes It            | Strategy                           | When to Use                                               |
| :----------------------------------------------------------- | :---------------------- | :--------------------------------- | :-------------------------------------------------------- |
| Transient errors (network issues, rate limits)               | System (automatic)      | Retry policy                       | Temporary failures that usually resolve on retry          |
| LLM-recoverable errors (tool failures, parsing issues)       | LLM                     | Store error in state and loop back | LLM can see the error and adjust its approach             |
| User-fixable errors (missing information, unclear instructions) | Human                   | Pause with `interrupt()`           | Need user input to proceed                                |
| Recoverable failure after retries                            | Developer (declarative) | `error_handler`                    | Run a compensation/recovery branch after retry exhaustion |
| Unexpected errors                                            | Developer               | Let them bubble up                 | Unknown issues that need debugging                        |

### Implementing our email agent nodes:

其中一个部分的源码
[from typing import Literal
from langgraph.graph import StateGraph, START, END
from langgraph.types import interrupt, Command, RetryPolicy
from langchain_openai import ChatOpenAI
from langchain.messages import HumanMessage

llm = ChatOpenAI(model="gpt-5-nano")

def read_email(state: EmailAgentState) -> dict:
    """Extract and parse email content"""
    # In production, this would connect to your email service
    return {
        "messages": [HumanMessage(content=f"Processing email: {state['email_content']}")]
    }

def classify_intent(state: EmailAgentState) -> Command[Literal["search_documentation", "human_review", "draft_response", "bug_tracking"]]:
    """Use LLM to classify email intent and urgency, then route accordingly"""

```py
# Create structured LLM that returns EmailClassification dict
structured_llm = llm.with_structured_output(EmailClassification)

# Format the prompt on-demand, not stored in state
classification_prompt = f"""
Analyze this customer email and classify it:

Email: {state['email_content']}
From: {state['sender_email']}

Provide classification including intent, urgency, topic, and summary.
"""

# Get structured response directly as dict
classification = structured_llm.invoke(classification_prompt)

# Determine next node based on classification
if classification['intent'] == 'billing' or classification['urgency'] == 'critical':
    goto = "human_review"
elif classification['intent'] in ['question', 'feature']:
    goto = "search_documentation"
elif classification['intent'] == 'bug':
    goto = "bug_tracking"
else:
    goto = "draft_response"

# Store classification as a single dict in state
return Command(
    update={"classification": classification},
    goto=goto
)]()
```

## Step 5: Wire it together

将`nodes`连接成一个可运行的图,由于`nodes`会自行处理决策路由,因此我们只需要少数几个必要的边(edge)

通过interrupt()启用Human-in-the-loop,我们需要checkpointer进行编译,以便在不同运行之间保存`state`

```py
from typing import Literal
from langgraph.graph import StateGraph, START, END
from langgraph.types import interrupt, Command, RetryPolicy
from langchain_openai import ChatOpenAI
from langchain.messages import HumanMessage

llm = ChatOpenAI(model="gpt-5-nano")

def read_email(state: EmailAgentState) -> dict:
    """Extract and parse email content"""
    # In production, this would connect to your email service
    return {
        "messages": [HumanMessage(content=f"Processing email: {state['email_content']}")]
    }

def classify_intent(state: EmailAgentState) -> Command[Literal["search_documentation", "human_review", "draft_response", "bug_tracking"]]:
    """Use LLM to classify email intent and urgency, then route accordingly"""

    # Create structured LLM that returns EmailClassification dict
    structured_llm = llm.with_structured_output(EmailClassification)

    # Format the prompt on-demand, not stored in state
    classification_prompt = f"""
    Analyze this customer email and classify it:

    Email: {state['email_content']}
    From: {state['sender_email']}

    Provide classification including intent, urgency, topic, and summary.
    """

    # Get structured response directly as dict
    classification = structured_llm.invoke(classification_prompt)

    # Determine next node based on classification
    if classification['intent'] == 'billing' or classification['urgency'] == 'critical':
        goto = "human_review"
    elif classification['intent'] in ['question', 'feature']:
        goto = "search_documentation"
    elif classification['intent'] == 'bug':
        goto = "bug_tracking"
    else:
        goto = "draft_response"

    # Store classification as a single dict in state
    return Command(
        update={"classification": classification},
        goto=goto
    )
```

