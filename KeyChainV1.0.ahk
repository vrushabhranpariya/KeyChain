#Requires AutoHotkey v2.0
#SingleInstance Force

; --- Configuration & Initialization ---
IniFile := A_ScriptDir "\settings.ini"
DefaultGroupHotkey := "^!c"
DefaultGroupSequence := "{Space},!{Esc},{Space}"
Groups := []  ; Array of objects: each with Hotkey and Sequence properties

LoadSettings()
SetupTrayMenu()
RegisterAllHotkeys()  ; Register hotkeys for all loaded groups

; --- Core Hotkey Definition Template ---
; Hotkeys are now registered dynamically via RegisterAllHotkeys()
; Each hotkey calls ExecuteGroupHotkey with its group index

ExecuteGroupHotkey(groupIndex, *) {
    global Groups
    if (groupIndex < 1 || groupIndex > Groups.Length) {
        ToolTip("Invalid group index: " . groupIndex, A_ScreenWidth - 150, A_ScreenHeight - 50)
        SetTimer () => ToolTip(), -1000
        return
    }

    group := Groups[groupIndex]
    sequence := group.Sequence

    if (sequence.Length == 0) {
        ToolTip("No actions configured for group " . groupIndex, A_ScreenWidth - 150, A_ScreenHeight - 50)
        SetTimer () => ToolTip(), -1000
        return
    }

    for action in sequence {
        if (action != "") {
            Send(action)
            Sleep 50 ; Default execution delay after each action
        }
    }

    ; Optional Visual Feedback
    ToolTip("Group " . groupIndex . " Executed", A_ScreenWidth - 150, A_ScreenHeight - 50)
    SetTimer () => ToolTip(), -1000
}

; --- Settings & Data Management ---

LoadSettings() {
    global Groups, IniFile, DefaultGroupHotkey, DefaultGroupSequence
    Groups := []  ; Reset groups

    if !FileExist(IniFile) {
        ; Create default group on first run
        Groups.Push({ Hotkey: DefaultGroupHotkey, Sequence: StrSplit(DefaultGroupSequence, ",") })
        SaveGroups()  ; Save the default group
        return
    }

    ; Read all sections from INI file
    sectionIndex := 1
    while (true) {
        sectionName := "Group " . sectionIndex
        hotkey := IniRead(IniFile, sectionName, "Hotkey", "")
        if (hotkey = "") {
            ; No more sections found
            break
        }
        sequenceStr := IniRead(IniFile, sectionName, "Sequence", "")
        sequence := StrSplit(sequenceStr, ",")
        Groups.Push({ Hotkey: hotkey, Sequence: sequence })
        sectionIndex++
    }

    ; If no groups were found, create a default one
    if (Groups.Length = 0) {
        Groups.Push({ Hotkey: DefaultGroupHotkey, Sequence: StrSplit(DefaultGroupSequence, ",") })
    }
}

SaveGroups() {
    global Groups, IniFile

    ; Completely delete the file if it exists to wipe out old, leftover groups
    if FileExist(IniFile) {
        FileDelete(IniFile)
    }

    ; Now write each active group cleanly as a separate section
    for index, group in Groups {
        sectionName := "Group " . index
        IniWrite(group.Hotkey, IniFile, sectionName, "Hotkey")

        sequenceStr := ""
        for seqIndex, action in group.Sequence {
            sequenceStr .= (seqIndex = 1 ? "" : ",") . action
        }
        IniWrite(sequenceStr, IniFile, sectionName, "Sequence")
    }
}

SetupTrayMenu() {
    A_TrayMenu.Delete() ; Clear default menu items
    A_TrayMenu.Add("Settings", (*) => ShowSettingsGUI())
    A_TrayMenu.Add() ; Separator
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    A_TrayMenu.Default := "Settings"
}

RegisterAllHotkeys() {
    global Groups
    ; Unregister any existing hotkeys first (though AHK v2 doesn't have explicit unregister
    ; we'll rely on overwriting with Hotkey() calls)

    ; Register hotkey for each group
    for index, group in Groups {
        try {
            ; Use .Bind(index) so the function locks in the specific group number
            Hotkey(group.Hotkey, ExecuteGroupHotkey.Bind(index))
        } catch {
            ToolTip(
                "Invalid hotkey for group " . index . ": " . group.Hotkey,
                A_ScreenWidth - 150,
                A_ScreenHeight - 50
            )
            SetTimer () => ToolTip(), -2000
        }
    }
}

; --- Interactive GUI Build for Group Management ---

ShowSettingsGUI() {
    global Groups

    ; Create GUI window object
    settingsGui := Gui("+AlwaysOnTop -MaximizeBox", "Group Settings")
    settingsGui.OnEvent("Close", (*) => settingsGui.Destroy())

    settingsGui.Add("Text", "w400", "Manage key-action groups:")

    ; Main container with two panels
    settingsGui.Add("GroupBox", "x10 y20 w520 h320", "Groups")

    ; Left Panel: Group List
    lbGroups := settingsGui.Add("ListBox", "x20 y35 w200 h200 vGroupList", GetGroupDisplayStrings())

    ; Right Panel: Selected Group Details
    ; Hotkey section
    settingsGui.Add("Text", "x240 y40 w80", "Hotkey:")
    tbHotkey := settingsGui.Add("Edit", "x330 y38 w100 h20 vHotkeyEdit", "")

    ; Action Sequence section
    settingsGui.Add("Text", "x240 y80 w100", "Action Sequence:")
    lbActions := settingsGui.Add("ListBox", "x240 y100 w180 h120 vActionList", [])

    ; Action controls for sequence editing
    btnAddAction := settingsGui.Add("Button", "x430 y100 w80 h25", "Add")
    btnDeleteAction := settingsGui.Add("Button", "x430 y135 w80 h25", "Delete")
    btnMoveUpAction := settingsGui.Add("Button", "x430 y170 w80 h25", "Up")
    btnMoveDownAction := settingsGui.Add("Button", "x430 y205 w80 h25", "Down")

    ; Group management buttons
    btnAddGroup := settingsGui.Add("Button", "x20 y250 w100 h30", "Add Group")
    btnRemoveGroup := settingsGui.Add("Button", "x130 y250 w100 h30", "Remove Group")
    btnMoveUpGroup := settingsGui.Add("Button", "x240 y250 w80 h30", "Group Up")
    btnMoveDownGroup := settingsGui.Add("Button", "x330 y250 w80 h30", "Group Down")

    ; Save & Cancel Row
    btnSave := settingsGui.Add("Button", "x20 y295 w100 h30 Default", "Save")
    btnCancel := settingsGui.Add("Button", "x130 y295 w100 h30", "Cancel")

    ; --- Event Bindings ---

    ; Group list events
    lbGroups.OnEvent("Change", (*) => OnGroupSelect(lbGroups, tbHotkey, lbActions))

    ; Action list events
    btnAddAction.OnEvent("Click", (*) => PromptAddAction(lbActions, settingsGui))
    btnDeleteAction.OnEvent("Click", (*) => DeleteSelectedAction(lbActions))
    btnMoveUpAction.OnEvent("Click", (*) => MoveItem(lbActions, -1))
    btnMoveDownAction.OnEvent("Click", (*) => MoveItem(lbActions, 1))

    ; Group management events
    btnAddGroup.OnEvent("Click", (*) => AddGroup(lbGroups, tbHotkey, lbActions))
    btnRemoveGroup.OnEvent("Click", (*) => RemoveGroup(lbGroups, tbHotkey, lbActions))
    btnMoveUpGroup.OnEvent("Click", (*) => MoveGroup(lbGroups, -1))
    btnMoveDownGroup.OnEvent("Click", (*) => MoveGroup(lbGroups, 1))

    btnCancel.OnEvent("Click", (*) => settingsGui.Destroy())
    btnSave.OnEvent("Click", (*) => SaveConfig(lbGroups, tbHotkey, lbActions, settingsGui))

    settingsGui.Show("w540 h350")
}

OnGroupSelect(lbGroups, tbHotkey, lbActions) {
    global Groups
    selectedIndex := lbGroups.Value
    if (selectedIndex > 0 && selectedIndex <= Groups.Length) {
        group := Groups[selectedIndex]
        tbHotkey.Value := group.Hotkey
        ; Populate action list
        lbActions.Delete()
        for action in group.Sequence {
            lbActions.Add([action])
        }
        lbActions.Value := 0  ; Clear selection
    } else {
        tbHotkey.Value := ""
        lbActions.Delete()
    }
}

AddGroup(lbGroups, tbHotkey, lbActions) {
    global Groups
    ; Add new group with default values
    newGroup := { Hotkey: "^!c", Sequence: StrSplit("{Space}", ",") }  ; Ctrl+Alt+C, Space as default
    Groups.Push(newGroup)
    ; Refresh group list
    lbGroups.Delete()
    lbGroups.Add(GetGroupDisplayStrings())
    ; Select the newly added group
    lbGroups.Value := Groups.Length
    ; Update detail view
    OnGroupSelect(lbGroups, tbHotkey, lbActions)
}

RemoveGroup(lbGroups, tbHotkey, lbActions) {
    global Groups
    selectedIndex := lbGroups.Value
    if (selectedIndex > 0 && selectedIndex <= Groups.Length) {
        Groups.RemoveAt(selectedIndex)
        ; Refresh group list
        lbGroups.Delete()
        lbGroups.Add(GetGroupDisplayStrings())
        ; Select next group or last if none
        if (Groups.Length > 0) {
            newIndex := Min(selectedIndex, Groups.Length)
            lbGroups.Value := newIndex
            OnGroupSelect(lbGroups, tbHotkey, lbActions)
        } else {
            tbHotkey.Value := ""
            lbActions.Delete()
        }
    }
}

MoveGroup(lbGroups, direction) {
    global Groups
    selectedIndex := lbGroups.Value
    if (selectedIndex < 1 || selectedIndex > Groups.Length)
        return

    targetIndex := selectedIndex + direction
    if (targetIndex < 1 || targetIndex > Groups.Length)
        return

    ; Swap groups
    temp := Groups[selectedIndex]
    Groups[selectedIndex] := Groups[targetIndex]
    Groups[targetIndex] := temp

    ; Refresh list and maintain selection
    lbGroups.Delete()
    lbGroups.Add(GetGroupDisplayStrings())
    lbGroups.Value := targetIndex
}

GetGroupDisplayStrings() {
    global Groups
    displayStrings := []
    for index, group in Groups {
        firstAction := group.Sequence.Length > 0 ? group.Sequence[1] : "<empty>"
        displayStrings.Push("[" . index . "] " . group.Hotkey . " -> " . firstAction)
    }
    return displayStrings
}

SaveConfig(lbGroups, tbHotkey, lbActions, guiObj) {
    global Groups, IniFile

    ; Update currently selected group's hotkey and sync action sequence from list box
    selectedIndex := lbGroups.Value
    if (selectedIndex > 0 && selectedIndex <= Groups.Length) {
        Groups[selectedIndex].Hotkey := tbHotkey.Value

        ; ControlGetItems grabs an array of ALL strings in the ListBox control
        Groups[selectedIndex].Sequence := ControlGetItems(lbActions.Hwnd)
    }

    ; Save all groups to settings
    SaveGroups()

    ; Re-register all hotkeys with new settings
    RegisterAllHotkeys()

    guiObj.Destroy()

    ; Reload app with fresh settings applied
    Reload()
}

; --- Reusable Helper Functions (adapted from original) ---

PromptAddAction(listBoxObj, parentGui) {
    ; "+OwnDialogs" forces any sub-window/InputBox to belong to and stay on top of the parent window
    parentGui.Opt("+OwnDialogs")

    inputBoxObj := InputBox("Enter Keystroke (e.g., {Space}, !{Esc}, ^c, Hello):", "Add Action", "w300 h130")
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
    totalItems := ControlGetItems(listBoxObj.Hwnd).Length

    if (targetIndex < 1 || targetIndex > totalItems)
        return ; Out of bounds

    ; Extract items array
    items := ControlGetItems(listBoxObj.Hwnd)

    ; Swap items
    temp := items[currIndex]
    items[currIndex] := items[targetIndex]
    items[targetIndex] := temp

    ; Re-populate ListBox
    listBoxObj.Delete()
    listBoxObj.Add(items)
    listBoxObj.Value := targetIndex ; Retain focus on moved item
}

; This function is not needed - we'll use ListBox methods directly
