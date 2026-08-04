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
    ; 方式1: IMM32 (imm32.dll) を直接呼び出す。
    ; メモ帳(クラシック)やWin32の標準エディットコントロールなど、
    ; IMM32に対応しているアプリはこれで確実に切り替わる。
    hwnd := GetFocusedHwnd()
    if hwnd {
        himc := DllCall("imm32\ImmGetContext", "ptr", hwnd, "ptr")
        if himc {
            DllCall("imm32\ImmSetOpenStatus", "ptr", himc, "int", state)
            DllCall("imm32\ImmReleaseContext", "ptr", hwnd, "ptr", himc)
        }
    }

    ; 方式2: IME ON/OFF専用の仮想キー (VK_IME_ON=0x16 / VK_IME_OFF=0x1A) を送る。
    ; Chrome・Electron製アプリ・最近のUWP/WinUI3アプリ(新しいメモ帳など)は
    ; IMM32を無効化してTSFのみでIMEを扱っているため、方式1だけでは
    ; ImmGetContextがNULLを返し何も起こらない。この仮想キーはTSF側が
    ; システム全体でフック(プリザーブドキー)しているため、対象アプリが
    ; IMM32に対応していなくても切り替わる。
    SendInput(state ? "{vk16}" : "{vk1A}")
}

; "~" を付けることで Shift 本来の機能(大文字入力やShift+矢印など)は
; そのまま生かしつつ、押下時に追加でIME切り替えを行う。
~LShift::SetIME(0)
~RShift::SetIME(1)

; ============================================================
; JIS ⇔ US 記号キーのリマップ (ノートPC本体=JIS配列 / 外付け=USキーボード)
;
; Windows のキーボードレイアウト設定は常に1つ(このPCではJIS 106/109)で、
; 繋いだ物理キーボードを自動判別してはくれない。そのため US キーボードを
; つないだ状態でJISレイアウトのままだと、記号キーの印字と実際に入力される
; 文字がズレる。ここではスキャンコード(物理キー位置。レイアウトに依存しない)
; を直接フックし、US モードが有効なときだけ US キーボードの印字通りの文字を
; 送出することでズレを解消する。JISキーボードを使うときは Win+F12 で
; US モードを OFF に戻せば、素通し(=Windowsの現在のレイアウト通り)になる。
;
; 対応キー: `~ 2@ 6^ 7& 8* 9( 0) -_ =+ [{ ]} \| ;: '"
; JIS特有の 無変換/変換/かな/ろ キーはUSキーボードに物理的に存在しないため対象外。
;
; 注意: Shiftとの組み合わせのみ面倒を見ている。Ctrl+[ のような
; 制御用ショートカットは現在のOSレイアウト(JIS)通りに動作する(制限事項)。
; ============================================================

g_USMode := false

RemapKeys := [
    Map("sc", "029", "un", "``", "sh", "~"),
    Map("sc", "003", "un", "2", "sh", "@"),
    Map("sc", "007", "un", "6", "sh", "^"),
    Map("sc", "008", "un", "7", "sh", "&"),
    Map("sc", "009", "un", "8", "sh", "*"),
    Map("sc", "00A", "un", "9", "sh", "("),
    Map("sc", "00B", "un", "0", "sh", ")"),
    Map("sc", "00C", "un", "-", "sh", "_"),
    Map("sc", "00D", "un", "=", "sh", "+"),
    Map("sc", "01A", "un", "[", "sh", "{"),
    Map("sc", "01B", "un", "]", "sh", "}"),
    Map("sc", "02B", "un", "\", "sh", "|"),
    Map("sc", "027", "un", ";", "sh", ":"),
    Map("sc", "028", "un", "'", "sh", '"')
]

for k in RemapKeys
    Hotkey "sc" k["sc"], RemapHandler.Bind(k["sc"], k["un"], k["sh"])

RemapHandler(sc, un, sh, ThisHotkey) {
    global g_USMode
    if !g_USMode {
        SendInput "{sc" sc "}" ; 現在のOSレイアウト(JIS)のまま素通し
        return
    }
    if GetKeyState("Shift")
        SendText sh
    else
        SendText un
}

ToggleUSMode(*) {
    global g_USMode
    g_USMode := !g_USMode
    UpdateTrayState()
    TrayTip("キー配列", g_USMode ? "USキーボード配列モード" : "JISキーボード配列モード(通常)",)
}

#F12::ToggleUSMode()

; タスクトレイメニュー
A_TrayMenu.Delete()
A_TrayMenu.Add("Shift-IME (LShift=OFF / RShift=ON)", (*) => "")
A_TrayMenu.Disable("Shift-IME (LShift=OFF / RShift=ON)")
A_TrayMenu.Add("USキーボード配列モード (Win+F12)", ToggleUSMode)
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())
A_TrayMenu.Default := "終了"
TraySetIcon("shell32.dll", 78) ; 適当なキーボードっぽいアイコン

UpdateTrayState() {
    global g_USMode
    if g_USMode
        A_TrayMenu.Check("USキーボード配列モード (Win+F12)")
    else
        A_TrayMenu.Uncheck("USキーボード配列モード (Win+F12)")
    A_IconTip := "Shift-IME  |  " (g_USMode ? "USキーボード配列" : "JISキーボード配列")
}
UpdateTrayState()
