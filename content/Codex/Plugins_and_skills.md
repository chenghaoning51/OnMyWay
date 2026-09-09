+++
title = 'Skills 与 Plugins'
slug = "codex-skills-plugins"
date = 2026-09-07T00:00:00+08:00
lastmod = 2026-09-09T00:00:00+08:00
weight = 3
categories = ['Codex']
tags = ['Skills', 'Plugins']
description = 'Skill 封装任务指令与资源、Plugin 组合工具，减少重复粘贴提示词与模板。'
+++

## Skills & Plugins

Helps to complete repeatable work with the right instructions,resources,and tools,They reduce the need to paste the same prompt ,template,requirements,or process into every chat.

#### Skill:

A **skill** packages instructions and supporting resources for a specific task or workflow.

#### Plugin:

A **plugin** is an installable bundle that can include skills, connectors, or both. Connectors are backed by Model Context Protocol (MCP) servers and can optionally include custom ChatGPT UI.

## Use skills for **repeatable** work:

A skill is a reusable workflow that gives ChatGPT or Codex task-specific guidance. 

A skill can combine:

- A name and description that help ChatGPT and Codex recognize when the skill applies.
- Workflow instructions that define the process and expected result.
- Supporting resources such as templates, examples, brand guidance, schemas, or connected tools.

## Build skills:

You can start by turning a task you already repeat into a focused playbook for ChatGPT and Codex.

To build a useful skill:

1. **Choose one focused task.** Note what you normally start with, such as files, links, or notes, and what a finished result should look like.
2. **Describe the workflow.** In ChatGPT, start with `@skill-creator`; in Codex, use `$skill-creator`. Explain the goal, the steps to follow, the expected format, and anything the skill should always include or avoid. Add a template or a good example when you have one.
3. **Review and try the draft.** Check the instructions, test the skill with a realistic request, and refine it if the result misses a step or drifts from the format you want.
4. **Install and reuse it.** Once the skill is enabled, ChatGPT or Codex can use it for relevant requests, or you can select it explicitly. You can also share it with teammates when your workspace settings allow it.

## Use plugins for tools and shared workflows:

A plugin can combine skills with connectors for services such as GitHub, Google Drive, or Slack, and can include MCP servers for additional tools and context.

## Choose between a skill and a plugin:

Use a skill when you need **reusable instructions** for a **focused** task. 

Use a plugin when you want an **installable package** that can combine instructions with connected services or other tools.

## 

