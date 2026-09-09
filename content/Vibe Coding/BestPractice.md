+++
title = 'Vibe Coding 最佳实践'
slug = "vibe-coding-best-practices"
date = 2026-09-09T00:00:00+08:00
lastmod = 2026-09-09T00:00:00+08:00
weight = 1
categories = ['Vibe Coding']
tags = ['Best Practices', 'Codex']
description = 'Vibe coding 最佳实践：上下文与提示词、并行协作、验证优先与常见反模式。'
+++


## Best practices

## Strong first use : Context and Prompts

Clear prompting makes results more reliable
A good default is to include four things in your prompt:

- **Goal:** What are you trying to change or build?
- **Context:** Which files, folders, docs, examples, or errors matter for this task? You can @ mention certain files as context.
- **Constraints:** What standards, architecture, safety requirements, or conventions should Codex follow?
- **Done when:** What should be true before the task is complete, such as tests passing, behavior changing, or a bug no longer reproducing?

it is similar to Claude Code Best practices

## Plan first for difficult tasks

A few approaches work well:
	**Use Plan mode**:/plan or Shift + Tab
	**Ask Codex to interview you**: when your idea is ambiguous
	**Use a PLANS.md template**: use PLANS.md 

## Make guidance reusable with AGENTS.md

Think of `AGENTS.md` as an open-format README for agents.

A good `AGENTS.md` covers:

- repo layout and important directories
- How to run the project
- Build, test, and lint commands
- Engineering conventions and PR expectations
- Constraints and do-not rules
- What done means and how to verify work

I think information above is very important!!!!
**/init** to scaffold a starter AGENTS.md
**Keep it practical.** 
A short, accurate `AGENTS.md` is more useful than a long file full of vague rules.
If `AGENTS.md` starts getting too large, keep the main file concise and reference task-specific markdown files for things like planning, code review, or architecture.

## Configure Codex for consistency

A good starting pattern is:

- Keep personal defaults in `~/.codex/config.toml` (**Settings > Configuration > Open config.toml** in the ChatGPT desktop app)
- Keep repo-specific behavior in `.codex/config.toml`
- Use command-line overrides only for one-off situations (if you use the CLI)

## Improve reliability with testing and review

Don't stop at asking Codex to make a change. Ask it to create tests when needed, run the relevant checks, confirm the result, and review the work before you accept it.
Codex can do this loop for you, but only if it knows what “good” looks like. That guidance can come from either the prompt or `AGENTS.md`.
**/review** gives you a few ways to review code

If you and your team have a `code_review.md` file and reference it from `AGENTS.md`, Codex can follow that guidance during review as well. 

## Use MCPs for external context

Use MCP when:

- The needed context lives outside the repo
- The data changes frequently
- You want Codex to use a tool rather than rely on pasted instructions
- You need a repeatable integration across users or projects

`codex mcp add` command in the CLI to add your custom servers with a name, URL, and other details.

## Turn repeatable work into skills

Use a [skill](https://learn.chatgpt.com/docs/build-skills) to package the instructions in a `SKILL.md` file

What a skill.md file should include:
1.Keep each skill scoped to one job
2.Start with 2 to 3 concrete use cases
3.define clear inputs and outputs
4.write the description so it says what the skill does and when to use it
5.Include the kinds of trigger phrases a user would actually say

The often situation:

- Log triage
- Release note drafting
- PR review against a checklist
- Migration planning
- Telemetry or incident summaries
- Standard debugging flows

The `$skill-creator` skill is the best place to start to scaffold the first version of a skill. 

## Use scheduled tasks for repeated work

Good candidates include:

- Summarizing recent commits
- Scanning for likely bugs
- Drafting release notes
- Checking CI failures
- Producing standup summaries
- Running repeatable analysis workflows on a schedule

## Organize long-running chats

The ChatGPT desktop app lets you pin chats and create worktrees. If you use the CLI, these [slash commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli) are especially useful:

- `/experimental` to toggle experimental features and add to your `config.toml`
- `/resume` to resume a saved chat
- `/fork` to create a new chat while preserving the original transcript
- `/compact` when the chat is getting long and you want a summarized version of earlier context. Codex also compacts chats automatically
- `/agent` when you are running parallel agents and want to switch between the active agent thread
- `/theme` to choose a syntax highlighting theme
- `/apps` to use ChatGPT apps directly in Codex
- `/status` to inspect the current session state

## Common mistakes

A few common mistakes to avoid when first using Codex:

- Overloading the prompt with durable rules instead of moving them into `AGENTS.md` or a skill
- Not letting the agent see its work by not giving details on how to best run build and test commands
- Skipping planning on multi-step and complex tasks
- Giving Codex full permission to your computer before you understand the workflow
- Running live tasks on the same files without using Git worktrees
- Scheduling a recurring task before it's reliable manually
- Treating Codex like something you have to watch step by step instead of using it in parallel with your own work
- Using one chat for an entire project instead of one chat per coherent outcome. This leads to bloated context and worse results over time
