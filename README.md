# AXION

AXION is a personal local-first macOS agent built with SwiftUI, AppKit, and a bundled `llama-server` runtime.

It is designed as a structured tool-routing system rather than a general chat assistant: the model is prompted to return compact JSON, the app parses that JSON into typed tool calls, applies runtime guardrails, executes local actions, and feeds tool results back into the conversation loop when needed.

## Design Goals

- Keep inference local.
- Constrain model output to a narrow JSON protocol.
- Normalize predictable model drift in code when it is safe to do so.
- Separate prompt routing, parsing, guardrails, and tool execution.
- Benchmark routing quality with reproducible datasets.

## Tool Surface

AXION exposes tools across these groups:

- Files: open, reveal, read, create, append, list, rename, move, delete, search, archive, organize, clean.
- Web apps: open apps, open URLs, focus apps, hide apps, quit apps.
- Text: copy to clipboard, read clipboard, get current date/time, Spotlight search.
- System: notifications, screenshots, volume, battery status, dark mode.
- Dev: list processes, open in VS Code, git status, open Terminal in a folder.
- Third-party: reminders and calendar events.

## Request Lifecycle

For a typical request, the runtime flow is:

1. The user sends a message in the chat UI.
2. `ChatService` builds an OpenAI-compatible `messages` payload and sends it to `http://localhost:8080/v1/chat/completions`.
3. The model is expected to return one compact JSON object in one of three shapes:
   - `tool_call`
   - `plan`
   - `final`
4. `AgentResponse` parses and normalizes the response into internal types.
5. `AgentService` decides whether to:
   - execute the tool
   - reject and reprompt with a guardrail message
   - request confirmation for sensitive actions
   - continue the loop for multi-step tasks
6. Tool results are injected back into the message history and sent to the model again when more steps are required.

The model is therefore not trusted to directly control the machine. It is treated as a planner/router operating behind a typed execution layer.

## Architecture

Main components:

- `src/Managers/AppDelegate.swift`
  - Menu bar lifecycle, floating window positioning, global hotkey registration.
- `src/UI/ChatView.swift`
  - Main UI, confirmation flow, debug visibility rules, tool result rendering.
- `src/Services/ChatService.swift`
  - Prompt loading, context compaction, request construction, HTTP transport.
- `src/Services/AgentService.swift`
  - Core agent loop, multi-step orchestration, runtime guardrails, confirmation handling.
- `src/Models/AgentResponse.swift`
  - JSON parsing and normalization layer between raw model output and executable tool calls.
- `src/Models/ToolCall.swift`
  - Canonical tool representation plus argument packing for execution.
- `src/Tools/*`
  - Concrete tool implementations and execution result formatting.
- `src/Tools/ToolRegistry.swift`
  - Tool registration, category validation, final execution dispatch.
- `src/Managers/LlamaServerManager.swift`
  - Starts, stops, and health-checks the bundled `llama-server` process.

## Protocol

The model is instructed to emit compact JSON only.

Expected response shapes:

```json
{"type":"tool_call","category":"CATEGORY","tool":"TOOL","params":{}}
```

```json
{"type":"plan","steps":[{"category":"CATEGORY","tool":"TOOL","params":{}},{"category":"CATEGORY","tool":"TOOL","params":{}}]}
```

```json
{"type":"final","content":"OK"}
```

The runtime deliberately performs a second validation layer after generation:

- tool/category normalization
- param normalization
- safe rewrites for common model drift
- prompt-aware guardrails
- confirmation gates for destructive actions

This split is intentional: the prompt defines the contract, while the runtime absorbs recoverable deviations and blocks unsafe behavior.

## Feature branch: summarize tools

This branch adds two LLM-powered summarization tools:

- `summarize_text`: summarizes provided text.
- `summarize_file`: reads and summarizes a local text-based file.

Supported summary styles:
- `short`
- `detailed`
- `bullet_points`
- `technical`

Examples:

```json
{"type":"tool_call","category":"text","tool":"summarize_text","params":{"text":"AXION is a local macOS assistant.","style":"short"}}
```

```json
{"type":"tool_call","category":"files","tool":"summarize_file","params":{"path":"~/Projects/AXION/README.md","style":"bullet_points"}}
```

The tools use the local LLM through *ChatService* with a dedicated summarization prompt, separated from the main tool-routing prompt.

## Setup

### Requirements

- macOS
- Xcode
- A local GGUF model

### Run the App

1. Open `AXION.xcodeproj` in Xcode.
2. Build and run the `AXION` target.
3. In Settings, select the path to your GGUF model.
4. AXION starts `llama-server` automatically on port `8080`.
5. Open the app from the menu bar.

### Shortcut

The default global shortcut is:

- `Control + Option + Space`

## Runtime Notes

- The app expects an OpenAI-compatible chat completion endpoint exposed by `llama-server`.
- The routing contract is defined in `data/system_prompt.txt`.
- `ChatService` sends the system prompt plus a bounded slice of recent history.
- Tool messages are compacted before being reintroduced into context.
- The app uses deterministic generation settings (`temperature: 0`, `max_tokens: 160`) for routing stability.

## Benchmarks

Two benchmark scripts are included:

- `benchmark.py`
  - Single-step routing benchmark.
- `benchmark_multistep.py`
  - Multi-step agent benchmark.

They are intended to measure routing quality rather than end-user UX. Current outputs track things such as:

- JSON validity
- strict tool selection accuracy
- parameter accuracy
- recoverable vs non-recoverable failures
- multi-step loop completion
- approximate latency and model memory usage

Run them from the `AXION/` directory:

```bash
python3 benchmark.py
python3 benchmark_multistep.py
```

## Development Philosophy

AXION is a personal engineering project focused on a narrow question:

How far can a local model be pushed as a reliable macOS tool router when the runtime is strict, typed, and benchmarked?

The project therefore prioritizes:

- native app shell
- local inference
- strict tool routing
- defensive runtime normalization
- benchmark-driven iteration

It is opinionated, experimental, and optimized for iteration on agent reliability rather than for becoming a generic SDK.

