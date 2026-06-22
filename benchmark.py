import json
import time
from collections import defaultdict

import requests

URL = "http://localhost:8080/v1/chat/completions"
DATASET_PATH = "data/test.jsonl"

SYSTEM_PROMPT = """
You are AXION, a concise local macOS assistant.

If no tool is needed, answer normally and briefly.

If a tool is needed, answer ONLY with valid compact JSON.
No markdown. No explanation. No extra text.

Tool format:
{"tool":"TOOL_NAME","params":{"KEY":"VALUE"}}

Available tools:
- open_app: opens a known macOS application
- open_url: opens a website URL
- open_file: opens a local file or application path
- reveal_file: reveals a local file in Finder
- read_text_file: reads the content of a local text/code file
- copy_to_clipboard: copies text to the macOS clipboard
- create_text_file: creates or overwrites a local text file
- append_text_file: appends text to a local text file
- get_current_datetime: returns the current local date and time

Priority rules:
1. If the user asks to open a known macOS application, use open_app.
2. Never use open_url for known app names.
3. Known apps: Safari, Xcode, Terminal, Finder, Firefox, Chrome, Calculator, Notes.
4. Use open_url only for domains, websites, or explicit URLs.
5. Use open_file only for absolute local paths starting with / or ~ when the user wants to open the file.
6. Use reveal_file when the user asks to show, locate, reveal, or find a file in Finder.
7. Use read_text_file only for readable text/code files such as .txt, .md, .json, .csv, .log, .swift, .cpp, .hpp, .h, .c, .py.
Use read_text_file for read, inspect, view content, show content, analyze content when the path is a text/code file.
8. For binary files such as .pdf or .png, do not use read_text_file. Use open_file or reveal_file depending on the request.
9. Use create_text_file for "write X into FILE" unless the user says add or append.
10. Use append_text_file when the user asks to add or append text to an existing file.
11. Use copy_to_clipboard when the user asks to copy text to the clipboard or pasteboard.
12. Use get_current_datetime when the user asks for the current date, time, datetime, or timestamp.

For create_text_file and append_text_file, preserve the requested content exactly.
Do not rewrite, reformat, split lines, translate, summarize, capitalize, or add punctuation.
If the user says copy followed by a path, copy the path as text unless they explicitly ask to copy the file object.
For copy_to_clipboard, exclude command words such as "copy", "to clipboard", "to the clipboard", and "to the pasteboard" from the copied text.
If the user says "show me Finder" without a file path, use open_app with Finder.
Use reveal_file only when a file path is provided.
If the parameter starts with / or ~, always preserve it as a path.
Even if it ends with .app, use open_file, not open_app.

Parameter schemas:
- open_app: {"app":"Safari"}
- open_url: {"url":"https://github.com"}
- open_file: {"path":"/Users/thomas/Desktop/test.png"}
- reveal_file: {"path":"/Users/thomas/Desktop/test.png"}
- read_text_file: {"path":"/Users/thomas/Desktop/notes.txt"}
- copy_to_clipboard: {"text":"hello AXON"}
- create_text_file: {"path":"/Users/thomas/Desktop/note.txt","content":"hello AXON"}
- append_text_file: {"path":"/Users/thomas/Desktop/note.txt","content":"second line"}
- get_current_datetime: {}

Examples:
User: open Safari
Assistant: {"tool":"open_app","params":{"app":"Safari"}}

User: open github.com
Assistant: {"tool":"open_url","params":{"url":"https://github.com"}}

User: open /Users/thomas/Desktop/test.png
Assistant: {"tool":"open_file","params":{"path":"/Users/thomas/Desktop/test.png"}}

User: reveal /Users/thomas/Desktop/test.png in Finder
Assistant: {"tool":"reveal_file","params":{"path":"/Users/thomas/Desktop/test.png"}}

User: read /Users/thomas/Desktop/notes.txt
Assistant: {"tool":"read_text_file","params":{"path":"/Users/thomas/Desktop/notes.txt"}}

User: copy hello AXON to the clipboard
Assistant: {"tool":"copy_to_clipboard","params":{"text":"hello AXON"}}

User: create /Users/thomas/Desktop/note.txt with hello AXON
Assistant: {"tool":"create_text_file","params":{"path":"/Users/thomas/Desktop/note.txt","content":"hello AXON"}}

User: append second line to /Users/thomas/Desktop/note.txt
Assistant: {"tool":"append_text_file","params":{"path":"/Users/thomas/Desktop/note.txt","content":"second line"}}

User: what time is it
Assistant: {"tool":"get_current_datetime","params":{}}

Never claim that an action was done yourself.
Only tools may report action results.
"""


def ask_model(prompt):
    payload = {
        "model": "local",
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0,
        "max_tokens": 120,
        "stream": False,
    }

    start = time.perf_counter()
    response = requests.post(URL, json=payload, timeout=120)
    duration = time.perf_counter() - start

    response.raise_for_status()

    content = response.json()["choices"][0]["message"]["content"]
    return content.strip(), duration


def extract_json_object(raw):
    raw = raw.strip()

    start = raw.find("{")
    end = raw.rfind("}")

    if start == -1 or end == -1 or end <= start:
        raise json.JSONDecodeError("No JSON object found", raw, 0)

    return json.loads(raw[start:end + 1])


def normalize_param(value):
    value = str(value).strip().rstrip(".,;:")
    value = value.replace("'", "").replace('"', "")

    if value.startswith("~/"):
        value = value.replace("~", "/Users/thomas", 1)

    if value.startswith("/"):
        return value

    if value.startswith("http://"):
        value = "https://" + value[len("http://"):]

    if (
        not value.startswith("https://")
        and "." in value
        and "|" not in value
    ):
        value = "https://" + value

    common_url_aliases = {
        "https://apple.com": "https://www.apple.com",
        "https://google.com": "https://www.google.com",
        "https://wikipedia.org": "https://www.wikipedia.org",
    }

    return common_url_aliases.get(value, value)


def canonical_params(tool, data):
    if "params" in data and isinstance(data["params"], dict):
        params = data["params"]
    else:
        params = params_from_legacy_param(tool, data.get("param", ""))

    normalized = {}

    for key, value in params.items():
        if key in ("url", "path", "app", "text", "content"):
            normalized[key] = normalize_param(value)
        else:
            normalized[key] = value

    return normalized


def params_from_legacy_param(tool, param):
    param = str(param)

    if tool == "open_app":
        return {"app": param}

    if tool == "open_url":
        return {"url": param}

    if tool in ("open_file", "reveal_file", "read_text_file"):
        return {"path": param}

    if tool == "copy_to_clipboard":
        return {"text": param}

    if tool in ("create_text_file", "append_text_file"):
        path, separator, content = param.partition("|")

        if not separator:
            return {"path": param, "content": ""}

        return {"path": path, "content": content}

    if tool == "get_current_datetime":
        return {}

    return {"value": param}


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
    expected_params = canonical_params(expected_tool, expected)

    result = {
        "line": example["line_number"],
        "prompt": example["prompt"],
        "expected_tool": expected_tool,
        "expected_params": expected_params,
        "raw": raw,
        "pred_tool": "",
        "pred_params": {},
        "valid_json": False,
        "tool_correct": False,
        "param_correct": False,
        "duration": duration,
        "error": "",
    }

    try:
        pred = extract_json_object(raw)
        result["valid_json"] = True
        result["pred_tool"] = pred.get("tool", "")
        result["pred_params"] = canonical_params(result["pred_tool"], pred)
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
        f"tool={result['expected_tool']} "
        f"params={result['expected_params']}"
    )
    print(
        "Predicted: "
        f"tool={result['pred_tool']} "
        f"params={result['pred_params']}"
    )
    print(f"Raw: {result['raw']}")

    if result["error"]:
        print(f"Error: {result['error']}")


def print_summary(results):
    total = len(results)
    valid_json = sum(result["valid_json"] for result in results)
    tool_correct = sum(result["tool_correct"] for result in results)
    param_correct = sum(result["param_correct"] for result in results)
    total_time = sum(result["duration"] for result in results)

    print("\n--- RESULTS ---")
    print(f"Total: {total}")
    print(f"Valid JSON: {valid_json / total:.0%}")
    print(f"Tool accuracy: {tool_correct / total:.0%}")
    print(f"Params accuracy: {param_correct / total:.0%}")
    print(f"Avg latency: {total_time / total:.2f}s")

    by_tool = defaultdict(list)

    for result in results:
        by_tool[result["expected_tool"]].append(result)

    print("\n--- BY TOOL ---")

    for tool_name, tool_results in sorted(by_tool.items()):
        count = len(tool_results)
        tool_acc = sum(r["tool_correct"] for r in tool_results) / count
        param_acc = sum(r["param_correct"] for r in tool_results) / count
        print(
            f"{tool_name}: "
            f"n={count} "
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

        status = "OK" if result["tool_correct"] and result["param_correct"] else "FAIL"
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
