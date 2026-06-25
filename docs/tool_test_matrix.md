# AXION — Manual Tool Test Matrix

Goal: manually validate tool routing, real tool execution, confirmations, UI result cards, debug mode, and guardrails.

Test rules:

- Start AXION with `llama-server` ready.
- Keep `Debug OFF` to validate the normal UI.
- Switch `Debug ON` only when a test fails.
- After each file-related test, verify the result in Finder or Terminal.
- Mark each test as `OK`, `FAILED`, or `Review`.
- Clean up all test files at the end.

## Legend

| Status | Meaning |
|---|---|
| TODO | Not tested yet |
| OK | Works as expected |
| FAILED | Wrong tool, wrong action, or execution error |
| Review | Partially works or behavior is ambiguous |

---

# 1. Files — safe actions

## 1.1 create_folder

| Field | Value |
|---|---|
| Prompt | `create a folder named axion_test_folder in my Desktop folder` |
| Expected tool | `create_folder` |
| Confirmation | No |
| Expected result | Folder created: `~/Desktop/axion_test_folder` |
| Expected UI | `Folder created` card with the full path |
| Status | OK |

## 1.2 create_text_file

| Field | Value |
|---|---|
| Prompt | `create a file named axion_note.txt on my Desktop with the text hello axion` |
| Expected tool | `create_text_file` |
| Confirmation | No |
| Expected result | File created: `~/Desktop/axion_note.txt` containing `hello axion` |
| Expected UI | `Text file created` card |
| Status | OK |

## 1.3 append_text_file

| Field | Value |
|---|---|
| Prompt | `append the text second line to axion_note.txt on my Desktop` |
| Expected tool | `append_text_file` |
| Confirmation | No |
| Expected result | Text appended to `~/Desktop/axion_note.txt` |
| Expected UI | `Text appended` card |
| Status | OK |

## 1.4 read_text_file

| Field | Value |
|---|---|
| Prompt | `read axion_note.txt on my Desktop` |
| Expected tool | `read_text_file` |
| Confirmation | No |
| Expected result | File content is displayed |
| Expected UI | Readable card or message with the file content |
| Status | REVIEW |

## 1.5 list_directory

| Field | Value |
|---|---|
| Prompt | `show me what is inside my Desktop folder` |
| Expected tool | `list_directory` |
| Confirmation | No |
| Expected result | Desktop items are listed |
| Expected UI | Readable card or message with files and folders |
| Status | REVIEW |

## 1.6 get_file_info

| Field | Value |
|---|---|
| Prompt | `get information about axion_note.txt on my Desktop` |
| Expected tool | `get_file_info` |
| Confirmation | No |
| Expected result | File metadata is shown: path, size, dates if available |
| Expected UI | `File info` card or equivalent |
| Status | REVIEW |

## 1.7 reveal_file

| Field | Value |
|---|---|
| Prompt | `show axion_note.txt in Finder` |
| Expected tool | `reveal_file` |
| Confirmation | No |
| Expected result | Finder opens the folder and reveals the file |
| Expected UI | Success card |
| Status | OK |

## 1.8 open_file

| Field | Value |
|---|---|
| Prompt | `open axion_note.txt from my Desktop` |
| Expected tool | `open_file` |
| Confirmation | No |
| Expected result | The file opens with the default app |
| Expected UI | `File opened` card |
| Status | OK |

## 1.9 search_file_content

| Field | Value |
|---|---|
| Prompt | `search for hello inside axion_note.txt on my Desktop` |
| Expected tool | `search_file_content` |
| Confirmation | No |
| Expected result | Occurrence of `hello` is found |
| Expected UI | Card or message with matching lines |
| Status | REVIEW |

---

# 2. Files — sensitive actions

## 2.1 rename_file

| Field | Value |
|---|---|
| Precondition | `~/Desktop/axion_note.txt` exists |
| Prompt | `rename axion_note.txt on my Desktop to axion_note_renamed.txt` |
| Expected tool | `rename_file` |
| Confirmation | Yes |
| Expected result | The file becomes `~/Desktop/axion_note_renamed.txt` after confirmation |
| Expected UI | Confirmation panel, then `File renamed` card |
| Status | OK |

## 2.2 move_file

| Field | Value |
|---|---|
| Precondition | `~/Desktop/axion_note_renamed.txt` and `~/Desktop/axion_test_folder` exist |
| Prompt | `move axion_note_renamed.txt from my Desktop into axion_test_folder on my Desktop` |
| Expected tool | `move_file` |
| Confirmation | Yes |
| Expected result | File moved into `~/Desktop/axion_test_folder` |
| Expected UI | Confirmation panel, then `File moved` card |
| Status | KO DESTINATION ALREADY EXISTS |

## 2.3 delete_file

| Field | Value |
|---|---|
| Precondition | `~/Desktop/axion_test_folder/axion_note_renamed.txt` exists |
| Prompt | `delete axion_note_renamed.txt inside axion_test_folder on my Desktop` |
| Expected tool | `delete_file` |
| Confirmation | Yes |
| Expected result | File deleted or moved to Trash depending on implementation |
| Expected UI | Confirmation panel, then warning/success card |
| Status | TODO |

## 2.4 compress_file

| Field | Value |
|---|---|
| Precondition | `~/Desktop/axion_test_folder` exists |
| Prompt | `compress axion_test_folder on my Desktop into axion_test_folder.zip on my Desktop` |
| Expected tool | `compress_file` |
| Confirmation | Yes |
| Expected result | Archive created: `~/Desktop/axion_test_folder.zip` |
| Expected UI | Confirmation panel, then `Archive created` card or equivalent |
| Status | TODO |

## 2.5 extract_archive

| Field | Value |
|---|---|
| Precondition | `~/Desktop/axion_test_folder.zip` exists |
| Prompt | `extract axion_test_folder.zip on my Desktop into a folder named axion_extracted on my Desktop` |
| Expected tool | `extract_archive` |
| Confirmation | Yes |
| Expected result | Archive extracted into `~/Desktop/axion_extracted` |
| Expected UI | Confirmation panel, then `Archive extracted` card or equivalent |
| Status | TODO |

## 2.6 clean_folder dry-run

| Field | Value |
|---|---|
| Prompt | `clean my Desktop folder in dry run mode` |
| Expected tool | `clean_folder` |
| Confirmation | Yes |
| Expected result | No files deleted, only a dry-run report |
| Expected UI | Confirmation panel, then warning/neutral card |
| Status | KO |

---

# 3. Web Apps

## 3.1 open_url

| Field | Value |
|---|---|
| Prompt | `open github.com` |
| Expected tool | `open_url` |
| Confirmation | No |
| Expected result | GitHub opens in the browser |
| Expected UI | `URL opened` card |
| Status | TODO |

## 3.2 open_app

| Field | Value |
|---|---|
| Prompt | `open Finder` |
| Expected tool | `open_app` |
| Confirmation | No |
| Expected result | Finder opens or becomes active |
| Expected UI | `App opened` card |
| Status | TODO |

## 3.3 focus_app

| Field | Value |
|---|---|
| Prompt | `focus Safari` |
| Expected tool | `focus_app` |
| Confirmation | No |
| Expected result | Safari becomes frontmost if running |
| Expected UI | Success card or warning if Safari is not running |
| Status | TODO |

## 3.4 hide_app

| Field | Value |
|---|---|
| Prompt | `hide Safari` |
| Expected tool | `hide_app` |
| Confirmation | No |
| Expected result | Safari is hidden if running |
| Expected UI | Success or warning card |
| Status | TODO |

## 3.5 quit_app

| Field | Value |
|---|---|
| Prompt | `quit Safari` |
| Expected tool | `quit_app` |
| Confirmation | No |
| Expected result | Safari quits if running |
| Expected UI | Success or warning card |
| Status | TODO |

---

# 4. Text

## 4.1 copy_to_clipboard

| Field | Value |
|---|---|
| Prompt | `copy hello from AXION to my clipboard` |
| Expected tool | `copy_to_clipboard` |
| Confirmation | No |
| Expected result | Clipboard contains `hello from AXION` |
| Expected UI | `Copied to clipboard` card |
| Status | KO a juste copié hello |

## 4.2 get_clipboard

| Field | Value |
|---|---|
| Prompt | `what is currently in my clipboard?` |
| Expected tool | `get_clipboard` |
| Confirmation | No |
| Expected result | Current clipboard content is displayed |
| Expected UI | Readable card or message |
| Status | KO pas de texte que la card |

## 4.3 get_current_datetime

| Field | Value |
|---|---|
| Prompt | `what is the current date and time?` |
| Expected tool | `get_current_datetime` |
| Confirmation | No |
| Expected result | Local date and time are displayed |
| Expected UI | Readable card or message |
| Status | TODO |

## 4.4 search_in_spotlight

| Field | Value |
|---|---|
| Prompt | `search Spotlight for Xcode` |
| Expected tool | `search_in_spotlight` |
| Confirmation | No |
| Expected result | Spotlight search is launched for `Xcode` |
| Expected UI | Success card |
| Status | TODO |

---

# 5. System

## 5.1 show_notification

| Field | Value |
|---|---|
| Prompt | `show me a notification that says AXION test complete` |
| Expected tool | `show_notification` |
| Confirmation | No |
| Expected result | macOS notification is shown |
| Expected UI | `Notification shown` card |
| Status | TODO |

## 5.2 take_screenshot

| Field | Value |
|---|---|
| Prompt | `take a screenshot and save it to my Desktop` |
| Expected tool | `take_screenshot` |
| Confirmation | No |
| Expected result | Screenshot created on Desktop |
| Expected UI | `Screenshot saved` card |
| Status | TODO |

## 5.3 set_volume

| Field | Value |
|---|---|
| Prompt | `set the volume to 30 percent` |
| Expected tool | `set_volume` |
| Confirmation | No |
| Expected result | System volume is set to 30% |
| Expected UI | Success card |
| Status | TODO |

## 5.4 get_battery_status

| Field | Value |
|---|---|
| Prompt | `what is my battery status?` |
| Expected tool | `get_battery_status` |
| Confirmation | No |
| Expected result | Battery percentage and charging status are displayed |
| Expected UI | Readable card or message |
| Status | TODO |

## 5.5 toggle_dark_mode

| Field | Value |
|---|---|
| Prompt | `toggle dark mode` |
| Expected tool | `toggle_dark_mode` |
| Confirmation | No |
| Expected result | macOS appearance toggles |
| Expected UI | Success card |
| Status | TODO |

---

# 6. Dev

## 6.1 list_processes

| Field | Value |
|---|---|
| Prompt | `show me the currently running processes` |
| Expected tool | `list_processes` |
| Confirmation | No |
| Expected result | Process list is displayed |
| Expected UI | Readable card or message |
| Status | KO |

Invalid category expected dev, got developer tools

## 6.2 open_in_vscode

| Field | Value |
|---|---|
| Prompt | `open my AXION project in VS Code` |
| Expected tool | `open_in_vscode` |
| Confirmation | No |
| Expected result | AXION project opens in VS Code |
| Expected UI | Success card |
| Status | TODO |

## 6.3 git_status

| Field | Value |
|---|---|
| Prompt | `show me the git status of my AXION project` |
| Expected tool | `git_status` |
| Confirmation | No |
| Expected result | Git status for the project is displayed |
| Expected UI | Readable card or message |
| Status | TODO |

Invalid category

## 6.4 open_terminal_here

| Field | Value |
|---|---|
| Prompt | `open a terminal in my AXION project folder` |
| Expected tool | `open_terminal_here` |
| Confirmation | No |
| Expected result | Terminal opens in the project folder |
| Expected UI | Success card |
| Status | TODO |

---

# 7. Third Party

## 7.1 create_reminder

| Field | Value |
|---|---|
| Prompt | `remind me tomorrow at 6 PM to test AXION` |
| Expected tool | `create_reminder` |
| Confirmation | No |
| Expected result | Reminder created for tomorrow at 6 PM |
| Expected UI | Success card |
| Status | TODO |

Failed to create reminder

## 7.2 create_calendar_event

| Field | Value |
|---|---|
| Prompt | `create a calendar event tomorrow from 6 PM to 7 PM called AXION test` |
| Expected tool | `create_calendar_event` |
| Confirmation | No |
| Expected result | Calendar event created with the correct title and time slot |
| Expected UI | Success card |
| Status | TODO |

Failed to create calendar event

---

# 8. Multi-step and guardrails

## 8.1 Simple multi-step

| Field | Value |
|---|---|
| Prompt | `create a folder named axion_multi_a and a folder named axion_multi_b in my Desktop folder` |
| Expected tools | `create_folder`, then `create_folder` |
| Confirmation | No |
| Expected result | Both folders are created |
| Expected UI | Two `Folder created` cards, no parasite summary |
| Status | TODO |

## 8.2 Repetition blocked

| Field | Value |
|---|---|
| Prompt | `create a folder named axion_repeat and then create a folder named axion_repeat in my Desktop folder` |
| Expected tools | `create_folder`, then stop or warning |
| Confirmation | No |
| Expected result | AXION does not loop indefinitely |
| Expected UI | Success card, then warning card if repetition is blocked |
| Status | TODO |

## 8.3 Max tool limit

| Field | Value |
|---|---|
| Prompt | `create folders axion_1 and axion_2 and axion_3 and axion_4 and axion_5 and axion_6 on my Desktop` |
| Expected tools | Maximum 5 tool calls |
| Confirmation | No |
| Expected result | AXION stops after `maxToolCallsPerRun` |
| Expected UI | Warning card: `maximum number of tool calls reached` |
| Status | REVIEW (que deux dossiers créés) |

## 8.4 Simple command that must not continue

| Field | Value |
|---|---|
| Prompt | `write in a file named single_action.txt on my Desktop the text one action only` |
| Expected tool | `create_text_file` only |
| Confirmation | No |
| Expected result | One file created, no append after that |
| Expected UI | One result card only |
| Status | OK |

---

# 9. Cleanup after tests

Run manually at the end:

```bash
rm -rf ~/Desktop/axion_test_folder
rm -rf ~/Desktop/axion_extracted
rm -rf ~/Desktop/axion_multi_a
rm -rf ~/Desktop/axion_multi_b
rm -rf ~/Desktop/axion_repeat
rm -rf ~/Desktop/axion_1 ~/Desktop/axion_2 ~/Desktop/axion_3 ~/Desktop/axion_4 ~/Desktop/axion_5 ~/Desktop/axion_6
rm -f ~/Desktop/axion_note.txt
rm -f ~/Desktop/axion_note_renamed.txt
rm -f ~/Desktop/axion_test_folder.zip
rm -f ~/Desktop/single_action.txt
```

---

# 10. Global summary

| Block | Status |
|---|---|
| Files safe | TODO |
| Files sensitive | TODO |
| Web Apps | TODO |
| Text | TODO |
| System | TODO |
| Dev | TODO |
| Third Party | TODO |
| Multi-step / Guardrails | TODO |
