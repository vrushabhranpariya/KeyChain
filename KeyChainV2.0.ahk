#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================================
; KeyChain — Key-Action Group Manager
; =====================================================================================

; --- Configuration & Initialization ---
IniFile := A_ScriptDir "\settings.ini"
DefaultGroupHotkey := "^!c"
DefaultGroupSequence := "{Space}|!{Esc}|{Space}"
Groups := []            ; Array of objects: { Hotkey, Label, Delay, Sequence }
RegisteredHotkeys := [] ; Tracks active hotkeys for clean re-registration
CurrentEditIndex := 0   ; Index of group in detail panel
IsRefreshingList := false ; Guard flag for ListBox events

LoadSettings()
SetupTrayMenu()
RegisterAllHotkeys()

; --- Core Hotkey Handler & Parsers ---

ExecuteGroupHotkey(groupIndex, *) {
    global Groups
    if (groupIndex < 1 || groupIndex > Groups.Length) {
        ShowTooltip("Invalid group index: " . groupIndex)
        return
    }

    group := Groups[groupIndex]
    sequence := group.Sequence

    if (sequence.Length = 0) {
        ShowTooltip("No actions configured for " . GroupDisplayName(group, groupIndex))
        return
    }

    delay := group.HasOwnProp("Delay") ? group.Delay : 50
    for rawAction in sequence {
        if (Trim(rawAction) != "") {
            ExecuteAction(rawAction)
            Sleep delay
        }
    }

    ShowTooltip(GroupDisplayName(group, groupIndex) . " executed")
}

; Advanced Action Keystroke Parser & Executor
ExecuteAction(actionStr) {
    actionStr := Trim(actionStr)

    ; Built-in commands syntax parser: {Command Arg}
    if RegExMatch(actionStr, "i)^\{Sleep\s+(\d+)\}$", &match) {
        Sleep Integer(match[1])
        return
    }

    if RegExMatch(actionStr, "i)^\{Text\}(.*)$", &match) {
        SendText(match[1])
        return
    }

    if RegExMatch(actionStr, "i)^\{Click(?:\s+(.*))?\}$", &match) {
        if match[1] != ""
            Click(match[1])
        else
            Click()
        return
    }

    if RegExMatch(actionStr, "i)^\{WinActivate\s+(.*)\}$", &match) {
        if WinExist(match[1])
            WinActivate(match[1])
        return
    }

    if RegExMatch(actionStr, "i)^\{Run\s+(.*)\}$", &match) {
        try Run(match[1])
        return
    }

    ; Standard Keystroke Action Processing
    parsedKeystroke := ParseActionKeystroke(actionStr)
    Send(parsedKeystroke)
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

; --- Settings & Data Management ---

LoadSettings() {
    global Groups, IniFile, DefaultGroupHotkey, DefaultGroupSequence
    Groups := []

    if !FileExist(IniFile) {
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
        sectionIndex++
    }

    if (Groups.Length = 0) {
        Groups.Push({ Hotkey: DefaultGroupHotkey, Label: "Group 1", Delay: 50,
            Sequence: StrSplit(DefaultGroupSequence, "|") })
    }
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
}

SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("Settings", (*) => ShowSettingsGUI())
    A_TrayMenu.Add("Reload Script", (*) => Reload())
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Settings"
}

RegisterAllHotkeys() {
    global Groups, RegisteredHotkeys

    for hk in RegisteredHotkeys {
        try Hotkey(hk, "Off")
    }
    RegisteredHotkeys := []

    seen := Map()
    for index, group in Groups {
        parsedHk := ParseHotkeyString(group.Hotkey)
        if (parsedHk = "")
            continue

        if seen.Has(parsedHk) {
            ShowTooltip("Duplicate hotkey '" . parsedHk . "' — group " . index .
                " conflicts with group " . seen[parsedHk] . " and was not registered.", 2500)
            continue
        }

        try {
            Hotkey(parsedHk, ExecuteGroupHotkey.Bind(index))
            RegisteredHotkeys.Push(parsedHk)
            seen[parsedHk] := index
        } catch {
            ShowTooltip("Invalid hotkey for group " . index . ": " . parsedHk, 2500)
        }
    }
}

; --- Interactive GUI Build for Group Management ---

ShowSettingsGUI() {
    global Groups, CurrentEditIndex
    CurrentEditIndex := 0

    settingsGui := Gui("+AlwaysOnTop -MaximizeBox", "Group Settings")
    settingsGui.OnEvent("Close", (*) => settingsGui.Destroy())

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

    btnAddAction.OnEvent("Click", (*) => PromptAddAction(lbActions, settingsGui))
    btnDeleteAction.OnEvent("Click", (*) => DeleteSelectedAction(lbActions))
    btnMoveUpAction.OnEvent("Click", (*) => MoveItem(lbActions, -1))
    btnMoveDownAction.OnEvent("Click", (*) => MoveItem(lbActions, 1))

    btnAddGroup.OnEvent("Click", (*) => AddGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions))
    btnRemoveGroup.OnEvent("Click", (*) => RemoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions))
    btnMoveUpGroup.OnEvent("Click", (*) => MoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, -1))
    btnMoveDownGroup.OnEvent("Click", (*) => MoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, 1))

    btnCancel.OnEvent("Click", (*) => settingsGui.Destroy())
    btnSave.OnEvent("Click", (*) => SaveConfig(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions, settingsGui))

    settingsGui.Show("w540 h500")

    if (Groups.Length > 0)
        lbGroups.Value := 1
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
    CurrentEditIndex := selectedIndex
    LoadGroupIntoPanel(selectedIndex, tbHotkey, tbLabel, tbDelay, lbActions)
    RefreshGroupList(lbGroups, selectedIndex)
}

AddGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups, CurrentEditIndex
    CommitEditsToGroup(CurrentEditIndex, tbHotkey, tbLabel, tbDelay, lbActions)

    newIndex := Groups.Length + 1
    Groups.Push({ Hotkey: "", Label: "Group " . newIndex, Delay: 50, Sequence: [] })

    RefreshGroupList(lbGroups, newIndex)
    CurrentEditIndex := newIndex
    LoadGroupIntoPanel(newIndex, tbHotkey, tbLabel, tbDelay, lbActions)
}

RemoveGroup(lbGroups, tbHotkey, tbLabel, tbDelay, lbActions) {
    global Groups, CurrentEditIndex
    selectedIndex := lbGroups.Value
    if (selectedIndex < 1 || selectedIndex > Groups.Length)
        return

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
    if (selectedIndex < 1 || selectedIndex > Groups.Length)
        return

    targetIndex := selectedIndex + direction
    if (targetIndex < 1 || targetIndex > Groups.Length)
        return

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
    }
}

DeleteSelectedAction(listBoxObj) {
    selectedIndex := listBoxObj.Value
    if (selectedIndex > 0) {
        listBoxObj.Delete(selectedIndex)
    }
}

MoveItem(listBoxObj, direction) {
    currIndex := listBoxObj.Value
    if (currIndex == 0)
        return

    targetIndex := currIndex + direction
    items := ControlGetItems(listBoxObj.Hwnd)
    totalItems := items.Length

    if (targetIndex < 1 || targetIndex > totalItems)
        return

    temp := items[currIndex]
    items[currIndex] := items[targetIndex]
    items[targetIndex] := temp

    listBoxObj.Delete()
    listBoxObj.Add(items)
    listBoxObj.Value := targetIndex
}
