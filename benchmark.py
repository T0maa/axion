import json
import time
from collections import defaultdict

import requests

URL = "http://localhost:8080/v1/chat/completions"
DATASET_PATH = "data/test.jsonl"

SYSTEM_PROMPT = """
Return exactly ONE valid compact JSON object. No markdown. No prose.
Always use this shape: {"category":"...","tool":"...","params":{...}}
Never output multiple JSON objects. Never output params{}.

Tool categories:
files: open_file, reveal_file, read_text_file, create_text_file, append_text_file, list_directory, create_folder, get_file_info, rename_file, move_file, delete_file, search_file_content, read_pdf_text, compress_file, extract_archive
web_apps: open_app, open_url, quit_app, focus_app, hide_app
text: copy_to_clipboard, get_clipboard, get_current_datetime, search_in_spotlight
system: show_notification, take_screenshot, set_volume, get_battery_status, toggle_dark_mode
dev: list_processes, open_in_vscode, git_status, open_terminal_here
third_party: create_reminder, create_calendar_event

Rules:
- Apps open/launch/start/show => open_app. App quit/close/stop/terminate => quit_app. App focus/bring/switch => focus_app. App hide/minimize => hide_app.
- Website/domain/url => open_url.
- If prompt contains a local file path (/Users/... or ~/...) and asks open, use open_file with path. Never use open_app with Preview/TextEdit for a file path. /Applications/Name.app is the only path that uses open_app.
- Reveal/show/locate/find path in Finder => reveal_file. If prompt says open Finder and show/reveal a path, choose reveal_file, not open_app.
- Read/show/inspect/open and read text/code file content => read_text_file. Binary files like pdf/png/jpg/zip => open_file, not read_text_file.
- Folder contents/list/inside/display contents/show contents => list_directory. A path without file extension is usually a folder. Folder create/make/add => create_folder. File info/metadata/size/type/modified => get_file_info.
- Create/write file with content => create_text_file with params path,content. Append/add text => append_text_file with params path,content. Preserve text exactly.
- Copy to clipboard/pasteboard => copy_to_clipboard with params text. The copied text is before "to clipboard/pasteboard". Clipboard content => get_clipboard. Date/time/timestamp => get_current_datetime.
- Notification/alert => show_notification with title,message. If title missing, title is AXION.
- Screenshot => take_screenshot. Volume N => set_volume with level. Battery/charging/power => get_battery_status. Toggle appearance => toggle_dark_mode.
- Processes => list_processes. VSCode => open_in_vscode. Git status/changes => git_status. Terminal in folder/open shell here => open_terminal_here. Spotlight/mdfind/search macOS files => search_in_spotlight.
- Rename file => rename_file with path,new_name. Move file from path to path => move_file with source,destination. Delete/remove/trash/move to Trash => delete_file with path. Destination "Trash" means delete_file, not move_file.
- Search text inside file/folder => search_file_content with path,query. Read/extract PDF text => read_pdf_text with path. Zip/compress/archive => compress_file with source,destination. Unzip/extract archive => extract_archive with source,destination.
- Reminder => create_reminder with title,due_date optional. Keep date wording from the prompt, e.g. "tomorrow morning", not "tomorrow at morning".
- Calendar event => create_calendar_event with title,start,end. Preserve date wording from the prompt. Use "tomorrow 14:00", not "tomorrow at 14:00", unless prompt says "at". If no end, end=start+1h.

Examples:
open Xcode => {"category":"web_apps","tool":"open_app","params":{"app":"Xcode"}}
show me Finder => {"category":"web_apps","tool":"open_app","params":{"app":"Finder"}}
open /Users/thomas/Desktop/test.pdf => {"category":"files","tool":"open_file","params":{"path":"/Users/thomas/Desktop/test.pdf"}}
open and read /Users/thomas/Desktop/notes.txt => {"category":"files","tool":"read_text_file","params":{"path":"/Users/thomas/Desktop/notes.txt"}}
open Safari then go to github.com => {"category":"web_apps","tool":"open_url","params":{"url":"https://github.com"}}
open Finder and show /Users/thomas/Desktop/test.png => {"category":"files","tool":"reveal_file","params":{"path":"/Users/thomas/Desktop/test.png"}}
copy hello AXON to clipboard => {"category":"text","tool":"copy_to_clipboard","params":{"text":"hello AXON"}}
what time is it => {"category":"text","tool":"get_current_datetime","params":{}}
append second line to /Users/thomas/Desktop/a.txt => {"category":"files","tool":"append_text_file","params":{"path":"/Users/thomas/Desktop/a.txt","content":"second line"}}
write project status ready into ~/Desktop/status.txt => {"category":"files","tool":"create_text_file","params":{"path":"~/Desktop/status.txt","content":"project status ready"}}
create /Users/thomas/Desktop/shopping.txt with eggs and bread => {"category":"files","tool":"create_text_file","params":{"path":"/Users/thomas/Desktop/shopping.txt","content":"eggs and bread"}}
add another note to ~/Desktop/quick-note.md => {"category":"files","tool":"append_text_file","params":{"path":"~/Desktop/quick-note.md","content":"another note"}}
show contents of /Users/thomas/Desktop => {"category":"files","tool":"list_directory","params":{"path":"/Users/thomas/Desktop"}}
set volume to 40 => {"category":"system","tool":"set_volume","params":{"level":"40"}}
list running processes => {"category":"dev","tool":"list_processes","params":{}}
search Spotlight for benchmark.py => {"category":"text","tool":"search_in_spotlight","params":{"query":"benchmark.py"}}
check repository status for ~/Projects/AXION => {"category":"dev","tool":"git_status","params":{"path":"~/Projects/AXION"}}
move /Users/thomas/Desktop/old.txt to Trash => {"category":"files","tool":"delete_file","params":{"path":"/Users/thomas/Desktop/old.txt"}}
search ToolRegistry in /Users/thomas/Projects/AXION => {"category":"files","tool":"search_file_content","params":{"path":"/Users/thomas/Projects/AXION","query":"ToolRegistry"}}
read pdf /Users/thomas/Desktop/test.pdf => {"category":"files","tool":"read_pdf_text","params":{"path":"/Users/thomas/Desktop/test.pdf"}}
zip /Users/thomas/Desktop/AXIONZipTest to /Users/thomas/Desktop/AXIONZipTest.zip => {"category":"files","tool":"compress_file","params":{"source":"/Users/thomas/Desktop/AXIONZipTest","destination":"/Users/thomas/Desktop/AXIONZipTest.zip"}}
unzip /Users/thomas/Desktop/AXIONZipTest.zip to /Users/thomas/Desktop/AXIONExtracted => {"category":"files","tool":"extract_archive","params":{"source":"/Users/thomas/Desktop/AXIONZipTest.zip","destination":"/Users/thomas/Desktop/AXIONExtracted"}}
open terminal in /Users/thomas/Projects/AXION => {"category":"dev","tool":"open_terminal_here","params":{"path":"/Users/thomas/Projects/AXION"}}
rename /Users/thomas/Desktop/old.txt to new.txt => {"category":"files","tool":"rename_file","params":{"path":"/Users/thomas/Desktop/old.txt","new_name":"new.txt"}}
remind me to buy milk tomorrow at 18:00 => {"category":"third_party","tool":"create_reminder","params":{"title":"buy milk","due_date":"tomorrow at 18:00"}}
create reminder call the bank tomorrow morning => {"category":"third_party","tool":"create_reminder","params":{"title":"call the bank","due_date":"tomorrow morning"}}
create calendar event Meeting tomorrow 14:00 to 15:00 => {"category":"third_party","tool":"create_calendar_event","params":{"title":"Meeting","start":"tomorrow 14:00","end":"tomorrow 15:00"}}
create calendar event Lunch tomorrow at 12:30 => {"category":"third_party","tool":"create_calendar_event","params":{"title":"Lunch","start":"tomorrow at 12:30","end":"tomorrow at 13:30"}}
"""


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
    raw = raw.replace('"params{}"', '"params":{}')
    raw = raw.replace('"params{}', '"params":{}')
    raw = raw.replace('"params"{}', '"params":{}')
    raw = raw.replace('"params": "{}"', '"params":{}')
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
    value = str(value).strip().rstrip(".,;:")
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

    if tool in EMPTY_PARAM_TOOLS:
        return {}

    if tool == "show_notification" and "message" in normalized and "title" not in normalized:
        normalized["title"] = "AXION"

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
    expected_params = canonical_params(expected_tool, expected)

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
        result["pred_tool"] = pred.get("tool", "")
        result["pred_category"] = expected_category_for_tool(result["pred_tool"])
        result["pred_params"] = canonical_params(result["pred_tool"], pred)
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


def main():
    examples = load_dataset(DATASET_PATH)
    results = []

    print(f"Loaded {len(examples)} examples")

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


if __name__ == "__main__":
    main()
