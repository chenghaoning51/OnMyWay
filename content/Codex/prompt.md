+++
title = 'Prompting 要点'
slug = "codex-prompting"
date = 2026-09-07T00:00:00+08:00
lastmod = 2026-09-09T00:00:00+08:00
weight = 4
categories = ['Codex']
tags = ['Prompt']
description = '提示词结构要点：目标、上下文与输出的格式、长度与详细程度。'
+++

## Prompting

## overview

Larger task,plz include these parts:
Goal
Context
Output: format,length,level of detail
Boundaries

## Describe the result u need:

not detailed list,but needed details those change what AI should produce

## Add useful context:

for example:
necessary attach file;
visual work: screenshot,image;and point out which area matters
web search: Explicitly( 显式地 ) ask to use Web Search in the conversation.
share resources: using a directory

## Use connected sources:

name where it should look and what if should find

## Using plugins:

plugins provide reusable instructions and connections to tools
Ask for the result u need and let the active surface choose from the tools available to it

## Personalize :

Put preferences that should apply across chats in **Settings > Personalization** as custom instructions.


## Set boundaries that prevent real problems:

avoid creating extra work or taking an action u did not asked.

- Keep the approved dates and budget figures unchanged.
- Use only the supplied sources. Flag missing information instead of guessing.
- Keep recommendations within the stated budget.
- Prepare the message as a draft. Don't send it.
  focus on the one or two boundaries that really matters

## Improve the result with follow-up messages:

Your first prompt doesn't need to be perfect. Review the result, then ask for the specific change you want.

## Steering and queuing:

Steer add to the current run;Queue for the next run.
In the CLI,using Enter to steer,and Tab to queue.

## Put the pieces together:

include the four parts(maybe not all) above

## Use voice dictation:

Ctrl+Shift+Tab

## Prompting examples for chat:

start with the outcome u want and add details when it changes to the answer

### Understand a topic

```
Explain how compound interest works for someone who has never invested.
Use one concrete example and define any financial terms you introduce.
```

### Draft and refine writing

```
Draft a friendly email declining this invitation because I will be traveling.
Keep it under 120 words and leave the door open for a future event.
```

### Compare options

```
Compare these two phone plans for one person who travels internationally twice
a year. Show the important differences in a table, then recommend one and explain
the tradeoff.
```

### Make a practical plan

```
Plan five weekday dinners that take less than 30 minutes. Avoid peanuts, reuse
ingredients across meals, and finish with one consolidated shopping list.
```

## Prompting codex:

Name the behavior u want,points to the relevant code or codebase or reproduction steps,preserves important constraints and says how to verify the change.

For a muti-step task,**/plan** when u want codex to investigate and propose an approach before editing.
**/goal** to set a persistent goal
CLI: using **/mention** and @ path autocomplete
Codex runs local commands inside a sandbox that limits file and network access

## Explain a codebase:

```
Explain how the request flows through the selected code.

Include:
- a short summary of the responsibilities of each module involved
- what data is validated and where
- one or two "gotchas" to watch for when changing this
```

## Fix a bug:

Give Codex a reproduction recipe, plus the file(s) you suspect

Context notes: by u and by Codex itself
Verification:
	Run the repro steps after fix
	if u have a standard check pipeline ,ask it to run it

## Write a test:

Prompt with a function name:
by the way,function name should be meaningful



