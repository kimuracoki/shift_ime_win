#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SendMode "Input"

; ============================================================
; 左Shift = IME OFF (半角/直接入力), 右Shift = IME ON (かな入力)
;
; USキーボードでも動作するように、キーコード(仮想キー)は
; VK_LSHIFT / VK_RSHIFT に対応する AutoHotkey の LShift / RShift を
; そのまま使用する。これらはレイアウトに依存しない物理キーであり、
; 「かな」キーのような専用キーの送出は行わない。
;
; IME の ON/OFF は IMM32 (imm32.dll) の ImmSetOpenStatus を直接呼び出す
; ことで切り替える。これによりキー送信(SendInput等)に頼らないため、
; MS-IME / Google 日本語入力など IMM32 互換の IME であればレイアウトや
; アプリの言語設定に関わらず確実に動作する。
; ============================================================

; フォアグラウンドウィンドウのスレッドから、実際にフォーカスを
; 持っているコントロールのハンドルを取得する。
; (WinExist("A") はトップレベルウィンドウしか返さないため、
;  エディットコントロール等の子ウィンドウに正しく作用しない場合がある)
GetFocusedHwnd() {
    hwndActive := WinExist("A")
    if !hwndActive
        return 0

    threadId := DllCall("GetWindowThreadProcessId", "ptr", hwndActive, "ptr", 0, "uint")

    cbSize := 72 ; sizeof(GUITHREADINFO) on x64
    gti := Buffer(cbSize, 0)
    NumPut("UInt", cbSize, gti, 0)

    if DllCall("GetGUIThreadInfo", "uint", threadId, "ptr", gti.Ptr) {
        hwndFocus := NumGet(gti, 16, "ptr") ; offset of hwndFocus
        if hwndFocus
            return hwndFocus
    }

    return hwndActive
}

; state: 1 = IME ON, 0 = IME OFF
SetIME(state) {
    hwnd := GetFocusedHwnd()
    if !hwnd
        return

    himc := DllCall("imm32\ImmGetContext", "ptr", hwnd, "ptr")
    if himc {
        DllCall("imm32\ImmSetOpenStatus", "ptr", himc, "int", state)
        DllCall("imm32\ImmReleaseContext", "ptr", hwnd, "ptr", himc)
    }
}

; "~" を付けることで Shift 本来の機能(大文字入力やShift+矢印など)は
; そのまま生かしつつ、押下時に追加でIME切り替えを行う。
~LShift::SetIME(0)
~RShift::SetIME(1)

; タスクトレイメニューに簡単な表示を出す
A_TrayMenu.Delete()
A_TrayMenu.Add("Shift-IME (LShift=OFF / RShift=ON)", (*) => "")
A_TrayMenu.Disable("Shift-IME (LShift=OFF / RShift=ON)")
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())
A_TrayMenu.Default := "終了"
TraySetIcon("shell32.dll", 78) ; 適当なキーボードっぽいアイコン
