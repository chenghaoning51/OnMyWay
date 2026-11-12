+++
title = "构建第一个 CrewAI 项目"
slug = "build-first-crew"
weight = 52
categories = ["Frameworks", "CrewAI"]
tags = ["CrewAI", "Agent"]
description = "构建第一个 CrewAI 项目相关学习笔记与实践要点。"
+++
## 第一步:创建新的CrewAI项目

```bash
crewai create crew research_crew
```

## 第二步:探索项目结构

遵循py项目的最佳实践,通过分离配置文件和实现代码,在不修改源代码的情况下修改团队的行为

## 第三步:配置你的智能体

通过修改agent.yaml来定义智能体
role;goal;backstory;llm

## 第四步:定义你的任务

任务代表可智能体将要执行的具体工作,包括详细的说明和预期输出
通过修改task.yaml文件
包含description和expected_output,context

## 第五步:配置你的团队

通过crew.py文件来配置

## 第六步:设置你的主脚本

## 第七步:设置你的环境变量

.env文件

## 第八步:安装依赖项

```
crewai install
```



## 第九步:运行你的团队

```
crewai run
```

## 第十步:查看你的输出