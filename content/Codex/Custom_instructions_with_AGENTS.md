+++
title = 'AGENTS.md 自定义指令'
slug = "codex-agents-instructions"
date = 2026-09-07T00:00:00+08:00
lastmod = 2026-09-09T00:00:00+08:00
weight = 1
categories = ['Codex']
tags = ['AGENTS.md', '自定义指令']
description = 'Codex 如何发现并读取 AGENTS.md：指令链、配置回退文件名与生效方式。'
+++

## Custom instructions with AGENTS.md

agents.md is read before doing any work

## How codex discovers guidance:

The instruction chain:

### 1.Global scope:

in your Codex directory(default~/.codex):
u can also use AGENTS.override.md,but only the first non-empty AGENTS.md is read

### 2.Project scope:

At the project root
in each directory along the path,it checks for AGENTS.override.md ,then AGENTS.md,then any fallback names in `project_doc_fallback_filenames`. 
Codex includes at most one file per directory

### 3.Merge order:

The later ,the higher : because they appear later in the prompt


### Create global guidance:

1.make sure the directory exist:
2.create with reusable preference
3.run codex anywhere to confirm it loads the file

if you want a temporary global ,use AGENTS.override.md

### Layer project instructions:

1.In your repository root, add an `AGENTS.md` that covers basic setup
2.Add overrides in nested directories when specific teams need different rules. For example, inside `services/payments/` create `AGENTS.override.md`
3.Start Codex from the payments directory:

### Add code reviews rules:

For [Codex code review in GitHub](https://learn.chatgpt.com/docs/third-party/github#customize-what-codex-reviews), add a `## Code Review Rules` section to the `AGENTS.md` closest to the code the rules govern. Put repository-wide checks at the root and service-specific checks in a nested file.

### Customize fallback filenames:

if u use a customize filename,add it to the fallback list then Codex can really read it as a instructions file:
1.edit your  Codex configuration

```
# ~/.codex/config.toml
project_doc_fallback_filenames = ["TEAM_GUIDE.md", ".agents.md"]
project_doc_max_bytes = 65536
```

2.Restart Codex or run a new command to update  configuration loads:

