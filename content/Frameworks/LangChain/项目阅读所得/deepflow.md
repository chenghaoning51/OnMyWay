+++
title = "DeepFlow"
slug = "deepflow"
weight = 50
categories = ["Frameworks", "LangChain"]
tags = ["LangChain", "Agent"]
description = "DeepFlow相关学习笔记与实践要点。"
+++
# 1.langgraph.json文件的作用

when:

1. 使用Langgraph cli部署本地API服务
2. 部署到langgraph cloud/langsmith deployment
3. 使用langgraph studio及逆行调试

不需要:
使用传统的后端API服务;纯脚本/嵌入式开发

作用:
指定graph入口;生命项目依赖;配置环境变量等等

# 2.Sandbox的作用

提供隔离的安全执行环境

1. 安全隔离(防止恶意代码和误操作):主要是限制一些危险操作,比如`rm`等删除操作,防止访问敏感数据,防止向外发送未经授权的请求等等

2. 环境独立和资源限制:

   1. 资源配额:CPU,内存,磁盘限额
   2. 隔离环境:每一个session都有干净的上下文

3. 支持复杂工具运行:

   1. 提供工具:文件系统操作工具
   2. 提供无头(Headless)浏览器环境

   

# 3.技能加载的递归实现:

递归发现skills下嵌套的SKILL.md文件

# 4.Subagent的SSE事件

SSE(Server sent evnet):一种基于HTTP协议的单向实时通信技术,创建HTTP连接后,主动,持续地向客户端推送数据

## subagent的SSE事件

subagent持续向用户端暴露该agent的执行情况
可视化的多agent协作;支持中途打断和交互

# 5.常见的工具生态系统

沙箱;内置工具(自己编写的);社区工具;MCP;Skill

