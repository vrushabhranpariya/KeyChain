# KeyChain

**KeyChain** is a lightweight, background Windows macro application built with AutoHotkey v2. It enables you to organize key combinations and automated actions into customizable execution groups with non-blocking live updates, user-friendly hotkey parsing, and dynamic command sequences.

---

## Features

* **Advanced Hotkey Parser**: Accepts human-friendly hotkey strings (e.g., `Ctrl+Alt+C`, `Win + Shift + A`) and automatically converts them into native AutoHotkey modifier symbols.
* **Extended Action Command Suite**: Supports standard keystroke execution along with inline commands:
  * `{Text}your string` — Raw literal text typing without accidental modifier triggers.
  * `{Sleep ms}` — Custom inline delays between individual actions.
  * `{Click}` / `{Click X, Y}` — Automated mouse clicks.
  * `{WinActivate Title}` — Window focus management.
  * `{Run target}` — Application, file, or URL launching.
* **Interactive Management GUI**: Built-in visual editor to create, reorder, label, and test key-action groups.
* **Live Re-registration**: Modifying hotkeys or actions updates memory instantly without requiring a full script restart or tray flash.
* **Data Loss & Conflict Prevention**: Automatic duplicate hotkey collision warnings, unsaved GUI state preservation on group switching, and clean unbinding of retired hotkeys.
* **Backward Compatibility**: Automatically reads legacy comma-separated (`,`) sequences from AutoHotkey v1 settings while storing new configurations in pipe-delimited (`|`) format to handle literal strings safely.

---

## Technical Specifications

| Parameter               | Specification                                       |
| :---------------------- | :-------------------------------------------------- |
| **Runtime Environment** | AutoHotkey v2.0+                                    |
| **Operating System**    | Windows 10 / Windows 11                             |
| **Config Storage**      | `settings.ini` (Auto-generated in script directory) |
| **Default Delay**       | 50 ms (Configurable per group)                      |
| **Default Hotkey**      | `Ctrl + Alt + C` (`^!c`)                            |

---

## Key Syntax Rules

### Hotkey Inputs
You can define hotkeys using standard AHK notation or plain English:

* `Ctrl+Alt+C` $\rightarrow$ `^!c`
* `Win+Shift+A` $\rightarrow$ `+#a`
* `Alt+F4` $\rightarrow$ `!{F4}`
* Combined prefixes like `~$^!c` are preserved.

### Action Commands
Each action entry in a sequence supports the following formats:

```text
{Space}                 ; Standard key press
Ctrl+C                  ; Friendly key combination
{Text}Hello, World!     ; Literal text output
{Sleep 250}             ; Pause execution for 250 milliseconds
{Click 500, 300}        ; Click coordinates (500, 300)
{WinActivate Notepad}   ; Bring Notepad window to front
{Run [https://github.com](https://github.com)}; Open URL or executable
```

### Application Structure
```text
KeyChain/
├── KeyChainV2.ahk      # Core application logic & GUI implementation
└── settings.ini        # Persistence layer for group configurations
```

### Data Schema (settings.ini)
```Ini, TOML
[Group 1]
Hotkey=^!c
Label=Quick Navigation
Delay=50
Sequence={Space}|!{Esc}|{Space}
```

---

## System Workflow
```
[ User Input / Hotkey Trigger ]
               │
               ▼
   ExecuteGroupHotkey(index)
               │
               ├──────► Validate Group Index & Sequence Length
               │
               ▼
     Iterate Action Sequence
               │
               ├──────► {Sleep N}       ──► Sleep(ms)
               ├──────► {Text}Str       ──► SendText(Str)
               ├──────► {Click ...}     ──► Click(...)
               ├──────► {WinActivate T} ──► WinActivate(T)
               ├──────► {Run Target}    ──► Run(Target)
               └──────► Keystroke       ──► Send(ParsedKeystroke)
               │
               ▼
         Per-Action Delay
               │
               ▼
        Display Tooltip
```

---

## Usage Instructions

### 1. End User (Pre-compiled Executable)

1. Download the latest `KeyChainV*.*.exe` release from the project releases section.
2. Launch `KeyChainV*.*.exe` (no installation or AutoHotkey software required).
3. Access settings by right-clicking the system tray icon and selecting **Settings** (or double-clicking the tray icon).
4. Manage your hotkey groups:
   * **Label**: Set a custom display name.
   * **Hotkey**: Press key combinations or enter friendly text (e.g., 'Ctrl+Alt+K').
   * **Delay (ms)**: Set the execution delay between individual actions.
   * **Action Sequence**: Add, remove, or reorder key actions and command blocks.
5. Click **Save** to instantly apply and activate your hotkey bindings.

### 2. Developer (Running & Extending Source Code)

#### Prerequisites
* Install [AutoHotkey v2.0](https://www.autohotkey.com/) or higher.
* A code editor such as VS Code with the AutoHotkey v2 language extension.

#### Running from Source
1. Clone or download the repository containing `KeyChain.ahk`.
2. Run `KeyChain.ahk` directly by double-clicking the file or via terminal:
   ```cmd
   AutoHotkey64.exe KeyChain.ahk
   ```
