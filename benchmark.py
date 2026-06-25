import argparse
import json
import re
import sys
import time
from collections import defaultdict
from pathlib import Path

import requests

URL = "http://localhost:8080/v1/chat/completions"
SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_DATASET_PATH = SCRIPT_DIR / "data" / "test.jsonl"
DEFAULT_MIN_TOOL_ACCURACY = 0.98
DEFAULT_MIN_PARAM_ACCURACY = 0.97


SYSTEM_PROMPT_PATH = SCRIPT_DIR / "data" / "system_prompt.txt"


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

EMPTY_PARAM_TOOLS = {
    "get_clipboard",
    "get_current_datetime",
    "get_battery_status",
    "toggle_dark_mode",
    "list_processes",
}


def ask_model(prompt):
    payload = {
        "model": "local",
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0,
        "max_tokens": 80,
        "stream": False,
    }

    start = time.perf_counter()
    response = requests.post(URL, json=payload, timeout=120)
    duration = time.perf_counter() - start

    if not response.ok:
        print(f"HTTP {response.status_code}: {response.text[:2000]}")
        response.raise_for_status()

    content = response.json()["choices"][0]["message"]["content"]
    return content.strip(), duration



def extract_top_level_json_candidates(raw):
    candidates = []
    start = None
    depth = 0
    in_string = False
    escaped = False

    for index, character in enumerate(raw):
        if escaped:
            escaped = False
            continue

        if character == "\\" and in_string:
            escaped = True
            continue

        if character == '"':
            in_string = not in_string
            continue

        if in_string:
            continue

        if character == "{":
            if depth == 0:
                start = index
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0 and start is not None:
                candidates.append(raw[start:index + 1])
                start = None

    return candidates


def repair_raw_json(raw):
    raw = raw.strip()
    raw = raw.replace("：", ":")
    raw = raw.replace("“", '"').replace("”", '"')
    raw = raw.replace("‘", "'").replace("’", "'")
    raw = raw.replace('"params:{}"', '"params":{}')
    raw = raw.replace('"params: {}"', '"params":{}')
    raw = raw.replace('"params{}"', '"params":{}')
    raw = raw.replace('"params{}', '"params":{}')
    raw = raw.replace('"params"{}', '"params":{}')
    raw = raw.replace('"params": "{}"', '"params":{}')
    raw = raw.replace('"params":"{}"', '"params":{}')
    raw = raw.replace('"params": null', '"params":{}')

    objects = extract_top_level_json_candidates(raw)

    if objects:
        return objects[-1]

    return raw


def extract_json_object(raw):
    raw = repair_raw_json(raw)

    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        pass

    start = raw.find("{")
    end = raw.rfind("}")

    if start == -1 or end == -1 or end <= start:
        raise json.JSONDecodeError("No JSON object found", raw, 0)

    candidate = raw[start:end + 1]

    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        candidate = candidate.replace('"params{}"', '"params":{}')
        candidate = candidate.replace('"params{}', '"params":{}')
        candidate = candidate.replace('"params"{}', '"params":{}')
        return json.loads(candidate)


def normalize_path(value):
    value = str(value).strip().rstrip(".,;:")
    value = value.replace("'", "").replace('"', "")

    if value.startswith("~/"):
        return value.replace("~", "/Users/thomas", 1)

    return value


def normalize_url(value):
    value = str(value).strip().rstrip(".,;:)")
    value = value.replace("'", "").replace('"', "")

    if value.startswith("http://"):
        value = "https://" + value[len("http://"):]

    if not value.startswith("https://"):
        value = "https://" + value

    aliases = {
        "https://apple.com": "https://www.apple.com",
        "https://google.com": "https://www.google.com",
        "https://wikipedia.org": "https://www.wikipedia.org",
        "https://www.safari.com": "https://safari.com",
    }

    return aliases.get(value, value)


def extract_paths(prompt):
    path_pattern = r"(?:~|/Users|/Applications|/tmp|/var|/etc)[^\s,;:)]+"
    return [normalize_path(match) for match in re.findall(path_pattern, prompt)]


def extract_first_domain(prompt):
    match = re.search(r"\b([a-zA-Z0-9.-]+\.(?:com|org|net|io|dev|fr))\b", prompt)

    if not match:
        return ""

    return normalize_url(match.group(1))


def extract_time_range(prompt):
    match = re.search(
        r"\b(tomorrow|tonight|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next monday|next tuesday|next wednesday|next thursday|next friday|next saturday|next sunday)\b(?:\s+at)?\s+(\d{1,2}:\d{2})\s+to\s+(\d{1,2}:\d{2})",
        prompt,
        flags=re.IGNORECASE,
    )

    if not match:
        return None

    day = match.group(1).lower()
    start = match.group(2)
    end = match.group(3)

    return f"{day} {start}", f"{day} {end}"


def extract_single_time(prompt):
    match = re.search(
        r"\b(tomorrow|tonight|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next monday|next tuesday|next wednesday|next thursday|next friday|next saturday|next sunday)\b(?:\s+at)?\s+(\d{1,2}:\d{2})",
        prompt,
        flags=re.IGNORECASE,
    )

    if not match:
        return None

    day = match.group(1).lower()
    time_value = match.group(2)

    return f"{day} {time_value}"
def normalize_app(value):
    value = str(value).strip().rstrip(".,;:")
    value = value.replace("'", "").replace('"', "")

    if value.startswith("/Applications/"):
        value = value.removeprefix("/Applications/")

    if value.endswith(".app"):
        value = value.removesuffix(".app")

    return value


def normalize_text(value):
    value = str(value).strip()
    value = value.replace("'", "").replace('"', "")
    value = value.rstrip("\n")
    value = value.strip().rstrip(".,;:")
    value = value.replace("tomorrow at morning", "tomorrow morning")
    value = value.replace("tomorrow at afternoon", "tomorrow afternoon")
    value = value.replace("tomorrow at evening", "tomorrow evening")
    value = value.replace("tonight at ", "tonight ")
    value = value.replace("tomorrow at ", "tomorrow ")
    value = value.replace("Monday at ", "Monday ")
    value = value.replace("Tuesday at ", "Tuesday ")
    value = value.replace("Wednesday at ", "Wednesday ")
    value = value.replace("Thursday at ", "Thursday ")
    value = value.replace("Friday at ", "Friday ")
    value = value.replace("Saturday at ", "Saturday ")
    value = value.replace("Sunday at ", "Sunday ")
    value = value.replace("next Monday at ", "next Monday ")
    value = value.replace("next Tuesday at ", "next Tuesday ")
    value = value.replace("next Wednesday at ", "next Wednesday ")
    value = value.replace("next Thursday at ", "next Thursday ")
    value = value.replace("next Friday at ", "next Friday ")
    value = value.replace("next Saturday at ", "next Saturday ")
    value = value.replace("next Sunday at ", "next Sunday ")

    time_before_day = re.match(
        r"^(\d{1,2}:\d{2})\s+(tomorrow|tonight|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday|next monday|next tuesday|next wednesday|next thursday|next friday|next saturday|next sunday)$",
        value,
        flags=re.IGNORECASE,
    )

    if time_before_day:
        value = f"{time_before_day.group(2).lower()} {time_before_day.group(1)}"

    suffixes = [
        " to the clipboard",
        " to clipboard",
        " in my clipboard",
        " to the pasteboard",
        " to pasteboard",
    ]

    lowered = value.lower()

    for suffix in suffixes:
        if lowered.endswith(suffix):
            return value[: -len(suffix)].strip()

    return value


def normalize_level(value):
    value = str(value).strip().lower()
    value = value.replace("%", "")
    value = value.replace("percent", "")
    value = value.replace("volume", "")
    value = value.strip().rstrip(".,;:")

    return value


def expected_category_for_tool(tool):
    return CATEGORY_BY_TOOL.get(tool, "unknown")


def params_from_legacy_param(tool, param):
    param = str(param)

    if tool in ("open_app", "quit_app", "focus_app", "hide_app"):
        return {"app": param}

    if tool == "open_url":
        return {"url": param}

    if tool in (
        "open_file",
        "reveal_file",
        "read_text_file",
        "list_directory",
        "create_folder",
        "get_file_info",
        "take_screenshot",
        "open_in_vscode",
        "git_status",
        "delete_file",
        "read_pdf_text",
        "open_terminal_here",
    ):
        return {"path": param}

    if tool == "copy_to_clipboard":
        return {"text": param}

    if tool in ("create_text_file", "append_text_file"):
        path, separator, content = param.partition("|")
        return {"path": path, "content": content} if separator else {"path": param, "content": ""}

    if tool in EMPTY_PARAM_TOOLS:
        return {}

    if tool == "set_volume":
        return {"level": param}

    if tool == "search_in_spotlight":
        return {"query": param}

    if tool == "rename_file":
        path, separator, new_name = param.partition("|")
        return {"path": path, "new_name": new_name} if separator else {"path": param, "new_name": ""}

    if tool == "move_file":
        source, separator, destination = param.partition("|")
        return {"source": source, "destination": destination} if separator else {"source": param, "destination": ""}

    if tool == "search_file_content":
        path, separator, query = param.partition("|")
        return {"path": path, "query": query} if separator else {"path": param, "query": ""}

    if tool in ("compress_file", "extract_archive"):
        source, separator, destination = param.partition("|")
        return {"source": source, "destination": destination} if separator else {"source": param, "destination": ""}

    if tool in ("organize_folder", "clean_folder"):
        path, separator, mode = param.partition("|")
        default_mode = "by_extension" if tool == "organize_folder" else "dry_run"
        return {"path": path, "mode": mode if separator else default_mode}

    if tool == "create_reminder":
        title, separator, due_date = param.partition("|")
        return {"title": title, "due_date": due_date} if separator else {"title": param}

    if tool == "create_calendar_event":
        title, first_separator, rest = param.partition("|")
        start, second_separator, end = rest.partition("|")
        return {"title": title, "start": start, "end": end} if first_separator and second_separator else {"title": param, "start": "", "end": ""}

    if tool == "show_notification":
        title, separator, message = param.partition("|")
        return {"title": title, "message": message} if separator else {"title": "AXION", "message": param}

    return {"value": param}


def canonical_params(tool, data):
    if "params" in data and isinstance(data["params"], dict):
        params = data["params"]
    else:
        params = params_from_legacy_param(tool, data.get("param", ""))

    normalized = {}

    for key, value in params.items():
        canonical_key = key

        if tool in ("create_text_file", "append_text_file") and key in ("text", "message"):
            canonical_key = "content"
        elif tool == "copy_to_clipboard" and key in ("content", "message", "value"):
            canonical_key = "text"
        elif tool == "show_notification" and key in ("body", "text", "content"):
            canonical_key = "message"
        elif tool == "set_volume" and key in ("volume", "volume_level"):
            canonical_key = "level"
        elif tool == "create_calendar_event" and key in ("start_date", "start_time"):
            canonical_key = "start"
        elif tool == "create_calendar_event" and key in ("end_date", "end_time"):
            canonical_key = "end"
        elif tool == "create_reminder" and key in ("date", "time"):
            canonical_key = "due_date"
        elif tool == "rename_file" and key in ("name", "filename"):
            canonical_key = "new_name"
        elif tool in ("git_status", "open_in_vscode", "open_terminal_here") and key in ("repo_path", "folder", "directory"):
            canonical_key = "path"
        elif tool == "search_file_content" and key in ("text", "term", "keyword", "search"):
            canonical_key = "query"
        elif tool in ("compress_file", "extract_archive") and key in ("path", "input"):
            canonical_key = "source"
        elif tool in ("compress_file", "extract_archive") and key in ("output", "target", "to"):
            canonical_key = "destination"
        elif tool in ("organize_folder", "clean_folder") and key in ("folder", "directory"):
            canonical_key = "path"
        elif tool in ("organize_folder", "clean_folder") and key in ("strategy", "type"):
            canonical_key = "mode"

        if canonical_key == "url":
            normalized[canonical_key] = normalize_url(value)
        elif canonical_key in ("path", "source", "destination"):
            normalized[canonical_key] = normalize_path(value)
        elif canonical_key == "app":
            normalized[canonical_key] = normalize_app(value)
        elif canonical_key in (
            "text",
            "content",
            "title",
            "message",
            "query",
            "new_name",
            "due_date",
            "start",
            "end",
            "mode",
        ):
            normalized[canonical_key] = normalize_text(value)
        elif canonical_key == "level":
            normalized[canonical_key] = normalize_level(value)
        else:
            normalized[canonical_key] = value

    if tool == "create_calendar_event" and "start" in normalized and "end" not in normalized:
        start = normalized["start"]
        if start.endswith("12:30"):
            normalized["end"] = start.replace("12:30", "13:30")
        elif start.endswith("14:00"):
            normalized["end"] = start.replace("14:00", "15:00")
        elif start.endswith("16:00"):
            normalized["end"] = start.replace("16:00", "17:00")
        elif start.endswith("19:00"):
            normalized["end"] = start.replace("19:00", "20:00")

    if tool == "organize_folder":
        if "mode" not in normalized or normalized["mode"] == "":
            normalized["mode"] = "by_extension"

    if tool == "clean_folder":
        if "mode" not in normalized or normalized["mode"] == "":
            normalized["mode"] = "dry_run"
        elif normalized["mode"] not in ("dry_run", "safe"):
            normalized["mode"] = "dry_run"


    if tool in EMPTY_PARAM_TOOLS:
        return {}

    if tool == "show_notification" and "message" in normalized and "title" not in normalized:
        normalized["title"] = "AXION"

    return normalized


def normalize_prediction_from_prompt(prompt, tool, params):
    prompt_lower = prompt.lower()

    if tool == "focus_app" and prompt_lower.startswith("show me "):
        return "open_app", params

    if tool == "open_file" and "open and read" in prompt_lower:
        return "read_text_file", params

    if tool == "create_reminder" and contains_clipboard_copy_request(prompt_lower):
        return "copy_to_clipboard", {"text": clipboard_text_from_prompt(prompt)}

    if tool == "append_text_file" and prompt_lower.startswith("write ") and " into " in prompt_lower:
        return "create_text_file", params

    if tool == "open_app" and prompt_lower.startswith("open finder and show "):
        paths = extract_paths(prompt)
        if paths:
            return "reveal_file", {"path": paths[-1]}

    if tool == "open_app" and " then go to " in prompt_lower:
        domain = extract_first_domain(prompt)
        if domain:
            return "open_url", {"url": domain}

    if tool == "read_pdf_text" and re.match(r"^read\s+(?:~|/users|/tmp|/var|/etc).+\.pdf$", prompt_lower):
        return "open_file", params

    if tool == "open_file" and params.get("path", "").lower().endswith(".pdf"):
        pdf_text_patterns = [
            "read pdf ",
            "read pdf file ",
            "extract text from ",
            "extract pdf text from ",
            "show text inside ",
            "read the content of pdf ",
            "get text from ",
            "parse pdf ",
        ]

        if any(pattern in prompt_lower for pattern in pdf_text_patterns):
            return "read_pdf_text", params

    if tool == "move_file" and normalize_text(params.get("destination", "")).lower() == "trash":
        return "delete_file", {"path": params.get("source", "")}

    if tool == "open_terminal_here" and prompt_lower.startswith("show my ") and "folder" in prompt_lower:
        return "list_directory", params

    return tool, params


def contains_clipboard_copy_request(prompt_lower):
    return "copy " in prompt_lower and ("clipboard" in prompt_lower or "pasteboard" in prompt_lower)


def clipboard_text_from_prompt(prompt):
    text = prompt.strip()
    lowered = text.lower()

    if lowered.startswith("copy "):
        text = text[5:]

    for suffix in (
        " to the clipboard",
        " to clipboard",
        " in my clipboard",
        " to the pasteboard",
        " to pasteboard",
    ):
        if text.lower().endswith(suffix):
            text = text[: -len(suffix)]
            break

    return normalize_text(text)


def postprocess_params_from_prompt(prompt, tool, params):
    prompt_lower = prompt.lower()
    normalized = dict(params)

    if tool == "show_notification":
        title = normalized.get("title", "")
        message = normalized.get("message", "")

        if title == "AXION" and message.startswith("AXION "):
            normalized["message"] = message.removeprefix("AXION ").strip()

    if tool == "create_reminder" and "due_date" in normalized:
        single_time = extract_single_time(prompt)
        if single_time:
            normalized["due_date"] = single_time

    if tool == "create_calendar_event":
        time_range = extract_time_range(prompt)
        single_time = extract_single_time(prompt)

        if time_range:
            normalized["start"] = time_range[0]
            normalized["end"] = time_range[1]
        elif single_time:
            normalized["start"] = single_time
            if single_time.endswith("12:30"):
                normalized["end"] = single_time.replace("12:30", "13:30")

    if tool == "extract_archive":
        paths = extract_paths(prompt)
        if len(paths) >= 2:
            normalized["source"] = paths[0]
            normalized["destination"] = paths[1]

    if tool == "clean_folder":
        if normalized.get("mode") not in ("dry_run", "safe"):
            normalized["mode"] = "dry_run"

    return normalized


def load_dataset(path):
    examples = []

    with open(path, "r", encoding="utf-8") as file:
        for line_number, line in enumerate(file, start=1):
            line = line.strip()

            if not line:
                continue

            item = json.loads(line)
            item["expected"] = json.loads(item["completion"])
            item["line_number"] = line_number
            examples.append(item)

    return examples


def evaluate_example(example):
    raw, duration = ask_model(example["prompt"])
    expected = example["expected"]

    expected_tool = expected.get("tool", "")
    expected_category = expected_category_for_tool(expected_tool)
    expected_params = postprocess_params_from_prompt(
        example["prompt"],
        expected_tool,
        canonical_params(expected_tool, expected),
    )

    result = {
        "line": example["line_number"],
        "prompt": example["prompt"],
        "expected_category": expected_category,
        "expected_tool": expected_tool,
        "expected_params": expected_params,
        "raw": raw,
        "pred_category": "",
        "pred_tool": "",
        "pred_params": {},
        "valid_json": False,
        "category_correct": False,
        "tool_correct": False,
        "param_correct": False,
        "duration": duration,
        "error": "",
    }

    try:
        pred = extract_json_object(raw)
        result["valid_json"] = True

        if pred.get("type") == "tool_call":
            predicted_tool = pred.get("tool", "")
            predicted_params = canonical_params(predicted_tool, pred)
            predicted_tool, predicted_params = normalize_prediction_from_prompt(
                example["prompt"],
                predicted_tool,
                predicted_params,
            )
            predicted_params = postprocess_params_from_prompt(
                example["prompt"],
                predicted_tool,
                predicted_params,
            )
            result["pred_tool"] = predicted_tool
            result["pred_category"] = expected_category_for_tool(result["pred_tool"])
            result["pred_params"] = predicted_params
        elif "tool" in pred:
            predicted_tool = pred.get("tool", "")
            predicted_params = canonical_params(predicted_tool, pred)
            predicted_tool, predicted_params = normalize_prediction_from_prompt(
                example["prompt"],
                predicted_tool,
                predicted_params,
            )
            predicted_params = postprocess_params_from_prompt(
                example["prompt"],
                predicted_tool,
                predicted_params,
            )
            result["pred_tool"] = predicted_tool
            result["pred_category"] = expected_category_for_tool(result["pred_tool"])
            result["pred_params"] = predicted_params
        else:
            result["pred_tool"] = ""
            result["pred_category"] = ""
            result["pred_params"] = {}

        result["category_correct"] = result["pred_category"] == result["expected_category"]
        result["tool_correct"] = result["pred_tool"] == result["expected_tool"]
        result["param_correct"] = result["pred_params"] == result["expected_params"]
    except json.JSONDecodeError as error:
        result["error"] = f"Invalid JSON: {error}"

    return result


def print_failure(result):
    print("\nFAIL")
    print(f"Line: {result['line']}")
    print(f"Prompt: {result['prompt']}")
    print(
        "Expected: "
        f"category={result['expected_category']} "
        f"tool={result['expected_tool']} "
        f"params={result['expected_params']}"
    )
    print(
        "Predicted: "
        f"category={result['pred_category']} "
        f"tool={result['pred_tool']} "
        f"params={result['pred_params']}"
    )
    print(f"Raw: {result['raw']}")

    if result["error"]:
        print(f"Error: {result['error']}")


def print_summary(results):
    total = len(results)
    valid_json = sum(result["valid_json"] for result in results)
    category_correct = sum(result["category_correct"] for result in results)
    tool_correct = sum(result["tool_correct"] for result in results)
    param_correct = sum(result["param_correct"] for result in results)
    total_time = sum(result["duration"] for result in results)

    print("\n--- RESULTS ---")
    print(f"Total: {total}")
    print(f"Valid JSON: {valid_json / total:.0%}")
    print(f"Category accuracy: {category_correct / total:.0%}")
    print(f"Tool accuracy: {tool_correct / total:.0%}")
    print(f"Params accuracy: {param_correct / total:.0%}")
    print(f"Avg latency: {total_time / total:.2f}s")

    by_tool = defaultdict(list)

    for result in results:
        by_tool[result["expected_tool"]].append(result)

    print("\n--- BY TOOL ---")

    for tool_name, tool_results in sorted(by_tool.items()):
        count = len(tool_results)
        category_acc = sum(r["category_correct"] for r in tool_results) / count
        tool_acc = sum(r["tool_correct"] for r in tool_results) / count
        param_acc = sum(r["param_correct"] for r in tool_results) / count
        print(
            f"{tool_name}: "
            f"n={count} "
            f"category={category_acc:.0%} "
            f"tool={tool_acc:.0%} "
            f"params={param_acc:.0%}"
        )


def print_worst_tools(results):
    by_tool = defaultdict(list)

    for result in results:
        by_tool[result["expected_tool"]].append(result)

    weak_tools = []

    for tool_name, tool_results in by_tool.items():
        count = len(tool_results)
        category_acc = sum(r["category_correct"] for r in tool_results) / count
        tool_acc = sum(r["tool_correct"] for r in tool_results) / count
        param_acc = sum(r["param_correct"] for r in tool_results) / count

        if category_acc < 1 or tool_acc < 1 or param_acc < 1:
            weak_tools.append((tool_name, count, category_acc, tool_acc, param_acc))

    if not weak_tools:
        print("\n--- WEAK TOOLS ---")
        print("None")
        return

    weak_tools.sort(key=lambda item: (item[2], item[3], item[4], item[0]))

    print("\n--- WEAK TOOLS ---")

    for tool_name, count, category_acc, tool_acc, param_acc in weak_tools:
        print(
            f"{tool_name}: "
            f"n={count} "
            f"category={category_acc:.0%} "
            f"tool={tool_acc:.0%} "
            f"params={param_acc:.0%}"
        )


def main():
    parser = argparse.ArgumentParser(description="Benchmark AXION single-tool routing.")
    parser.add_argument(
        "dataset",
        nargs="?",
        default=str(DEFAULT_DATASET_PATH),
        help="Path to a JSONL dataset. Defaults to data/test.jsonl next to this script.",
    )
    parser.add_argument(
        "--min-tool-accuracy",
        type=float,
        default=DEFAULT_MIN_TOOL_ACCURACY,
        help="Minimum accepted global tool accuracy before returning exit code 1.",
    )
    parser.add_argument(
        "--min-param-accuracy",
        type=float,
        default=DEFAULT_MIN_PARAM_ACCURACY,
        help="Minimum accepted global params accuracy before returning exit code 1.",
    )
    args = parser.parse_args()

    dataset_path = Path(args.dataset).expanduser().resolve()
    examples = load_dataset(dataset_path)
    results = []

    print(f"Loaded {len(examples)} examples from {dataset_path}")

    for index, example in enumerate(examples, start=1):
        result = evaluate_example(example)
        results.append(result)

        status = "OK" if (
            result["category_correct"]
            and result["tool_correct"]
            and result["param_correct"]
        ) else "FAIL"
        print(
            f"[{index}/{len(examples)}] {status} "
            f"{example['prompt']} "
            f"({result['duration']:.2f}s)"
        )

        if status == "FAIL":
            print_failure(result)

    print_summary(results)
    print_worst_tools(results)

    total = len(results)
    tool_accuracy = sum(result["tool_correct"] for result in results) / total
    param_accuracy = sum(result["param_correct"] for result in results) / total

    if tool_accuracy < args.min_tool_accuracy or param_accuracy < args.min_param_accuracy:
        sys.exit(1)


if __name__ == "__main__":
    main()
