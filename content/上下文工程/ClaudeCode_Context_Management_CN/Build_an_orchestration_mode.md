+++
title = "构建编排模式"
slug = "mid-conversation-effort-example"
weight = 40
categories = ["上下文工程"]
tags = ["Context Engineering", "Claude"]
description = "构建一个会话级模式：为多智能体 fan-out 授予持续性授权，并通过会话中途的 system messages 打开和关闭。"
source_url = "https://platform.claude.com/docs/en/build-with-claude/mid-conversation-effort-example"
+++

编排模式是一个会话级开关：开启时，模型对每一个实质性请求都投入最大程度的彻底性，自行侦察任务，然后默认将工作 fan-out 给并行子代理。关闭时，同一个编排工具恢复为按请求 opt-in。

该模式不是 API 参数。它完全由文档中已有的组件构成：

1. **一个 effort 级别：** 请求以文档中的 [Effort](https://platform.claude.com/docs/en/build-with-claude/effort) 值运行，例如 `xhigh`。该页面所列级别之上没有隐藏级别。本示例在每个请求的顶层设置 effort，无需 beta header。
2. **一条模式提醒：** 一条 [会话中途的 system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages) 告知模型该模式处于活动状态，每隔若干轮附带一行刷新提醒，并在关闭模式时发送退出通知。顶层 `system` 字段始终不变，因此缓存前缀保持完整。
3. **工具描述中的持续性授权：** 编排工具的描述写明：模式开启时，模型应为每一个实质性任务编写并运行 workflow，无需事先询问。

<Note>
  本示例使用会话中途的 system messages；关于支持它们的模型与平台，见 [会话中途的 system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)。fan-out 本身会成倍增加 token 用量：一次请求可以催生许多子代理对话，因此请把该模式留给值得付出成本的工作。
</Note>

## 设置循环

该示例是单个文件。常量控制 effort 级别、fan-out 形态，以及模式刷新提醒的重发频率。`MAX_CONCURRENT` 限制同时运行的子代理数量（PHP 移植版是顺序执行并忽略该值）；`MAX_TOTAL_SUBTASKS` 限制模型在单次 Workflow 调用中可以排队的数量。把两者分开，让模型可以规划大量积压任务，而不必一次全部启动。当设置了环境变量 `DOC_TEST_MODE` 时，该检查会把循环限制为单轮，以便自动化文档 harness 验证文件能够编译并迅速结束，而无需跑完整编排；你自己运行示例时请保持其未设置。

<CodeGroup>
  ```python Python
  import atexit
  import concurrent.futures
  import hashlib
  import json
  import os
  import shutil
  import subprocess
  import sys
  import tempfile
  import threading

  import anthropic

  client = anthropic.Anthropic()

  MODEL = "claude-opus-5"
  EFFORT = "xhigh"

  SYSTEM_PROMPT = "You are a helpful general-purpose agent. Answer the user's request directly."

  REQUEST_TIMEOUT_SECONDS = 600
  BASH_TIMEOUT_SECONDS = 60
  TOOL_RESULT_MAX_CHARS = 8000
  MAX_CONCURRENT = 10
  DOC_TEST_MODE = bool(os.environ.get("DOC_TEST_MODE"))
  MAX_TOTAL_SUBTASKS = 2 if DOC_TEST_MODE else 200
  MAX_SUBAGENT_TURNS = 1 if DOC_TEST_MODE else 15
  MAX_MAIN_TURNS = 1 if DOC_TEST_MODE else 30
  TURNS_BETWEEN_REFRESHERS = 10
  JOURNAL_PATH = os.environ.get("ORCH_JOURNAL") or "orchestration_journal.json"
  ```

</CodeGroup>

## 定义模式提醒

提醒刻意写得很短。它们切换模式，并指向工具描述——重量级指令就放在那里。全文只在模式开启时发送一次，刷新提醒只在若干用户轮次之后才重发，退出通知在模式关闭时发送一次。

<CodeGroup>
  ```python Python
  MODE_ENTER = (
      "Orchestration mode is on: optimize for the most exhaustive, correct answer rather than "
      "the fastest one. Use the Workflow tool on every substantive task, sized to the problem's "
      "natural decomposition rather than the maximum the tool allows. See the Workflow tool's "
      "description for standing consent, granularity guidance, and quality patterns. Work solo "
      "only on conversational or trivial turns."
  )
  MODE_REFRESH = (
      "Orchestration mode is still on. Use the Workflow tool; see its standing consent section."
  )
  MODE_EXIT = (
      "Orchestration mode is off. The Workflow tool's standard opt-in rule applies again."
  )
  ```

</CodeGroup>

## 在工具描述中授予持续性授权

Workflow 工具承载真正的行为契约：opt-in 规则、模式开启期间适用的持续性授权、用于确定 fan-out 规模的粒度指引，以及模型可以取用的质量模式（验证波、完备性批评者、多阶段分步）。子代理还会得到一个 `report_findings` 工具，使其结果以结构化 JSON 而非散文返回；bash 工具则是 Anthropic 定义的 `bash_20250124` 工具，在本地运行。

<CodeGroup>
  ```python Python
  WORKFLOW_TOOL = {
      "name": "Workflow",
      "description": (
          "Orchestrate a multiagent workflow: split a large task into independent subtasks "
          "and run them as parallel agents, then collect their results.\n\n"
          "Opt-in: only use this tool when the user explicitly asks for a workflow, or when a "
          "system message confirms that orchestration mode is on.\n\n"
          "Quality patterns: adversarial verification (a second wave of agents checks the first "
          "wave's findings against the source), a completeness critic (one agent hunts for what "
          "the others missed), and multiphase sequencing (understand, design, implement, and "
          "review as separate workflow calls, reading results between phases). A useful default "
          "is hybrid: scout inline first to discover the work-list, then fan out over it.\n\n"
          "Granularity: scope each subtask to a distinct concern, component, or question rather "
          "than per line or per file section. Scale the count to what the user asked for: a "
          "focused review of a module of a few hundred lines rarely needs more than about ten "
          "subtasks; a broad audit of a large codebase can justify more.\n\n"
          "Standing consent: while a system message confirms orchestration mode is on, that "
          "opt-in is standing. Author and run a workflow for every substantive task by default, "
          "and lean toward verifying findings adversarially. Work solo only on conversational "
          "turns or trivial mechanical edits. When a system message says the mode is off, "
          "revert to the opt-in rule above."
      ),
      "input_schema": {
          "type": "object",
          "properties": {
              "subtasks": {
                  "type": "array",
                  "items": {"type": "string"},
                  "description": "Independent subtask prompts to run as parallel agents",
              }
          },
          "required": ["subtasks"],
      },
  }

  BASH_TOOL = {"type": "bash_20250124", "name": "bash"}

  REPORT_TOOL = {
      "name": "report_findings",
      "description": (
          "Report the final findings for your subtask. Call this exactly once, when you are "
          "done investigating; it ends your task."
      ),
      "input_schema": {
          "type": "object",
          "properties": {
              "summary": {"type": "string", "description": "Two or three sentences of synthesis"},
              "findings": {
                  "type": "array",
                  "items": {
                      "type": "object",
                      "properties": {
                          "claim": {"type": "string", "description": "The finding, one sentence"},
                          "evidence": {
                              "type": "string",
                              "description": "How it was verified (file, line, or command output)",
                          },
                          "severity": {"type": "string", "enum": ["high", "medium", "low", "info"]},
                      },
                      "required": ["claim", "evidence", "severity"],
                  },
              },
          },
          "required": ["summary", "findings"],
      },
  }
  ```

</CodeGroup>

## 在本地运行 bash 工具

bash 处理器以超时运行所请求的命令，捕获合并后的 stdout 和 stderr，并截断结果，以免失控命令淹没上下文窗口。命令在你启动示例时所在的目录中运行，因此要指向某个项目，就从那里启动；当设置了 `DOC_TEST_MODE` 时，harness 会改为给 bash 一个退出时删除的小型一次性夹具目录。这里没有沙箱：命令以启动该示例的进程的权限运行。为清晰起见，本示例在全新的 subshell 中运行每一次调用，而不是维护 `bash_20250124` 契约所描述的持久会话；生产级代理应用长生命周期 shell 支撑该工具，使工作目录、环境以及 `restart` 动作按文档行为。

<CodeGroup>
  ```python Python
  # Run bash where the example was launched. In DOC_TEST_MODE the docs harness
  # points it at a throwaway fixture directory instead, removed on exit.
  if DOC_TEST_MODE:
      WORK_DIR = tempfile.mkdtemp(prefix="orchestration-")
      atexit.register(shutil.rmtree, WORK_DIR, ignore_errors=True)
      with open(os.path.join(WORK_DIR, "sample.py"), "w") as fixture:
          fixture.write(
              "def fib(n):\n"
              "    return n if n < 2 else fib(n - 1) + fib(n - 2)\n\n"
              "print(fib(10))\n"
          )
  else:
      WORK_DIR = os.getcwd()


  def run_bash(command: str) -> tuple[str, bool]:
      """Run a shell command and return (output, is_error). No sandbox: example code only."""
      print(f"[bash] {command}", file=sys.stderr)
      try:
          proc = subprocess.run(
              ["bash", "-c", command],
              cwd=WORK_DIR,
              capture_output=True,
              text=True,
              errors="replace",
              timeout=BASH_TIMEOUT_SECONDS,
          )
      except subprocess.TimeoutExpired:
          return f"command timed out after {BASH_TIMEOUT_SECONDS}s", True
      output = (proc.stdout + proc.stderr).strip() or "(no output)"
      if len(output) > TOOL_RESULT_MAX_CHARS:
          output = output[:TOOL_RESULT_MAX_CHARS] + f"\n(truncated at {TOOL_RESULT_MAX_CHARS} chars)"
      if proc.returncode != 0:
          output = f"(exit code {proc.returncode})\n{output}"
      return output, proc.returncode != 0


  def handle_bash_block(block) -> tuple[str, bool]:
      if block.input.get("restart") is True:
          return "Shell restarted.", False
      command = block.input.get("command")
      if not isinstance(command, str) or not command:
          return "bash error: no command was provided.", True
      return run_bash(command)
  ```

</CodeGroup>

## 运行一个子代理

每一个 workflow 子任务都会变成带 bash 工具的小型代理循环，并以与主循环相同的 effort 运行。每次 API 调用都有按请求的超时上限，因此连接中断只会让一个子代理降级，而不会卡住整次运行。

<CodeGroup>
  ```python Python
  def run_subagent(model: str, prompt: str) -> str:
      """One subagent: a small nested agent loop with the bash tool plus report_findings.
      Subagents inherit the main loop's effort level."""
      subagent_system = (
          "You are one agent in a larger parallel fan-out, assigned a single subtask. "
          "Investigate it directly, using bash to check facts rather than guessing, and finish "
          "by calling report_findings exactly once. Return findings, not narration."
      )
      messages = [{"role": "user", "content": prompt}]
      for _ in range(MAX_SUBAGENT_TURNS):
          with client.messages.stream(
              model=model,
              max_tokens=64000,
              system=subagent_system,
              output_config={"effort": EFFORT},
              tools=[BASH_TOOL, REPORT_TOOL],
              messages=messages,
              timeout=REQUEST_TIMEOUT_SECONDS,
          ) as stream:
              response = stream.get_final_message()
          messages.append({"role": "assistant", "content": response.content})
          if response.stop_reason == "pause_turn":
              continue
          if response.stop_reason != "tool_use":
              text = "".join(block.text for block in response.content if block.type == "text")
              if response.stop_reason == "max_tokens":
                  text += "\n\n(warning: subagent response was truncated at max_tokens)"
              return text
          tool_results = []
          report = None
          for block in response.content:
              if block.type != "tool_use":
                  continue
              if block.name == "report_findings":
                  report = json.dumps(block.input, indent=2)
                  output, is_error = "Findings recorded.", False
              elif block.name == "bash":
                  output, is_error = handle_bash_block(block)
              else:
                  output, is_error = f"unknown tool: {block.name}", True
              tool_results.append(
                  {
                      "type": "tool_result",
                      "tool_use_id": block.id,
                      "content": output,
                      "is_error": is_error,
                  }
              )
          if report is not None:
              return report
          messages.append({"role": "user", "content": tool_results})
      return "(subagent hit the turn limit before finishing)"
  ```

</CodeGroup>

## 将结果写入 journal，以便重跑时续跑

催生数十个子代理的 fan-out，从头重启代价很高。一个小型内容寻址 journal 使其幂等：在派发子代理之前，在本地 JSON 文件中查找其 prompt 的 SHA-256，若已有记录则返回该结果。中断运行后再重跑，只有从未完成的子任务才会被重新计算。journal 在多次运行之间去重，而不是在单次 fan-out 波次之内；删除 journal 文件即可重新开始。

<CodeGroup>
  ```python Python
  _journal_lock = threading.Lock()


  def _load_journal() -> dict:
      try:
          with open(JOURNAL_PATH) as file:
              return json.load(file) or {}
      except (OSError, json.JSONDecodeError):
          return {}


  def journaled(prompt: str, compute) -> str:
      """Return a cached result for this exact prompt, or compute and persist it. This
      makes the fan-out resumable: interrupt the run, rerun it, and only the subtasks
      that never finished are recomputed. Delete the journal file to start fresh."""
      key = hashlib.sha256(prompt.encode()).hexdigest()
      cached = _load_journal().get(key)
      if cached is not None:
          print(f"[journal] cache hit for {key[:12]}", file=sys.stderr)
          return cached
      result = compute()
      try:
          with _journal_lock:  # fan-out writes from many threads
              journal = _load_journal()
              journal[key] = result
              temp = f"{JOURNAL_PATH}.tmp"
              with open(temp, "w") as file:
                  json.dump(journal, file)
              os.replace(temp, JOURNAL_PATH)  # atomic on POSIX and Windows
      except OSError as error:  # the journal is best-effort; never discard a computed result
          print(f"[journal] write failed: {error}", file=sys.stderr)
      return result
  ```

</CodeGroup>

## 先 fan-out，再验证

fan-out 最多接受 `MAX_TOTAL_SUBTASKS` 条 prompt，经 journal 运行，同时进行中的不超过 `MAX_CONCURRENT` 个（PHP 移植版为顺序执行），并隔离失败，使一个损坏的子代理降级为错误字符串，而不是结束整次运行。第一波完成后，第二波复用同一条子代理路径，试图反驳每一条结果：每个验证者从源头重新推导这些论断，不确定时默认判定为已反驳。原始结果及其裁决都会返回给编排器，以便一并权衡。

<CodeGroup>
  ```python Python
  def normalize_subtasks(raw) -> list[str]:
      """Accept the subtasks input in whatever shape the model emits: an array, the array
      JSON-encoded as a single string, or a newline-separated list."""
      if isinstance(raw, str):
          try:
              raw = json.loads(raw)
          except json.JSONDecodeError:
              raw = raw.splitlines() if "\n" in raw else [raw]
      if not isinstance(raw, list):
          return []
      return [task.strip() for task in raw if isinstance(task, str) and task.strip()]


  def verify_prompt_for(subtask: str, result: str) -> str:
      return (
          "Adversarially verify the subagent result below: try to REFUTE it. Re-derive the "
          "claims yourself with bash rather than trusting the result, and look for evidence "
          "that contradicts them. Default to refuted if uncertain. Call report_findings with "
          "summary 'refuted: <why>' or 'confirmed: <why>', citing the file:line or command "
          "output that decided it.\n\n"
          f"Subtask: {subtask}\n\nResult to verify:\n{result}"
      )


  def run_workflow(model: str, raw_subtasks) -> tuple[str, bool]:
      """Run subtasks as parallel subagents, then run a second verification wave over
      the results, and return both. MAX_TOTAL_SUBTASKS bounds how many the model can
      queue; MAX_CONCURRENT bounds how many run at once."""
      all_subtasks = normalize_subtasks(raw_subtasks)
      subtasks = all_subtasks[:MAX_TOTAL_SUBTASKS]
      dropped = len(all_subtasks) - len(subtasks)
      if not subtasks:
          return "Workflow error: no usable subtasks were provided.", True
      print(f"[workflow] fanning out {len(subtasks)} agents", file=sys.stderr)

      def run_one(prompt: str) -> str:
          try:
              return journaled(prompt, lambda: run_subagent(model, prompt))
          except Exception as error:  # isolation boundary: one bad subagent should not end the run
              return f"(subagent failed: {type(error).__name__}: {error})"

      with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_CONCURRENT) as pool:
          results = list(pool.map(run_one, subtasks))
          print(f"[workflow] verifying {len(results)} results", file=sys.stderr)
          verify_prompts = [verify_prompt_for(task, result) for task, result in zip(subtasks, results)]
          verdicts = list(pool.map(run_one, verify_prompts))

      joined = "\n\n".join(
          f"[agent {index + 1}: {task}]\n{result}\n\n[verify {index + 1}]\n{verdict}"
          for index, (task, result, verdict) in enumerate(zip(subtasks, results, verdicts))
      )
      if dropped > 0:
          joined = (
              f"(note: {dropped} subtasks beyond MAX_TOTAL_SUBTASKS={MAX_TOTAL_SUBTASKS} were not "
              "run; rerun them in a follow-up Workflow call)\n\n" + joined
          )
      return joined, False
  ```

</CodeGroup>

## 用会话中途的 system messages 切换模式

代理先追加用户消息，再追加本轮应付的任何 system messages：退出通知、进入时的完整模式文本，或周期性刷新提醒。把 system message 放在用户轮次之后，可使它前面的每一个缓存字节保持未动，并满足 system message 跟在用户轮次之后的放置规则。

<CodeGroup>

  ```python Python
  class ModeAgent:
      """An agent loop whose orchestration mode is toggled with mid-conversation system messages."""

      def __init__(self, model: str, mode_on: bool = True):
          self.model = model
          self.mode_on = mode_on
          self.messages: list[dict] = []
          self._mode_announced = False
          self._exit_pending = False
          self._turns_since_reminder = 0

      def set_mode(self, mode_on: bool) -> None:
          """Turn the mode on or off. The notice is delivered with the next user turn."""
          if mode_on == self.mode_on:
              return
          if not mode_on:
              if self._mode_announced:
                  self._exit_pending = True
          else:
              self._exit_pending = False
          self.mode_on = mode_on

      def _due_system_messages(self) -> list[dict]:
          """System messages owed on this turn: an exit notice, the full mode text on entry,
          or a one-line refresher every TURNS_BETWEEN_REFRESHERS user turns."""
          due = []
          if self._exit_pending:
              self._exit_pending = False
              self._mode_announced = False
              due.append({"role": "system", "content": MODE_EXIT})
          if self.mode_on:
              if not self._mode_announced:
                  self._mode_announced = True
                  self._turns_since_reminder = 0
                  due.append({"role": "system", "content": MODE_ENTER})
              elif self._turns_since_reminder >= TURNS_BETWEEN_REFRESHERS:
                  self._turns_since_reminder = 0
                  due.append({"role": "system", "content": MODE_REFRESH})
          return due

      def turn(self, user_input: str) -> str:
          # Mid-conversation system messages follow the user turn they apply to, which keeps
          # the cached prefix ahead of them untouched.
          self.messages.append({"role": "user", "content": user_input})
          self.messages.extend(self._due_system_messages())
          self._turns_since_reminder += 1

          for _ in range(MAX_MAIN_TURNS):
              with client.messages.stream(
                  model=self.model,
                  max_tokens=64000,
                  system=SYSTEM_PROMPT,  # static for the whole session
                  output_config={"effort": EFFORT},
                  tools=[WORKFLOW_TOOL, BASH_TOOL],
                  messages=self.messages,
                  timeout=REQUEST_TIMEOUT_SECONDS,
              ) as stream:
                  response = stream.get_final_message()
              self.messages.append({"role": "assistant", "content": response.content})

              if response.stop_reason == "pause_turn":
                  continue
              if response.stop_reason != "tool_use":
                  text = "".join(block.text for block in response.content if block.type == "text")
                  if response.stop_reason == "max_tokens":
                      # Drop the truncated assistant message so later turns don't build on it.
                      self.messages.pop()
                      text += "\n\n(warning: response was truncated at max_tokens)"
                  return text

              tool_results = []
              for block in response.content:
                  if block.type != "tool_use":
                      continue
                  if block.name == "Workflow":
                      output, is_error = run_workflow(self.model, block.input.get("subtasks", []))
                  elif block.name == "bash":
                      output, is_error = handle_bash_block(block)
                  else:
                      output, is_error = f"unknown tool: {block.name}", True
                  tool_results.append(
                      {
                          "type": "tool_result",
                          "tool_use_id": block.id,
                          "content": output,
                          "is_error": is_error,
                      }
                  )
              self.messages.append({"role": "user", "content": tool_results})
          return "(hit the main loop turn limit before finishing)"
  ```

</CodeGroup>

## 运行它

<Warning>
  本示例中的 bash 工具会在你的机器上直接运行模型编写的命令，没有沙箱，而且 fan-out 会并行运行若干这样的代理。请在你愿意暴露的目录和环境中运行，并在把它改造成超出本地实验用途之前加上沙箱。
</Warning>

<CodeGroup>
  ```python Python
  if __name__ == "__main__":
      task = (
          sys.argv[1]
          if len(sys.argv) > 1
          else "Explore the current directory, then give a thorough review: what it does, "
          "code-quality issues, and concrete improvements."
      )
      agent = ModeAgent(MODEL)
      print(agent.turn(task))
      agent.set_mode(False)
      print(agent.turn("Briefly summarize what you found above, no fan-out needed."))
  ```

</CodeGroup>

从你希望代理工作的目录启动该示例，例如要审查的仓库根目录：

模式开启时，预期模型会用几条 bash 命令侦察，主动派发 Workflow 工具，并把子代理报告综合成最终答案。琐碎或对话性请求会保持单独处理，正如提醒所指示的。

## 迈向生产级 harness

本示例刻意保持精简。面向真实工作负载的 harness 通常还会加上：

* **带沙箱的编排脚本：** 让模型发出一段简短的编排程序（分支、循环和 reduce 步骤），并在隔离的解释器中运行，而不是只接受扁平的子任务字符串列表。
* **持久 journaling：** 用能在进程重启后存活、且在跨机器并发写入下安全的存储，替换本地 JSON 文件。
* **预算强制：** 跟踪整个会话中启动的子代理总数，而不只是每次 Workflow 调用，并拒绝超过硬上限，以免失控计划耗尽你的配额。

本示例中的模式（模式提醒、工具描述中的持续性授权、journaling，以及验证波）原样沿用；只是它们周围的执行基底会更稳健。

## 相关内容

<CardGroup cols={2}>
  <Card title="会话中途的 system messages" icon="message" href="https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages">
    模式提醒所使用的机制，以及它如何与 Prompt Caching 交互。
  </Card>

  <Card title="Effort" icon="gauge" href="https://platform.claude.com/docs/en/build-with-claude/effort">
    API 接受的 effort 级别，以及如何选择。
  </Card>

  <Card title="使用 Claude 的工具调用" icon="wrench" href="https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview">
    定义工具、处理工具调用，以及工具结果。
  </Card>

  <Card title="Bash tool" icon="terminal" href="https://platform.claude.com/docs/en/agents-and-tools/tool-use/bash-tool">
    本示例在本地执行的 Anthropic 定义的 bash 工具。
  </Card>
</CardGroup>