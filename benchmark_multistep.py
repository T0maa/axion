#!/usr/bin/env python3

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

SERVER_URL = "http://localhost:8080/v1/chat/completions"
SCRIPT_DIR = Path(__file__).resolve().parent
TEST_FILE = SCRIPT_DIR / "data/test_multi_step.jsonl"
SYSTEM_PROMPT_PATH = SCRIPT_DIR / "data/system_prompt.txt"
MAX_STEPS = 7
MAX_TOKENS = 160

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


def call_model(messages):
    body = {
        "model": "local",
        "messages": messages,
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
    category = str(category or "")
    category = CATEGORY_ALIASES.get(category, category)

    if category in VALID_CATEGORIES:
        return category

    return CATEGORY_BY_TOOL.get(tool, category)


def normalize_parsed_response(parsed):
    if not isinstance(parsed, dict):
        return None

    response_type = parsed.get("type")

    if response_type == "final":
        return {
            "type": "final",
            "content": str(parsed.get("content", "")),
        }

    if response_type == "tool_call" or "tool" in parsed:
        tool = str(parsed.get("tool", ""))

        return {
            "type": "tool_call",
            "category": normalize_category(parsed.get("category", ""), tool),
            "tool": tool,
            "params": normalize_params(parsed.get("params", {})),
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
    return (
        f"Tool result for {tool}:\n"
        "Done.\n\n"
        "Continue with the next unfinished action from the original user request. "
        "If all requested actions are complete, return final. "
        "Do not repeat successful tools. Do not invent extra actions."
    )


def fake_tool_result(scenario, tool):
    fake_results = scenario.get("fake_results", {})
    result = fake_results.get(tool, make_default_fake_result(tool))

    if "Do not repeat successful tools" not in result:
        result += " Do not repeat successful tools. Do not invent extra actions."

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


def has_executed_any(observed_tools, tool_names):
    return any(tool in observed_tools for tool in tool_names)


def tool_key(parsed):
    params = parsed.get("params", {})
    params_text = json.dumps(params, sort_keys=True, separators=(",", ":"))
    return f"{parsed.get('tool', '')}|{params_text}"


def guardrail_rejection_reason(parsed, prompt, observed_tools, executed_keys):
    tool = parsed.get("tool", "")
    params = parsed.get("params", {})
    params_text = json.dumps(params, ensure_ascii=False).lower()

    if tool_key(parsed) in executed_keys:
        return f"The tool {tool} with the same arguments already succeeded. Do not repeat it."

    if tool == "delete_file" and not user_requested_delete(prompt):
        return "delete_file is blocked because the original user request did not explicitly ask to delete, remove, trash, or move something to Trash."

    if tool == "move_file" and "trash" in params_text:
        return "Moving to Trash must use delete_file, not move_file."

    if tool == "clean_folder" and "safe" in params_text and not user_requested_safe_clean(prompt):
        return "clean_folder safe mode is blocked because the original user request did not explicitly ask for safe cleaning or moving clean candidates. Use dry_run or return final."

    if tool == "open_terminal_here" and not contains_any(prompt, ["terminal", "shell", "command line"]):
        path = params.get("path", "")
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

    return None


def make_guardrail_message(reason):
    return (
        "Tool call rejected by benchmark guardrail:\n"
        f"{reason}\n\n"
        "Return exactly one corrected tool_call JSON object for the original user request. "
        "Do not return final unless every requested action already has a Tool result. "
        "Do not ask for confirmation. Do not explain."
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
    valid_json_count = 0
    final_received = False
    executed_keys = set()

    for _ in range(MAX_STEPS):
        raw, latency = call_model(messages)
        latencies.append(latency)
        raw_responses.append(raw)

        parsed, is_valid = parse_model_response(raw)

        if not is_valid or parsed is None:
            break

        valid_json_count += 1
        parsed_responses.append(parsed)

        messages.append({
            "role": "assistant",
            "content": json.dumps(parsed, ensure_ascii=False, separators=(",", ":")),
        })

        response_type = parsed.get("type")

        if response_type == "final":
            final_received = True
            break

        if response_type != "tool_call":
            break

        if observed_tools == expected_tools:
            rejected_tools.append(parsed.get("tool", ""))
            final_received = True
            break

        rejection_reason = guardrail_rejection_reason(parsed, prompt, observed_tools, executed_keys)

        if rejection_reason:
            rejected_tools.append(parsed.get("tool", ""))
            messages.append({
                "role": "user",
                "content": make_guardrail_message(rejection_reason),
            })
            continue

        tool = parsed.get("tool", "")
        observed_tools.append(tool)
        executed_keys.add(tool_key(parsed))

        messages.append({
            "role": "user",
            "content": fake_tool_result(scenario, tool),
        })

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


def print_details(results):
    print("\n--- BY SCENARIO ---")

    for result in results:
        status = "OK" if result["loop_completion_ok"] else "FAIL"
        print(f"{status} {result['name']}")
        print(f"  expected: {result['expected_tools']}")
        print(f"  observed: {result['observed_tools']}")
        print(f"  rejected: {result['rejected_tools']}")
        print(f"  final: {result['final_received']}")

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
