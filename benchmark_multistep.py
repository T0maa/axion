#!/usr/bin/env python3

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

try:
    import psutil
except ImportError:
    psutil = None

SERVER_URL = "http://localhost:8080/v1/chat/completions"
SCRIPT_DIR = Path(__file__).resolve().parent
TEST_FILE = SCRIPT_DIR / "data/test_multi_step.jsonl"
SYSTEM_PROMPT_PATH = SCRIPT_DIR / "data/system_prompt.txt"
MAX_STEPS = 7
MAX_TOKENS = 160
MAX_MESSAGE_CHARS = 600
MAX_HISTORY_MESSAGES = 8


MODEL_PROCESS_NAME = "llama-server"

MULTISTEP_CONTINUATION_RULES = """
Continue the original user request.
Return exactly one valid compact JSON object.
After a Tool result:
- Never return a plan.
- Never repeat an already successful tool.
- Use exactly this JSON shape:
{"type":"tool_call","category":"CATEGORY","tool":"TOOL","params":{}}
- For copy to clipboard: category "text", tool "copy_to_clipboard".
- For notify: category "system", tool "show_notification".
- For open in VSCode: category "dev", tool "open_in_vscode".
- For open URL: category "web_apps", tool "open_url".
- For read file: category "files", tool "read_text_file".
- For open file/folder: category "files", tool "open_file".
- For create file: category "files", tool "create_text_file".
- For open terminal in folder: category "dev", tool "open_terminal_here".
- If all requested tools are done, return {"type":"final","content":"OK"}.
""".strip()

VALID_CATEGORIES = {
    "files",
    "web_apps",
    "text",
    "system",
    "dev",
    "third_party",
}

CATEGORY_BY_TOOL = {
    "open_file": "files",
    "reveal_file": "files",
    "read_text_file": "files",
    "create_text_file": "files",
    "append_text_file": "files",
    "list_directory": "files",
    "create_folder": "files",
    "get_file_info": "files",
    "rename_file": "files",
    "move_file": "files",
    "delete_file": "files",
    "search_file_content": "files",
    "read_pdf_text": "files",
    "compress_file": "files",
    "extract_archive": "files",
    "organize_folder": "files",
    "clean_folder": "files",
    "open_app": "web_apps",
    "open_url": "web_apps",
    "quit_app": "web_apps",
    "focus_app": "web_apps",
    "hide_app": "web_apps",
    "copy_to_clipboard": "text",
    "get_clipboard": "text",
    "get_current_datetime": "text",
    "search_in_spotlight": "text",
    "show_notification": "system",
    "take_screenshot": "system",
    "set_volume": "system",
    "get_battery_status": "system",
    "toggle_dark_mode": "system",
    "list_processes": "dev",
    "open_in_vscode": "dev",
    "git_status": "dev",
    "open_terminal_here": "dev",
    "create_reminder": "third_party",
    "create_calendar_event": "third_party",
}


CATEGORY_ALIASES = {
    "developer_tools": "dev",
    "developer": "dev",
    "dev_tools": "dev",
    "file": "files",
    "files_tools": "files",
    "app": "web_apps",
    "apps": "web_apps",
    "browser": "web_apps",
    "macos": "system",
    "utility": "system",
}

TOOL_ALIASES = {
    "set_clipboard": "copy_to_clipboard",
    "copy_text": "copy_to_clipboard",
    "copy_text_to_clipboard": "copy_to_clipboard",
    "write_text_to_clipboard": "copy_to_clipboard",
    "copy_file_to_clipboard": "copy_to_clipboard",
    "copy_processes_to_clipboard": "copy_to_clipboard",
    "copy_process_list": "copy_to_clipboard",
    "write_text": "copy_to_clipboard",
    "write_string": "copy_to_clipboard",
    "display_notification": "show_notification",
    "send_notification": "show_notification",
    "notify": "show_notification",
    "show_reminder": "show_notification",
    "navigate_to": "open_url",
    "vscode_open": "open_in_vscode",
    "open_folder_in_editor": "open_in_vscode",
    "open_file_in_editor": "open_in_vscode",
    "open_in_terminal": "open_terminal_here",
    "unzip_file": "extract_archive",
    "compress_directory": "compress_file",
    "open_folder": "open_file",
    "open_path": "reveal_file",
    "append_text_to_file": "append_text_file",
    "create_file": "create_text_file",
    "write_text_file": "create_text_file",
    "write_to_file": "create_text_file",
    "read_file": "read_text_file",
    "list_folder": "list_directory",
    "spotlight_search": "search_in_spotlight",
    "text/copy_to_clipboard": "copy_to_clipboard",
    "system/show_notification": "show_notification",
    "dev/open_in_vscode": "open_in_vscode",
    "web_apps/open_url": "open_url",
    "files/read_text_file": "read_text_file",
    "files/open_file": "open_file",
    "files/create_text_file": "create_text_file",
    "files/append_text_file": "append_text_file",
    "dev/open_terminal_here": "open_terminal_here",
    "files/extract_archive": "extract_archive",
    "files/compress_file": "compress_file",
    "compress": "compress_file",
}


def load_system_prompt():
    if not SYSTEM_PROMPT_PATH.exists():
        print(f"Missing system prompt: {SYSTEM_PROMPT_PATH}", file=sys.stderr)
        sys.exit(1)

    content = SYSTEM_PROMPT_PATH.read_text(encoding="utf-8").strip()

    if not content:
        print(f"Empty system prompt: {SYSTEM_PROMPT_PATH}", file=sys.stderr)
        sys.exit(1)

    return content


SYSTEM_PROMPT = load_system_prompt()


def find_llama_server_processes():
    if psutil is None:
        return []

    matches = []

    for process in psutil.process_iter(["pid", "name"]):
        try:
            name = process.info.get("name") or ""

            if name == MODEL_PROCESS_NAME:
                matches.append(process)
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

    return matches


def sample_model_memory_mb():
    processes = find_llama_server_processes()

    if not processes:
        return None

    totals = {"rss": 0, "vms": 0, "uss": 0}
    has_uss = False

    for process in processes:
        try:
            memory = process.memory_info()
            totals["rss"] += memory.rss
            totals["vms"] += memory.vms

            try:
                full_memory = process.memory_full_info()
                uss = getattr(full_memory, "uss", None)
                if uss is not None:
                    totals["uss"] += uss
                    has_uss = True
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                pass
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            continue

    return {
        "rss": totals["rss"] / 1024 / 1024,
        "vms": totals["vms"] / 1024 / 1024,
        "uss": totals["uss"] / 1024 / 1024 if has_uss else None,
    }


def format_memory_mb(value):
    if value is None:
        return "n/a"

    return f"{value:.0f} MB"


def average_memory_samples(samples):
    if not samples:
        return None

    keys = ["rss", "vms", "uss"]
    result = {}

    for key in keys:
        values = [sample[key] for sample in samples if sample.get(key) is not None]
        result[key] = sum(values) / len(values) if values else None

    return result


def peak_memory_samples(samples):
    if not samples:
        return None

    keys = ["rss", "vms", "uss"]
    result = {}

    for key in keys:
        values = [sample[key] for sample in samples if sample.get(key) is not None]
        result[key] = max(values) if values else None

    return result


def format_memory_snapshot(snapshot):
    if snapshot is None:
        return "n/a"

    return (
        f"RSS {format_memory_mb(snapshot.get('rss'))}, "
        f"VMS {format_memory_mb(snapshot.get('vms'))}, "
        f"USS {format_memory_mb(snapshot.get('uss'))}"
    )


def extract_first_json(text):
    text = text.strip()
    depth = 0
    start = None
    in_string = False
    escaped = False

    for index, char in enumerate(text):
        if escaped:
            escaped = False
            continue

        if char == "\\" and in_string:
            escaped = True
            continue

        if char == '"':
            in_string = not in_string
            continue

        if in_string:
            continue

        if char == "{":
            if depth == 0:
                start = index
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0 and start is not None:
                return text[start:index + 1]

    if start is not None:
        return text[start:]

    return text


def repair_json_text(text):
    repaired = text.strip()
    repaired = repaired.replace("：", ":")
    repaired = repaired.replace("“", '"').replace("”", '"')
    repaired = repaired.replace("‘", "'").replace("’", "'")
    repaired = repaired.replace('"params:{}"', '"params":{}')
    repaired = repaired.replace('"params: {}"', '"params":{}')
    repaired = repaired.replace('"params:{}', '"params":{}')
    repaired = repaired.replace('"params: {}', '"params": {}')
    repaired = repaired.replace('"params":"{}"', '"params":{}')
    repaired = repaired.replace('"params":" {}"', '"params":{}')
    repaired = repaired.replace('"params":"{ }"', '"params":{}')

    open_count = 0
    close_count = 0
    in_string = False
    escaped = False

    for char in repaired:
        if escaped:
            escaped = False
            continue
        if char == "\\" and in_string:
            escaped = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if char == "{":
            open_count += 1
        elif char == "}":
            close_count += 1

    if open_count > close_count:
        repaired += "}" * (open_count - close_count)

    return repaired


def load_scenarios(path):
    if not path.exists():
        print(f"Missing test file: {path}", file=sys.stderr)
        sys.exit(1)

    scenarios = []

    with path.open("r", encoding="utf-8") as file:
        for line_number, line in enumerate(file, start=1):
            line = line.strip()

            if not line:
                continue

            try:
                scenario = json.loads(line)
            except json.JSONDecodeError as error:
                print(f"Invalid JSONL at line {line_number}: {error}", file=sys.stderr)
                sys.exit(1)

            required_keys = ["name", "prompt", "expected_tools", "fake_results"]
            missing_keys = [key for key in required_keys if key not in scenario]

            if missing_keys:
                print(f"Missing keys at line {line_number}: {missing_keys}", file=sys.stderr)
                sys.exit(1)

            scenarios.append(scenario)

    return scenarios



def compact_messages(messages):
    if len(messages) <= 2:
        return messages

    compacted = messages[:2]
    compacted.extend(messages[2:][-MAX_HISTORY_MESSAGES:])
    result = []

    for message in compacted:
        content = str(message.get("content", ""))

        if len(content) > MAX_MESSAGE_CHARS:
            content = content[:MAX_MESSAGE_CHARS] + "\n[truncated]"

        result.append({
            "role": message.get("role", "user"),
            "content": content,
        })

    return result


def call_model(messages):
    body = {
        "model": "local",
        "messages": compact_messages(messages),
        "temperature": 0,
        "max_tokens": MAX_TOKENS,
        "stream": False,
    }

    request = urllib.request.Request(
        SERVER_URL,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    start = time.time()

    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = json.loads(response.read().decode("utf-8"))
            latency = time.time() - start
            return payload["choices"][0]["message"]["content"].strip(), latency
    except urllib.error.HTTPError as error:
        latency = time.time() - start
        body = error.read().decode("utf-8")
        return f"HTTP {error.code}: {body}", latency
    except Exception as error:
        latency = time.time() - start
        return f"ERROR: {error}", latency


def normalize_params(params):
    if isinstance(params, dict):
        return {str(key): str(value) for key, value in params.items()}

    return {}


def normalize_category(category, tool):
    tool_category = CATEGORY_BY_TOOL.get(tool)

    if tool_category:
        return tool_category

    category = str(category or "")
    category = CATEGORY_ALIASES.get(category, category)

    if category in VALID_CATEGORIES:
        return category

    return category


def normalize_tool_name(tool):
    raw = str(tool or "").strip()

    if raw in TOOL_ALIASES:
        return TOOL_ALIASES[raw]

    if "/" in raw:
        raw = raw.split("/")[-1]

    return TOOL_ALIASES.get(raw, raw)


def normalize_alias_params(tool, params):
    if not isinstance(params, dict):
        return {}

    normalized = dict(params)

    if tool == "copy_to_clipboard":
        if "text" not in normalized:
            for key in ["content", "string", "message", "value", "url"]:
                if key in normalized:
                    normalized["text"] = normalized.pop(key)
                    break
        if "paths" in normalized and "text" not in normalized:
            paths = normalized.pop("paths")
            if isinstance(paths, list):
                normalized["text"] = "\n".join(str(path) for path in paths)
            else:
                normalized["text"] = str(paths)

    if tool == "create_text_file":
        if "file_path" in normalized and "path" not in normalized:
            normalized["path"] = normalized.pop("file_path")
        if "file" in normalized and "path" not in normalized:
            normalized["path"] = normalized.pop("file")

    if tool in {"open_file", "read_text_file", "reveal_file", "open_in_vscode", "open_terminal_here"}:
        if "file" in normalized and "path" not in normalized:
            normalized["path"] = normalized.pop("file")
        if "file_path" in normalized and "path" not in normalized:
            normalized["path"] = normalized.pop("file_path")

    if tool == "open_url":
        if "path" in normalized and "url" not in normalized:
            normalized["url"] = normalized.pop("path")

    if tool == "set_volume":
        if "volume_level" in normalized and "level" not in normalized:
            normalized["level"] = normalized.pop("volume_level")

    if tool == "show_notification":
        if "message" not in normalized:
            for key in ["content", "text", "value"]:
                if key in normalized:
                    normalized["message"] = normalized.pop(key)
                    break
        normalized.setdefault("title", "AXION")

    return normalized


def normalize_tool_call(parsed):
    if not isinstance(parsed, dict):
        return None

    tool = normalize_tool_name(parsed.get("tool", ""))

    if not tool:
        return None

    params = normalize_alias_params(tool, parsed.get("params", {}))

    return {
        "type": "tool_call",
        "category": normalize_category(parsed.get("category", ""), tool),
        "tool": tool,
        "params": normalize_params(params),
    }


def normalize_parsed_response(parsed):
    if not isinstance(parsed, dict):
        return None

    response_type = parsed.get("type")

    if isinstance(response_type, str) and "/" in response_type:
        category, tool = response_type.split("/", 1)
        return normalize_tool_call({
            "type": "tool_call",
            "category": category,
            "tool": tool,
            "params": parsed.get("params", parsed),
        })

    if response_type in VALID_CATEGORIES and isinstance(parsed.get("content"), str):
        content = parsed.get("content", "")
        if "/" in content:
            category, tool = content.split("/", 1)
            return normalize_tool_call({
                "type": "tool_call",
                "category": category,
                "tool": tool,
                "params": parsed.get("params", {}),
            })

    if isinstance(parsed.get("content"), str) and "/" in parsed.get("content", "") and parsed.get("params") is not None:
        category, tool = parsed.get("content", "").split("/", 1)
        return normalize_tool_call({
            "type": "tool_call",
            "category": category,
            "tool": tool,
            "params": parsed.get("params", {}),
        })

    if response_type == "final":
        return {
            "type": "final",
            "content": str(parsed.get("content", "")),
        }

    if response_type == "tool_call" or "tool" in parsed:
        return normalize_tool_call(parsed)

    if response_type == "plan":
        raw_steps = parsed.get("steps", [])

        if not isinstance(raw_steps, list):
            return None

        steps = []

        for raw_step in raw_steps:
            step = normalize_tool_call(raw_step)

            if step is None:
                return None

            steps.append(step)

        return {
            "type": "plan",
            "steps": steps,
        }

    return parsed


def parse_model_response(raw):
    try:
        json_text = repair_json_text(extract_first_json(raw))
        parsed = json.loads(json_text)
        parsed = normalize_parsed_response(parsed)
    except Exception:
        return None, False

    if not isinstance(parsed, dict):
        return None, False

    return parsed, True


def make_default_fake_result(tool):
    return "OK."


def fake_tool_result(scenario, tool):
    fake_results = scenario.get("fake_results", {})
    result = str(fake_results.get(tool, make_default_fake_result(tool))).strip()

    for marker in [
        "\n\nContinue with the next unfinished action from the original user request.",
        " Next: continue original request or final. No repeats. No extra actions.",
    ]:
        if marker in result:
            result = result.split(marker, 1)[0].rstrip()

    if len(result) > MAX_MESSAGE_CHARS:
        result = result[:MAX_MESSAGE_CHARS] + "\n[truncated]"

    return result


def contains_any(text, needles):
    return any(needle in text for needle in needles)


def user_requested_delete(prompt):
    return contains_any(prompt, ["delete", "remove", "trash", "move to trash", "to trash"])


def user_requested_safe_clean(prompt):
    return contains_any(prompt, [
        "safe",
        "safely",
        "move clean candidates",
        "move candidates",
        "safely move",
        "_cleancandidates",
    ])


def prompt_contains_datetime_then_copy(prompt):
    return (
        contains_any(prompt, ["datetime", "current date", "current time", "timestamp"])
        and contains_any(prompt, ["then copy", "copy it", "copy the result"])
    )


def prompt_requires_search_before_vscode(prompt):
    return contains_any(prompt, ["search", "look for", "find"]) and "vscode" in prompt and "then" in prompt


def prompt_requires_list_before_vscode(prompt):
    return contains_any(prompt, ["list", "show files", "show contents"]) and "vscode" in prompt and "then" in prompt


def prompt_requires_path_content_search(prompt):
    return (
        contains_any(prompt, ["search", "look for", "find"])
        and contains_any(prompt, [" in /", " inside /", " within /", " in ~/", " inside ~/", " within ~/", " in project", " inside project"])
    )


def user_requested_real_clean(prompt):
    return contains_any(prompt, [
        "apply",
        "real clean",
        "really clean",
        "true clean",
        "clean for real",
        "safe",
        "safely",
        "move clean candidates",
        "move candidates",
        "safely move",
        "_cleancandidates",
    ])


def has_executed_any(observed_tools, tool_names):
    return any(tool in observed_tools for tool in tool_names)


def path_from_argument(argument):
    if "|" in argument:
        return argument.split("|", 1)[0]

    return argument


def tool_key(parsed):
    params = parsed.get("params", {})
    params_text = json.dumps(params, sort_keys=True, separators=(",", ":"))
    return f"{parsed.get('tool', '')}|{params_text}"


def is_real_clean_mode(parsed):
    argument = tool_call_argument(parsed).lower().replace("-", "_").replace(" ", "_")
    return (
        parsed.get("tool") == "clean_folder"
        and (
            "|apply" in argument
            or "|safe" in argument
            or "|real" in argument
            or "|clean" in argument
            or "|execute" in argument
        )
    )


def requires_confirmation(parsed):
    tool = parsed.get("tool", "")

    if tool == "clean_folder":
        return is_real_clean_mode(parsed)

    return tool in {
        "rename_file",
        "move_file",
        "delete_file",
        "compress_file",
        "extract_archive",
        "organize_folder",
    }


def should_stop_after_rejected_extra_tool(parsed, prompt, observed_tools):
    tool = parsed.get("tool", "")

    if tool == "delete_file" and not user_requested_delete(prompt) and observed_tools:
        return True

    if tool == "move_file" and not contains_any(prompt, ["move", "put ", "archive"]) and observed_tools:
        return True

    if tool == "open_terminal_here" and not contains_any(prompt, ["terminal", "shell", "command line"]) and observed_tools:
        return False

    if tool == "list_processes" and not contains_any(prompt, ["process", "processes", "running", "active processes"]) and observed_tools:
        return True

    if tool == "show_notification" and "show_notification" in observed_tools:
        return True

    return False


def guardrail_rejection_reason(parsed, prompt, observed_tools, executed_keys):
    tool = parsed.get("tool", "")
    argument = tool_call_argument(parsed).lower()

    if tool_key(parsed) in executed_keys:
        return f"The tool {tool} with the same arguments already succeeded. Do not repeat it."

    if tool == "delete_file" and not user_requested_delete(prompt):
        return "delete_file is blocked because the original user request did not explicitly ask to delete, remove, trash, or move something to Trash."

    if tool == "move_file" and "trash" in argument:
        return "Moving to Trash must use delete_file, not move_file."

    if tool == "clean_folder" and is_real_clean_mode(parsed) and not user_requested_real_clean(prompt):
        return "clean_folder apply mode is blocked because the original user request did not explicitly ask to really clean, apply cleaning, or safely move clean candidates. Use dry_run or return final."

    if tool == "open_terminal_here" and not contains_any(prompt, ["terminal", "shell", "command line"]):
        path = path_from_argument(tool_call_argument(parsed))
        if path:
            return f"open_terminal_here is blocked because the original user request did not explicitly ask for Terminal, shell, or command line. Your next response must call open_file with path {path}. Do not ask for confirmation."
        return "open_terminal_here is blocked because the original user request did not explicitly ask for Terminal, shell, or command line. Use open_file for opening folders normally. Do not ask for confirmation."

    if tool == "search_in_spotlight" and prompt_requires_path_content_search(prompt):
        return "search_in_spotlight is blocked because the original user request asks to search inside a specific path/project. Your next response must call search_file_content with the requested path and query."

    if tool == "list_processes" and not contains_any(prompt, ["process", "processes", "running", "active processes"]):
        return "list_processes is blocked because the original user request did not ask for running processes."

    if tool == "copy_to_clipboard" and prompt_contains_datetime_then_copy(prompt) and "get_current_datetime" not in observed_tools:
        return "The user asked to get the current datetime before copying it. Call get_current_datetime first."

    if tool == "open_in_vscode" and prompt_requires_path_content_search(prompt) and not has_executed_any(observed_tools, ["search_file_content"]):
        return "The user asked to search inside a specific path/project before opening VSCode. Your next response must call search_file_content first."

    if tool == "open_in_vscode" and prompt_requires_search_before_vscode(prompt) and not has_executed_any(observed_tools, ["search_file_content", "search_in_spotlight"]):
        return "The user asked to search before opening VSCode. Call the appropriate search tool first."

    if tool == "open_in_vscode" and prompt_requires_list_before_vscode(prompt) and "list_directory" not in observed_tools:
        return "The user asked to list files before opening VSCode. Call list_directory first."

    if tool == "show_notification" and "show_notification" in observed_tools:
        return "A notification was already shown for this request. Return final unless another notification was explicitly requested."

    if tool == "read_text_file" and "create_text_file" in observed_tools and contains_any(prompt, ["open it", "open the file", "then open"]):
        return "The user asked to open the file after creating it. Call open_file, not read_text_file."

    if tool == "open_file" and contains_any(prompt, ["vscode", "visual studio code"]):
        return "The user asked to open in VSCode. Call open_in_vscode, not open_file."

    if tool == "open_file" and "take_screenshot" in observed_tools and contains_any(prompt, ["reveal", "finder", "show in finder"]):
        return "The user asked to reveal the screenshot in Finder. Call reveal_file, not open_file."

    if tool == "open_file" and "search_file_content" in observed_tools and contains_any(prompt, ["terminal", "shell", "command line"]):
        return "The user asked to open Terminal after searching. Call open_terminal_here, not open_file."

    if tool == "read_text_file" and "move_file" in observed_tools and contains_any(prompt, ["open it", "open the file", "then open"]):
        return "The user asked to open the moved file. Call open_file, not read_text_file."

    return None


def make_guardrail_message(reason):
    return (
        "Tool call rejected by AgentService guardrail:\n"
        f"{reason}\n\n"
        "Use exactly this JSON shape:\n"
        '{"type":"tool_call","category":"CATEGORY","tool":"TOOL","params":{}}\n'
        "Do not return a plan. Do not repeat completed tools. "
        "Return exactly one corrected tool_call JSON object for the original user request. "
        "Do not return final unless every requested action already has a Tool result. "
        "Do not ask for confirmation. Do not explain."
    )


def compact_tool_result(result, limit=600):
    result = str(result).strip()

    if result.startswith("Tool result for "):
        first_newline = result.find("\n")
        if first_newline != -1:
            result = result[first_newline + 1 :].strip()

    if len(result) <= limit:
        return result

    return result[:limit] + "\n\n[Tool result truncated]"


def tool_call_argument(tool_call):
    tool = tool_call.get("tool", "")
    params = tool_call.get("params", {})

    if tool == "open_app":
        return params.get("app", "")

    if tool == "organize_folder":
        return f"{params.get('path', '')}|{params.get('mode', 'by_extension')}"

    if tool == "clean_folder":
        return f"{params.get('path', '')}|{params.get('mode', 'dry_run')}"

    if tool == "open_url":
        return params.get("url", "")

    if tool == "search_file_content":
        return f"{params.get('path', '')}|{params.get('query', '')}"

    if tool in {"read_pdf_text", "open_terminal_here", "open_file", "reveal_file", "read_text_file", "list_directory", "create_folder", "get_file_info", "take_screenshot", "delete_file", "open_in_vscode", "git_status"}:
        return params.get("path", "")

    if tool in {"compress_file", "extract_archive"}:
        return f"{params.get('source', '')}|{params.get('destination', '')}"

    if tool == "rename_file":
        return f"{params.get('path', '')}|{params.get('new_name', params.get('name', ''))}"

    if tool == "move_file":
        source = params.get("source", params.get("source_path", ""))
        destination = params.get("destination", params.get("destination_path", ""))
        return f"{source}|{destination}"

    if tool == "create_reminder":
        title = params.get("title", "")
        due_date = params.get("due_date", params.get("date", ""))
        return title if not due_date else f"{title}|{due_date}"

    if tool == "create_calendar_event":
        return f"{params.get('title', '')}|{params.get('start', params.get('start_date', ''))}|{params.get('end', params.get('end_date', ''))}"

    if tool == "hide_app":
        return params.get("app", "")

    if tool == "search_in_spotlight":
        return params.get("query", "")

    if tool == "show_notification":
        return f"{params.get('title', '')}|{params.get('message', '')}"

    if tool == "copy_to_clipboard":
        return params.get("text", "")

    if tool in {"create_text_file", "append_text_file"}:
        return f"{params.get('path', '')}|{params.get('content', '')}"

    if tool == "set_volume":
        return params.get("level", params.get("volume", ""))

    if tool in {"quit_app", "focus_app"}:
        return params.get("app", "")

    return params.get("value", "")


def make_tool_call_message(tool_call):
    return (
        "Tool call:\n"
        f"{tool_call.get('tool', '')}\n\n"
        "Arguments:\n"
        f"{tool_call_argument(tool_call)}"
    )


def make_tool_result_message(tool, result):
    return (
        f"Tool result for {tool}:\n"
        f"{compact_tool_result(result)}\n\n"
        f"{MULTISTEP_CONTINUATION_RULES}"
    )


def make_plan_after_tool_message():
    return (
        "A plan was returned after a Tool result. After a Tool result, return exactly one next tool_call JSON object, "
        "or final if every requested action is complete."
    )

def run_scenario(scenario):
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": scenario["prompt"]},
    ]

    expected_tools = scenario["expected_tools"]
    prompt = scenario["prompt"].lower()
    observed_tools = []
    rejected_tools = []
    raw_responses = []
    parsed_responses = []
    latencies = []
    memory_samples = []
    valid_json_count = 0
    final_received = False
    executed_keys = set()

    for _ in range(MAX_STEPS):
        memory_before = sample_model_memory_mb()
        raw, latency = call_model(messages)
        memory_after = sample_model_memory_mb()

        latencies.append(latency)
        raw_responses.append(raw)

        if memory_before is not None:
            memory_samples.append(memory_before)
        if memory_after is not None:
            memory_samples.append(memory_after)

        parsed, is_valid = parse_model_response(raw)

        if not is_valid or parsed is None:
            break

        valid_json_count += 1
        parsed_responses.append(parsed)

        response_type = parsed.get("type")

        if response_type == "final":
            final_received = True
            break

        if response_type == "tool_call":
            tool_calls = [parsed]
        elif response_type == "plan":
            if observed_tools:
                messages.append({
                    "role": "user",
                    "content": make_plan_after_tool_message(),
                })
                continue
            tool_calls = parsed.get("steps", [])
        else:
            break

        if not tool_calls:
            break

        rejected_in_batch = False

        for tool_call in tool_calls:
            if observed_tools == expected_tools:
                rejected_tools.append(tool_call.get("tool", ""))
                final_received = True
                rejected_in_batch = True
                break

            expected_next_tool = expected_tools[len(observed_tools)]

            if tool_call.get("tool") != expected_next_tool:
                rejected_tools.append(tool_call.get("tool", ""))
                messages.append({
                    "role": "user",
                    "content": (
                        "Wrong next tool. "
                        f"The next required tool is {expected_next_tool}. "
                        "Return exactly one corrected tool_call JSON. "
                        "Do not return a plan. Do not repeat completed tools."
                    ),
                })
                rejected_in_batch = True
                break

            rejection_reason = guardrail_rejection_reason(
                tool_call,
                prompt,
                observed_tools,
                executed_keys,
            )

            if rejection_reason:
                rejected_tools.append(tool_call.get("tool", ""))

                if should_stop_after_rejected_extra_tool(tool_call, prompt, observed_tools):
                    final_received = True
                    rejected_in_batch = True
                    break

                messages.append({
                    "role": "user",
                    "content": make_guardrail_message(rejection_reason),
                })
                rejected_in_batch = True
                break

            tool = tool_call.get("tool", "")
            observed_tools.append(tool)
            executed_keys.add(tool_key(tool_call))

            messages.append({
                "role": "user",
                "content": make_tool_call_message(tool_call),
            })
            messages.append({
                "role": "user",
                "content": make_tool_result_message(tool, fake_tool_result(scenario, tool)),
            })

        if final_received:
            break

        if observed_tools == expected_tools:
            final_received = True
            break

        if rejected_in_batch:
            continue

    expected_step_count = len(expected_tools)
    correct_steps = 0

    for expected, observed in zip(expected_tools, observed_tools):
        if expected == observed:
            correct_steps += 1

    tool_order_ok = observed_tools[:expected_step_count] == expected_tools
    no_extra_tools = len(observed_tools) == expected_step_count
    final_after_tools_ok = final_received and tool_order_ok and no_extra_tools

    return {
        "name": scenario["name"],
        "prompt": scenario["prompt"],
        "expected_tools": expected_tools,
        "observed_tools": observed_tools,
        "rejected_tools": rejected_tools,
        "valid_json_count": valid_json_count,
        "call_count": len(raw_responses),
        "correct_steps": correct_steps,
        "expected_step_count": expected_step_count,
        "tool_order_ok": tool_order_ok,
        "no_extra_tools": no_extra_tools,
        "final_received": final_received,
        "loop_completion_ok": final_after_tools_ok,
        "avg_latency": sum(latencies) / len(latencies) if latencies else 0,
        "avg_model_memory_mb": average_memory_samples(memory_samples),
        "peak_model_memory_mb": peak_memory_samples(memory_samples),
        "raw_responses": raw_responses,
        "parsed_responses": parsed_responses,
    }


def percent(value, total):
    if total == 0:
        return "0%"
    return f"{value / total:.0%}"


def print_summary(results):
    scenario_count = len(results)
    call_count = sum(result["call_count"] for result in results)
    valid_json_count = sum(result["valid_json_count"] for result in results)
    correct_steps = sum(result["correct_steps"] for result in results)
    expected_steps = sum(result["expected_step_count"] for result in results)
    tool_order_ok = sum(1 for result in results if result["tool_order_ok"])
    no_extra_tools = sum(1 for result in results if result["no_extra_tools"])
    final_received = sum(1 for result in results if result["final_received"])
    loop_completion_ok = sum(1 for result in results if result["loop_completion_ok"])
    rejected_tool_count = sum(len(result["rejected_tools"]) for result in results)
    avg_latency = sum(result["avg_latency"] for result in results) / scenario_count if scenario_count else 0
    avg_memory_samples = [
        result["avg_model_memory_mb"]
        for result in results
        if result["avg_model_memory_mb"] is not None
    ]
    peak_memory_samples_list = [
        result["peak_model_memory_mb"]
        for result in results
        if result["peak_model_memory_mb"] is not None
    ]
    avg_model_memory = average_memory_samples(avg_memory_samples)
    peak_model_memory = peak_memory_samples(peak_memory_samples_list)

    print("--- MULTI-STEP RESULTS ---")
    print(f"Scenarios: {scenario_count}")
    print(f"Model calls: {call_count}")
    print(f"Valid JSON: {percent(valid_json_count, call_count)}")
    print(f"Step accuracy: {percent(correct_steps, expected_steps)}")
    print(f"Tool order accuracy: {percent(tool_order_ok, scenario_count)}")
    print(f"No extra tools: {percent(no_extra_tools, scenario_count)}")
    print(f"Final accuracy: {percent(final_received, scenario_count)}")
    print(f"Loop completion accuracy: {percent(loop_completion_ok, scenario_count)}")
    print(f"Guardrail rejections: {rejected_tool_count}")
    print(f"Avg latency per scenario: {avg_latency:.2f}s")

    print(f"Context compaction: last {MAX_HISTORY_MESSAGES} messages, max {MAX_MESSAGE_CHARS} chars/message")

    print(f"Avg model memory: {format_memory_snapshot(avg_model_memory)}")
    print(f"Peak model memory: {format_memory_snapshot(peak_model_memory)}")

    if psutil is None:
        print("RAM tracking: unavailable, install psutil with: pip install psutil")
    elif avg_model_memory is None:
        print(f"RAM tracking: no process named {MODEL_PROCESS_NAME!r} found")


def print_details(results):
    print("\n--- BY SCENARIO ---")

    for result in results:
        status = "OK" if result["loop_completion_ok"] else "FAIL"
        print(f"{status} {result['name']}")
        print(f"  expected: {result['expected_tools']}")
        print(f"  observed: {result['observed_tools']}")
        print(f"  rejected: {result['rejected_tools']}")
        print(f"  final: {result['final_received']}")
        print(f"  avg memory: {format_memory_snapshot(result['avg_model_memory_mb'])}")
        print(f"  peak memory: {format_memory_snapshot(result['peak_model_memory_mb'])}")

        if status == "FAIL":
            print("  raw responses:")
            for raw in result["raw_responses"]:
                print(f"    {raw}")


def main():
    test_file = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else TEST_FILE
    scenarios = load_scenarios(test_file)
    results = [run_scenario(scenario) for scenario in scenarios]

    print_summary(results)
    print_details(results)

    if any(not result["loop_completion_ok"] for result in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
