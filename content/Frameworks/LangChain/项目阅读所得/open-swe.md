+++
title = "Open-SWE"
slug = "open-swe"
weight = 60
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "Open-SWE相关学习笔记与实践要点。"
+++
# Convention part

## 1.使用async方法,只在必须的时候才使用sync方法(不是通用的设计范式):

约束之一为:Use async-only implementations. Add a sync method only when an interface requires it, and then raise `NotImplementedError`.

1.使用async方法优化并发性能 2.使用NotImplementedError显式告知为提供async实现,采用同步方法

## 2.Use strong types everywhere

1. 类型安全:防止隐式转换带来的诸多问题
2. 代码即文档(Self-Documenting Code)(可读性)与可维护性:该可读性不只是对于人,也可以是LLM,agent等等

常见的情况是:
Never use Any

## 3.Use absolute imports across packages; same-package imports may start with one dot. Never use parent-relative imports.

解释:1.使用绝对路径而非相对路径2.同一个package内部的导入可以使用.
3.但是禁止使用多`.`来向上级或者祖先目录寻找模块

作用:
1.编码"跨层级重构"引入的导入崩溃
2.增强代码的可读性
3.允许单点`.`的折中考虑:既保留了同模块的内聚性,又省略了编码的繁琐性

## 4.Use structured logging with a static message and values in extra; never interpolate values into log messages. Avoid standard LogRecord field names in extra.

使用结构化日志,保留固定的静态信息,将动态变量放入extra属性中
1.优化了日志聚合和分析系统
2.防止破坏日志结构的内部状态
3.增加日志的安全性,防止个人私密信息的泄露

## 5.Never discard an error. Every `except` either propagates (re-raise, or raise a more useful error) or logs what it swallowed — a bare `except ...: return None` / `pass` hides the failure from everyone debugging it later.

1.向上抛出更具业务语义的异常
2.记录日志后重新抛出
3.吞掉异常,但必须记录日志

# Test Part

运行测试:
切勿在本地运行完整测试套件；仅运行与本次变更相关的测试。
添加测试:
仅当测试能有意义地保护可观察行为时才添加测试。不要添加仅简单重复常量、映射、提示词文本、源码结构或内部调用顺序等非本质交互的“变更检测（change-detector）”测试。
覆盖有意义的边缘情况，并保持测试的确定性（deterministic）。

# Codes

## 1.显式导出接口:

```Py
# 1. 显式引入（Re-export / Forwarding）：
# 从子模块/深层模块 agent.server 中导入 get_agent 和 traced_agent
from agent.server import get_agent, traced_agent

# 2. 导出控制（Public API Definition）：
# 定义该模块对外的公开 API 白名单
__all__ = ["get_agent", "traced_agent"]
```

1.精简包的导出路径
2.控制from module import * 只有在__all__中的对象才会被导
3.静态类型检查:将--明确识别为公开给外部调用的Pubilc API

## 2._function_name(),function_name()的关系

OOP中的封装和面向接口编程的思想
在Python中,函数前带有_下划线的通常被认为是私有函数(认为,这是大家的一种约定俗称,但是并没有真正意义上的private函数),
而通过这个方法,将function_name()暴露为接口,将__function_name()封装为内部实现



## 3.日志的冒泡传递机制

当当前目录的logger是一个没有绑定任何输出目的地(Handler)的节点时,他会把日志信息抛给父级logger

# Server.py中关于subagent的创建部分

## 1.显式沙盒隔离

对于敏感工具的调用,不是使用prompt劝导不要调用敏感工具,而是直接使用`_SubagentToolGuard` 和 `is_subagent_excluded_tool`的MIddleware进行了切面阻断
且拦截后不抛出异常导致崩溃,而是优雅的返回结构化的ToolMessage进行告知

## 2.纵深防御的中间件分层:

代码将中间件按职责严格分层装配：

- **模型层** (`_subagent_model_middleware`)：拦截 LLM 调用的基础异常（超时、格式清洗、报错捕捉）。
- **运行期层** (`_subagent_middleware`)：工作流推送保护、动态工具注入。
- **环境守卫层** (`_subagent_guard_middleware`)：区分 `local_run` 环境（桌面端自由执行 vs 云端环境 PR 拦截）。 这种模块化的 `list` 解包组合（`*` 语法），极大地提升了中间件复用率。

## 3.显式继承覆盖机制

通过 `_DisableInheritedMiddleware` 解决了子图继承父图中间件时的冲突问题。子 Agent 作为独立图编译，有时继承父级的某些中间件（如重复检查消息队列）会导致死锁或逻辑冗余，显式声明 `inherited_middleware_exclusions` 实现了精细的取消重写。

## 4.提示词动态增强

SubAgent 的 `description` 决定了 Parent Agent 能否准确路由任务。源码不仅使用基础描述，还动态追加了 `load_prompt('system/general-purpose-subagent-suffix.md')`
这个技巧在返回敏感工具调用的ToolMessage也有使用

# 5.创建Subagent的标准通用流程

## 1.确定运行模式和分叉策略

确定Subagent的隔离级别

## 2.裁剪工具集和构建安全工具防护网

列出Subagent可用的工具,并使用切面Middleware横切阻断违规操作

## 3.组装中间件栈

按顺序:
权限拦截 -> 日志/轨迹记录 -> 动态工具 -> 模型超时/容错控制 -> 上下文卸载

## 4.根据运行环境注入安全守卫

根据部署目标（如本地 CLI、Docker 容器或 LangGraph Cloud）注入环境特定的守卫，如禁用高危 Shell 命令或 PR 自动提交

## 5.拼接路由 Prompt 与定义能力边界 

为 SubAgent 编写明确的 `name` 和 `description`，并附加标准化的系统后缀说明（Suffix），帮助主 Agent 准确判断何种子任务需要委派（Delegate）。

## 6.打包工厂函数并编译子图 

将上述组件封装工厂函数，返回符合框架规范的 SubAgent 配置结构供图引擎（Graph Engine）统一编译。

# 6.海象运算符

:= 含义为赋值并返回赋值之后的值

# 7.创建FastAPI应用总结(api/app.py文件)

**配置校验前置**：配置、数据库、云端沙箱和本地 LLM 的校验（`validate_*`）全部在 `lifespan` 启动阶段完成，遵循 **Fail-Fast（快速失败）** 原则[cite: 1]。

**数据迁移幂等设计**：版本升级时的存储迁移代码应当做成 **`no-op` 驱动的防重入函数**，并容忍局部失败[cite: 1]。

**资源清理彻底**：在 `lifespan` 的 `finally` 块中集中释放 DB 连接、HTTP Client 和 Worker 句柄，防止 Docker 容器优雅停机（SIGTERM）时出现资源泄漏或数据损坏[cite: 1]。

# 8.版本向下兼容和容错包的导入技巧

try-except Import Error组合
优先尝试符合新规范的导入方式;导入失败自动降级(fallback)到旧版的导入路径

# 9.dispatch.py的思想

对于不同的data source,将其进行归一化然后在传入进行处理,提高了代码的可阅读性和可复用性,而不是建立对于每个data source都进行独特的处理
