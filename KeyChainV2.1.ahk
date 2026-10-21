#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================================
; KeyChain — Key-Action Group Manager
; =====================================================================================

; --- Configuration & Initialization ---
IniFile := A_ScriptDir "\settings.ini"
LogDirectory := A_ScriptDir "\logs"
LogFilePrefix := "KeyChain_"
DefaultGroupHotkey := "^!c"
DefaultGroupSequence := "{Space}|!{Esc}|{Space}"
Groups := []            ; Array of objects: { Hotkey, Label, Delay, Sequence }
RegisteredHotkeys := [] ; Tracks active hotkeys for clean re-registration
CurrentEditIndex := 0   ; Index of group in detail panel
IsRefreshingList := false ; Guard flag for ListBox events

InitializeLogRetention()
OnExit(LogApplicationExit)
LogEvent("application_started", "script=" . A_ScriptName)
LoadSettings()
SetupTrayMenu()
RegisterAllHotkeys()

; --- Core Hotkey Handler & Parsers ---

ExecuteGroupHotkey(groupIndex, *) {
    global Groups
    LogEvent("group_hotkey_triggered", "group_index=" . groupIndex)
    if (groupIndex < 1 || groupIndex > Groups.Length) {
        LogEvent("group_hotkey_rejected", "reason=invalid_group_index; group_index=" . groupIndex, "ERROR")
        ShowTooltip("Invalid group index: " . groupIndex)
        return
    }

    group := Groups[groupIndex]
    sequence := group.Sequence

    if (sequence.Length = 0) {
        LogEvent("group_execution_skipped", "group_index=" . groupIndex . "; reason=empty_sequence")
        ShowTooltip("No actions configured for " . GroupDisplayName(group, groupIndex))
        return
    }

    delay := group.HasOwnProp("Delay") ? group.Delay : 50
    LogEvent("group_execution_started", "group_index=" . groupIndex . "; label=" . group.Label
        . "; hotkey=" . group.Hotkey . "; delay_ms=" . delay . "; action_count=" . sequence.Length)
    for rawAction in sequence {
        if (Trim(rawAction) != "") {
            try {
                ExecuteAction(rawAction)
            } catch Error as err {
                LogEvent("group_action_failed", "group_index=" . groupIndex . "; action=" . rawAction
                    . "; error=" . err.Message, "ERROR")
                throw err
            }
            Sleep delay
        }
    }

    LogEvent("group_execution_completed", "group_index=" . groupIndex . "; label=" . GroupDisplayName(group, groupIndex
    ))
    ShowTooltip(GroupDisplayName(group, groupIndex) . " executed")
}

; Advanced Action Keystroke Parser & Executor
ExecuteAction(actionStr) {
    actionStr := Trim(actionStr)
    LogEvent("action_started", "action=" . actionStr)

    ; Built-in commands syntax parser: {Command Arg}
    if RegExMatch(actionStr, "i)^\{Sleep\s+(\d+)\}$", &match) {
        Sleep Integer(match[1])
        LogEvent("action_completed", "action=" . actionStr . "; type=sleep; duration_ms=" . match[1])
        return
    }

    if RegExMatch(actionStr, "i)^\{Text\}(.*)$", &match) {
        SendText(match[1])
        LogEvent("action_completed", "action=" . actionStr . "; type=text")
        return
    }

    if RegExMatch(actionStr, "i)^\{Click(?:\s+(.*))?\}$", &match) {
        if match[1] != ""
            Click(match[1])
        else
            Click()
        LogEvent("action_completed", "action=" . actionStr . "; type=click")
        return
    }

    if RegExMatch(actionStr, "i)^\{WinActivate\s+(.*)\}$", &match) {
        if WinExist(match[1]) {
            WinActivate(match[1])
            LogEvent("action_completed", "action=" . actionStr . "; type=window_activate; result=activated")
        } else
            LogEvent("action_completed", "action=" . actionStr . "; type=window_activate; result=window_not_found",
                "ERROR")
        return
    }

    if RegExMatch(actionStr, "i)^\{Run\s+(.*)\}$", &match) {
        try {
            Run(match[1])
            LogEvent("action_completed", "action=" . actionStr . "; type=run; target=" . match[1])
        } catch Error as err {
            LogEvent("action_failed", "action=" . actionStr . "; type=run; error=" . err.Message, "ERROR")
            throw err
        }
        return
    }

    ; Standard Keystroke Action Processing
    parsedKeystroke := ParseActionKeystroke(actionStr)
    Send(parsedKeystroke)
    LogEvent("action_completed", "action=" . actionStr . "; type=keystroke; parsed=" . parsedKeystroke)
}

ParseActionKeystroke(inputStr) {
    str := Trim(inputStr)
    if (str = "")
        return ""

    ; If user typed friendly combo like "Ctrl+Alt+Delete" or "Ctrl+C"
    if InStr(str, "+") && !RegExMatch(str, "^\{.*\}$") {
        parts := StrSplit(str, "+")
        modifiers := ""
        key := ""
        for idx, part in parts {
            p := Trim(part)
            switch Low(p) {
                case "ctrl", "control": modifiers .= "^"
                case "alt": modifiers .= "!"
                case "shift": modifiers .= "+"
                case "win", "lwin", "rwin": modifiers .= "#"
                default: key := p
            }
        }
        if (key != "") {
            if (StrLen(key) > 1 && !SubStr(key, 1, 1) = "{")
                key := "{" . key . "}"
            return modifiers . key
        }
    }

    return str
}

; Advanced Hotkey Input Parser
ParseHotkeyString(inputStr) {
    str := Trim(inputStr)
    if (str = "")
        return ""

    ; If it already uses standard AHK syntax (e.g. ^!c, ~#a), return normalized
    if RegExMatch(str,
        "^[\^\!\+\#\~\$\*\<\>]*[a-zA-Z0-9F1-F24KeyPadSpaceTabEnterEscBSDelInsHomeEndPgUpPgDnUpDownLeftRight]+$")
        return str

    ; Parse friendly human text syntax like "Ctrl + Alt + C" or "Win+Shift+F"
    prefix := ""
    cleanStr := RegExReplace(str, "\s+", "") ; strip spaces

    ; Extract prefix symbols (~, $, *)
    while RegExMatch(cleanStr, "^([\~\$\*])(.*)$", &m) {
        prefix .= m[1]
        cleanStr := m[2]
    }

    tokens := StrSplit(cleanStr, "+")
    mods := ""
    mainKey := ""

    for token in tokens {
        switch Low(token) {
            case "ctrl", "control", "lctrl", "rctrl": mods .= "^"
            case "alt", "lalt", "ralt": mods .= "!"
            case "shift", "lshift", "rshift": mods .= "+"
            case "win", "lwin", "rwin": mods .= "#"
            default: mainKey := token
        }
    }

    if (mainKey = "")
        return str ; Fallback to original if parsing fails

    return prefix . mods . Low(mainKey)
}

Low(str) {
    return StrLower(str)
}

GroupDisplayName(group, index) {
    return (group.HasOwnProp("Label") && group.Label != "") ? group.Label : ("Group " . index)
}

ShowTooltip(text, duration := 1000) {
    ToolTip(text, A_ScreenWidth - 150, A_ScreenHeight - 50)
    SetTimer () => ToolTip(), -duration
}

LogApplicationExit(exitReason, exitCode) {
    LogEvent("application_exit", "reason=" . exitReason . "; exit_code=" . exitCode)
}

; --- Settings & Data Management ---

InitializeLogRetention() {
    global LogDirectory, LogFilePrefix
    if !DirExist(LogDirectory)
        DirCreate(LogDirectory)

    deletedCount := 0
    cutoff := FormatTime(DateAdd(A_Now, -3, "Days"), "yyyyMMdd")
    pattern := LogDirectory "\" . LogFilePrefix . "*.log"
    deletedFiles := []
    loop files, pattern, "F" {
        modifiedTime := ""
        if RegExMatch(A_LoopFileName, "(\d{4})[-_]?([01]\d)[-_]?([0-3]\d)", &dateMatch)
            modifiedTime := dateMatch[1] . dateMatch[2] . dateMatch[3]
        if (modifiedTime != "") {
            if (DateDiff(modifiedTime, cutoff, "Days") <= 0) {
                try {
                    FileDelete(A_LoopFileFullPath)
                    deletedCount++
                    deletedFiles.Push(A_LoopFileName)
                } catch Error as err {
                    LogEvent("log_retention_delete_failed", "file=" . A_LoopFileName . "; error=" . err.Message,
                        "ERROR")
                }
            }
        }
    }
    LogEvent("log_retention_completed", "retention_days=3; deleted_files=" . deletedCount . "; file_names=" . ArrJoin(
        deletedFiles, ", "))
}

LogEvent(eventName, details := "", category := "INFO") {
    global LogDirectory, LogFilePrefix
    category := StrUpper(category)
    if (category != "INFO" && category != "ERROR")
        throw ValueError("Invalid log category: " . category)
    if (details != "") {
        details := StrReplace(details, "`r", "\r")
        details := StrReplace(details, "`n", "\n")
        details := StrReplace(details, "`t", "\t")
    }
    logFile := LogDirectory "\" . LogFilePrefix . FormatTime(A_Now, "yyyyMMdd") . ".log"
    FileAppend(FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") . " [" . category . "] [" . eventName . "]"
    . (details = "" ? "" : " " . details) . "`n", logFile, "UTF-8-RAW")
}

LoadSettings() {
    global Groups, IniFile, DefaultGroupHotkey, DefaultGroupSequence
    Groups := []

    if !FileExist(IniFile) {
        LogEvent("settings_missing", "file=" . IniFile . "; result=creating_default_group")
        Groups.Push({ Hotkey: DefaultGroupHotkey, Label: "Group 1", Delay: 50,
            Sequence: StrSplit(DefaultGroupSequence, "|") })
        SaveGroups()
        return
    }

    Missing := "##MISSING##"
    sectionIndex := 1
    while (true) {
        sectionName := "Group " . sectionIndex
        hotkey := IniRead(IniFile, sectionName, "Hotkey", Missing)
        if (hotkey = Missing)
            break

        sequenceStr := IniRead(IniFile, sectionName, "Sequence", "")
        label := IniRead(IniFile, sectionName, "Label", "Group " . sectionIndex)
        delay := ParseDelay(IniRead(IniFile, sectionName, "Delay", "50"))

        Groups.Push({ Hotkey: ParseHotkeyString(hotkey), Label: label, Delay: delay, Sequence: ParseSequenceString(
            sequenceStr) })
        LogEvent("settings_group_loaded", "group_index=" . sectionIndex . "; label=" . label . "; hotkey=" . hotkey
            . "; delay_ms=" . delay . "; action_count=" . Groups[Groups.Length].Sequence.Length)
        sectionIndex++
    }

    if (Groups.Length = 0) {
        LogEvent("settings_empty", "file=" . IniFile . "; result=using_default_group")
        Groups.Push({ Hotkey: DefaultGroupHotkey, Label: "Group 1", Delay: 50,
            Sequence: StrSplit(DefaultGroupSequence, "|") })
    }
    LogEvent("settings_loaded", "group_count=" . Groups.Length . "; file=" . IniFile)
}

ParseSequenceString(s) {
    if (s = "")
        return []
    if InStr(s, "|")
        return StrSplit(s, "|")
    return StrSplit(s, ",")
}

ParseDelay(val) {
    val := Trim(val)
    if (val = "" || !IsNumber(val))
        return 50
    n := Integer(val)
    return (n < 0) ? 50 : n
}

SaveGroups() {
    global Groups, IniFile
    LogEvent("settings_save_started", "group_count=" . Groups.Length . "; file=" . IniFile)

    if FileExist(IniFile) {
        FileDelete(IniFile)
    }

    for index, group in Groups {
        sectionName := "Group " . index
        IniWrite(ParseHotkeyString(group.Hotkey), IniFile, sectionName, "Hotkey")
        IniWrite(GroupDisplayName(group, index), IniFile, sectionName, "Label")
        IniWrite(group.HasOwnProp("Delay") ? group.Delay : 50, IniFile, sectionName, "Delay")

        sequenceStr := ""
        for seqIndex, action in group.Sequence {
            sequenceStr .= (seqIndex = 1 ? "" : "|") . action
        }
        IniWrite(sequenceStr, IniFile, sectionName, "Sequence")
    }
    LogEvent("settings_save_completed", "group_count=" . Groups.Length . "; file=" . IniFile)
}

SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Settings", TrayOpenSettings)
    A_TrayMenu.Add("Reload Script", TrayReloadScript)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", TrayExitApp)
    A_TrayMenu.Default := "Settings"
}

TrayOpenSettings(*) {
    LogEvent("tray_action", "action=settings")
    ShowSettingsGUI()
}

TrayReloadScript(*) {
    LogEvent("tray_action", "action=reload")
    Reload()
}

TrayExitApp(*) {
    LogEvent("tray_action", "action=exit")
    ExitApp()
}

RegisterAllHotkeys() {
    global Groups, RegisteredHotkeys

    for hk in RegisteredHotkeys {
        try {
            Hotkey(hk, "Off")
            LogEvent("hotkey_disabled", "hotkey=" . hk)
        } catch Error as err {
            LogEvent("hotkey_disable_failed", "hotkey=" . hk . "; error=" . err.Message, "ERROR")
        }
    }
    RegisteredHotkeys := []

    seen := Map()
    for index, group in Groups {
        parsedHk := ParseHotkeyString(group.Hotkey)
        if (parsedHk = "") {
            LogEvent("hotkey_skipped", "group_index=" . index . "; reason=unassigned")
            continue
        }

        if seen.Has(parsedHk) {
            LogEvent("hotkey_skipped", "group_index=" . index . "; hotkey=" . parsedHk . "; reason=duplicate"
                . "; conflicts_with_group=" . seen[parsedHk])
            ShowTooltip("Duplicate hotkey '" . parsedHk . "' — group " . index .
                " conflicts with group " . seen[parsedHk] . " and was not registered.", 2500)
            continue
        }

        try {
            Hotkey(parsedHk, ExecuteGroupHotkey.Bind(index))
            RegisteredHotkeys.Push(parsedHk)
            seen[parsedHk] := index
            LogEvent("hotkey_registered", "group_index=" . index . "; hotkey=" . parsedHk)
        } catch Error as err {
            LogEvent("hotkey_registration_failed", "group_index=" . index . "; hotkey=" . parsedHk
                . "; error=" . err.Message, "ERROR")
            ShowTooltip("Invalid hotkey for group " . index . ": " . parsedHk, 2500)
        }
    }
    LogEvent("hotkey_registration_completed", "registered_count=" . RegisteredHotkeys.Length)
}

; --- Interactive GUI Build for Group Management ---

ShowSettingsGUI() {
    global Groups, CurrentEditIndex
    LogEvent("settings_gui_opened", "group_count=" . Groups.Length)
    CurrentEditIndex := 0

    settingsGui := Gui("+AlwaysOnTop -MaximizeBox", "Group Settings")
    settingsGui.OnEvent("Close", (*) => CloseSettingsGUI(settingsGui, "close"))

    settingsGui.Add("Text", "w400", "Manage key-action groups:")
    settingsGui.Add("GroupBox", "x10 y20 w520 h430", "Groups")

    lbGroups := settingsGui.Add("ListBox", "x20 y35 w200 h350 vGroupList", GetGroupDisplayStrings())

    settingsGui.Add("Text", "x240 y35 w60 h20", "Label:")
    tbLabel := settingsGui.Add("Edit", "x305 y33 w215 h20 vGroupLabelEdit", "")

    settingsGui.Add("Text", "x240 y65 w60 h20", "Hotkey:")
    tbHotkey := settingsGui.Add("Hotkey", "x305 y63 w150 h20 vHotkeyEdit", "")

    settingsGui.Add("Text", "x240 y95 w70 h20", "Delay (ms):")
    tbDelay := settingsGui.Add("Edit", "x305 y93 w60 h20 Number vDelayEdit", "50")

    settingsGui.Add("Text", "x240 y125 w150 h20", "Action Sequence:")
    lbActions := settingsGui.Add("ListBox", "x240 y145 w180 h170 vActionList", [])

    btnAddAction := settingsGui.Add("Button", "x430 y145 w80 h25", "Add")
    btnDeleteAction := settingsGui.Add("Button", "x430 y180 w80 h25", "Delete")
    btnMoveUpAction := settingsGui.Add("Button", "x430 y215 w80 h25", "Up")
    btnMoveDownAction := settingsGui.Add("Button", "x430 y250 w80 h25", "Down")

    btnAddGroup := settingsGui.Add("Button", "x20 y400 w100 h30", "Add Group")
    btnRemoveGroup := settingsGui.Add("Button", "x130 y400 w100 h30", "Remove Group")
    btnMoveUpGroup := settingsGui.Add("Button", "x240 y400 w80 h30", "Group Up")
    btnMoveDownGroup := settingsGui.Add("Button", "x330 y400 w80 h30", "Group Down")

    btnSave := settingsGui.Add("Button", "x20 y460 w100 h30 Default", "Save")
    btnCancel := settingsGui.Add("Button", "x130 y460 w100 h30", "Cancel")

    ; Event bindings
    lbGroups.OnEvent("Change", (*) => OnGroupSelect(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions))
    lbActions.OnEvent("Change", (*) => LogEvent("action_selected", "action_index=" . lbActions.Value))
    tbLabel.OnEvent("Change", (*) => LogEvent("group_field_changed", "field=label; value=" . tbLabel.Value))
    tbHotkey.OnEvent("Change", (*) => LogEvent("group_field_changed", "field=hotkey; value=" . tbHotkey.Value))
    tbDelay.OnEvent("Change", (*) => LogEvent("group_field_changed", "field=delay_ms; value=" . tbDelay.Value))

    btnAddAction.OnEvent("Click", (*) => PromptAddAction(lbActions, settingsGui))
    btnDeleteAction.OnEvent("Click", (*) => DeleteSelectedAction(lbActions))
    btnMoveUpAction.OnEvent("Click", (*) => MoveItem(lbActions, -1))
    btnMoveDownAction.OnEvent("Click", (*) => MoveItem(lbActions, 1))

    btnAddGroup.OnEvent("Click", (*) => AddGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions))
    btnRemoveGroup.OnEvent("Click", (*) => RemoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions))
    btnMoveUpGroup.OnEvent("Click", (*) => MoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, -1))
    btnMoveDownGroup.OnEvent("Click", (*) => MoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, 1))

    btnCancel.OnEvent("Click", (*) => CloseSettingsGUI(settingsGui, "cancel"))
    btnSave.OnEvent("Click", (*) => SaveConfig(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, settingsGui))

    settingsGui.Show("w540 h500")

    if (Groups.Length > 0)
        lbGroups.Value := 1
}

CloseSettingsGUI(settingsGui, action) {
    LogEvent("settings_gui_closed", "action=" . action)
    settingsGui.Destroy()
}

CommitEditsToGroup(index, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups
    if (index < 1 || index > Groups.Length)
        return
    Groups[index].Hotkey := ParseHotkeyString(tbHotkey.Value)
    lbl := Trim(tbLabel.Value)
    Groups[index].Label := (lbl != "") ? lbl : ("Group " . index)
    Groups[index].Delay := ParseDelay(tbDelay.Value)
    Groups[index].Sequence := ControlGetItems(lbActions.Hwnd)
    LogEvent("group_edits_committed", "group_index=" . index . "; label=" . Groups[index].Label
        . "; hotkey=" . Groups[index].Hotkey . "; delay_ms=" . Groups[index].Delay
        . "; action_count=" . Groups[index].Sequence.Length)
}

RefreshGroupList(lbGroups, selectIndex := 0) {
    global Groups, IsRefreshingList
    IsRefreshingList := true
    lbGroups.Delete()
    if (Groups.Length > 0)
        lbGroups.Add(GetGroupDisplayStrings())
    if (selectIndex > 0 && selectIndex <= Groups.Length)
        lbGroups.Value := selectIndex
    IsRefreshingList := false
}

LoadGroupIntoPanel(index, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups
    lbActions.Delete()
    if (index < 1 || index > Groups.Length) {
        tbHotkey.Value := ""
        tbLabel.Value := ""
        tbDelay.Value := 50
        return
    }
    group := Groups[index]
    tbHotkey.Value := group.Hotkey
    tbLabel.Value := GroupDisplayName(group, index)
    tbDelay.Value := group.HasOwnProp("Delay") ? group.Delay : 50
    for action in group.Sequence
        lbActions.Add([action])
}

OnGroupSelect(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups, CurrentEditIndex, IsRefreshingList
    if (IsRefreshingList)
        return

    CommitEditsToGroup(CurrentEditIndex, tbHotkey, tbLabel, tbDelay, lbActions)
    selectedIndex := lbGroups.Value
    LogEvent("group_selected", "group_index=" . selectedIndex)
    CurrentEditIndex := selectedIndex
    LoadGroupIntoPanel(selectedIndex, tbHotkey, tbLabel, tbDelay, lbActions)
    RefreshGroupList(lbGroups, selectedIndex)
}

AddGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups, CurrentEditIndex
    CommitEditsToGroup(CurrentEditIndex, tbHotkey, tbLabel, tbDelay, lbActions)

    newIndex := Groups.Length + 1
    Groups.Push({ Hotkey: "", Label: "Group " . newIndex, Delay: 50, Sequence: [] })
    LogEvent("group_added", "group_index=" . newIndex)

    RefreshGroupList(lbGroups, newIndex)
    CurrentEditIndex := newIndex
    LoadGroupIntoPanel(newIndex, tbHotkey, tbLabel, tbDelay, lbActions)
}

RemoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups, CurrentEditIndex
    selectedIndex := lbGroups.Value
    if (selectedIndex < 1 || selectedIndex > Groups.Length) {
        LogEvent("group_remove_skipped", "group_index=" . selectedIndex . "; reason=no_group_selected")
        return
    }

    LogEvent("group_removed", "group_index=" . selectedIndex . "; label=" . GroupDisplayName(Groups[selectedIndex],
        selectedIndex))
    Groups.RemoveAt(selectedIndex)

    if (Groups.Length = 0) {
        RefreshGroupList(lbGroups, 0)
        CurrentEditIndex := 0
        LoadGroupIntoPanel(0, tbHotkey, tbLabel, tbDelay, lbActions)
        return
    }

    newIndex := Min(selectedIndex, Groups.Length)
    RefreshGroupList(lbGroups, newIndex)
    CurrentEditIndex := newIndex
    LoadGroupIntoPanel(newIndex, tbHotkey, tbLabel, tbDelay, lbActions)
}

MoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, direction) {
    global Groups, CurrentEditIndex
    CommitEditsToGroup(CurrentEditIndex, tbHotkey, tbLabel, tbDelay, lbActions)

    selectedIndex := lbGroups.Value
    if (selectedIndex < 1 || selectedIndex > Groups.Length) {
        LogEvent("group_move_skipped", "group_index=" . selectedIndex . "; direction=" . direction
            . "; reason=no_group_selected")
        return
    }

    targetIndex := selectedIndex + direction
    if (targetIndex < 1 || targetIndex > Groups.Length) {
        LogEvent("group_move_skipped", "group_index=" . selectedIndex . "; direction=" . direction
            . "; reason=out_of_bounds")
        return
    }

    LogEvent("group_moved", "from_index=" . selectedIndex . "; to_index=" . targetIndex)
    temp := Groups[selectedIndex]
    Groups[selectedIndex] := Groups[targetIndex]
    Groups[targetIndex] := temp

    RefreshGroupList(lbGroups, targetIndex)
    CurrentEditIndex := targetIndex
    LoadGroupIntoPanel(targetIndex, tbHotkey, tbLabel, tbDelay, lbActions)
}

GetGroupDisplayStrings() {
    global Groups
    displayStrings := []
    for index, group in Groups {
        hotkeyDisplay := (group.Hotkey != "") ? group.Hotkey : "(unassigned)"
        displayStrings.Push("[" . index . "] " . GroupDisplayName(group, index) . "  —  " . hotkeyDisplay)
    }
    return displayStrings
}

SaveConfig(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, guiObj) {
    global Groups, CurrentEditIndex
    CommitEditsToGroup(CurrentEditIndex, tbHotkey, tbLabel, tbDelay, lbActions)

    unassignedCount := 0
    for group in Groups
        if (group.Hotkey = "")
            unassignedCount++

    SaveGroups()
    RegisterAllHotkeys()
    guiObj.Destroy()
    LogEvent("configuration_saved", "group_count=" . Groups.Length . "; unassigned_count=" . unassignedCount)

    if (unassignedCount > 0)
        ShowTooltip(unassignedCount . " group(s) have no hotkey and were left unregistered.", 2500)
    else
        ShowTooltip("Settings saved.", 1200)
}

; --- Helper Functions ---

PromptAddAction(listBoxObj, parentGui) {
    parentGui.Opt("+OwnDialogs")
    msg :=
        "Enter Action:`n- Keystrokes: {Space}, !{Esc}, Ctrl+C`n- Text: {Text}Hello World`n- Delay: {Sleep 500}`n- App: {Run notepad.exe}`n- Click: {Click 100, 200}"
    inputBoxObj := InputBox(msg, "Add Action", "w350 h200")
    if (inputBoxObj.Result == "OK" && inputBoxObj.Value != "") {
        listBoxObj.Add([inputBoxObj.Value])
        LogEvent("action_added", "action=" . inputBoxObj.Value)
    } else {
        LogEvent("action_add_cancelled", "result=" . inputBoxObj.Result)
    }
}

DeleteSelectedAction(listBoxObj) {
    selectedIndex := listBoxObj.Value
    if (selectedIndex > 0) {
        items := ControlGetItems(listBoxObj.Hwnd)
        LogEvent("action_removed", "action_index=" . selectedIndex . "; action=" . items[selectedIndex])
        listBoxObj.Delete(selectedIndex)
    } else {
        LogEvent("action_remove_skipped", "reason=no_action_selected")
    }
}

MoveItem(listBoxObj, direction) {
    currIndex := listBoxObj.Value
    if (currIndex == 0) {
        LogEvent("action_move_skipped", "direction=" . direction . "; reason=no_action_selected")
        return
    }

    targetIndex := currIndex + direction
    items := ControlGetItems(listBoxObj.Hwnd)
    totalItems := items.Length

    if (targetIndex < 1 || targetIndex > totalItems) {
        LogEvent("action_move_skipped", "action_index=" . currIndex . "; direction=" . direction
            . "; reason=out_of_bounds")
        return
    }

    temp := items[currIndex]
    items[currIndex] := items[targetIndex]
    items[targetIndex] := temp

    listBoxObj.Delete()
    listBoxObj.Add(items)
    listBoxObj.Value := targetIndex
    LogEvent("action_moved", "from_index=" . currIndex . "; to_index=" . targetIndex
        . "; action=" . items[targetIndex])
}

; Reusable Join Function
ArrJoin(arr, delimiter := ", ") {
    str := ""
    for index, value in arr
        str .= (index = 1 ? "" : delimiter) . value
    return str
}
