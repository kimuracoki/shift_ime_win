#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SendMode "Input"

; ------------------------------------------------------------
; グローバルエラーハンドラ
;   未処理の例外が起きると、AutoHotkey v2は既定でスクリプトごと
;   終了してしまう。そうなるとタスクトレイのアイコンも消え、
;   終了ホットキーも効かなくなり、「入力もできず終了もできない」
;   最悪の状態になる。想定外のキー入力パターンなどで万一例外が
;   発生しても常駐だけは継続するよう、ここで一律に握りつぶす。
; ------------------------------------------------------------
OnError(OnUnhandledError)
OnUnhandledError(exc, mode) {
    TrayTip("Shift-IME: エラーを検出しましたが継続します", exc.Message, "Icon!")
    return true ; trueを返すと既定のエラーダイアログ表示とスクリプト終了を抑止する
}

; ============================================================
; 概要
;   ・左Shiftを単体でタップ → IME OFF (直接入力)
;   ・右Shiftを単体でタップ → IME ON  (かな入力)
;   ・Shiftを他のキーと組み合わせて使った場合(大文字入力、Shift+2など)は
;     IME切り替えは一切発生しない。Shift本来の修飾キーとしての動作のみ。
;   ・USキーボード接続時、Win+F12でJIS⇔US記号キー配列を切り替え可能。
;
; USキーボードでも動作する理由
;   LShift/RShiftや各記号キーはすべて「物理キー位置」で判定しており
;   (仮想キー、またはスキャンコード)、Windowsのキーボードレイアウト設定
;   (JIS/US)には依存しない。
; ============================================================


; ------------------------------------------------------------
; IME ON/OFF
; ------------------------------------------------------------
; state: true = ON(かな入力) / false = OFF(直接入力)
SetIME(state) {
    ; 方式1: IMM32 (imm32.dll) を直接呼び出す。
    ; メモ帳(クラシック)やWin32標準のエディットコントロールなど、
    ; IMM32に対応しているアプリはこれで確実に切り替わる。
    hwnd := GetFocusedHwnd()
    if hwnd {
        himc := DllCall("imm32\ImmGetContext", "ptr", hwnd, "ptr")
        if himc {
            DllCall("imm32\ImmSetOpenStatus", "ptr", himc, "int", state)
            DllCall("imm32\ImmReleaseContext", "ptr", hwnd, "ptr", himc)
        }
    }

    ; 方式2: IME ON/OFF専用の仮想キー (VK_IME_ON=0x16 / VK_IME_OFF=0x1A)。
    ; Chrome・Electron製アプリ・最近のUWP/WinUI3アプリ(新しいメモ帳など)は
    ; IMM32を無効化しTSFのみでIMEを扱うため方式1だけでは効かない。
    ; この仮想キーはTSF側がシステム全体でフックしているため、
    ; 対象アプリがIMM32非対応でも切り替わる。
    SendInput(state ? "{vk16}" : "{vk1A}")
}

; フォアグラウンドウィンドウの、実際にフォーカスを持っている
; コントロールのハンドルを取得する。
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


; ------------------------------------------------------------
; Shift単体タップの検出
;   Shiftが「押されてから離されるまでの間に、他のどれかのキーが
;   使われたか」を記録し、使われていなければ単体タップとみなす。
;   他のキーが使われた場合は、Shift本来の修飾キー動作のみを行い
;   IME切り替えは発生させない。
; ------------------------------------------------------------
g_LShiftUsedAsModifier := false
g_RShiftUsedAsModifier := false

; Shift以外の何らかのキーが押されたときに呼ぶ。
; そのとき押されている側のShiftを「修飾キーとして使った」ことにする。
NoteShiftUsedAsModifier() {
    global g_LShiftUsedAsModifier, g_RShiftUsedAsModifier
    if GetKeyState("LShift", "P")
        g_LShiftUsedAsModifier := true
    if GetKeyState("RShift", "P")
        g_RShiftUsedAsModifier := true
}

OnLShiftDown() {
    global g_LShiftUsedAsModifier
    g_LShiftUsedAsModifier := false
}
OnRShiftDown() {
    global g_RShiftUsedAsModifier
    g_RShiftUsedAsModifier := false
}

OnLShiftUp() {
    global g_LShiftUsedAsModifier
    if !g_LShiftUsedAsModifier
        SetIME(false)
}
OnRShiftUp() {
    global g_RShiftUsedAsModifier
    if !g_RShiftUsedAsModifier
        SetIME(true)
}

; "~" を付けることで Shift 本来の機能(大文字入力、Shift+矢印など)は
; そのまま生かしつつ、追加で上記の状態管理を行う。
~LShift::OnLShiftDown()
~RShift::OnRShiftDown()
~LShift Up::OnLShiftUp()
~RShift Up::OnRShiftUp()


; ------------------------------------------------------------
; JIS ⇔ US 記号キーのリマップ (ノートPC本体=JIS配列 / 外付け=USキーボード)
;
; Windowsのキーボードレイアウト設定は常に1つ(このPCではJIS 106/109)で、
; 繋いだ物理キーボードを自動判別してはくれない。そのためUSキーボードを
; つないだ状態でJISレイアウトのままだと、記号キーの印字と実際に入力される
; 文字がズレる。ここではスキャンコード(物理キー位置。レイアウトに依存しない)
; を直接フックし、USモードが有効なときだけUSキーボードの印字通りの文字を
; 送出することでズレを解消する。JISキーボードを使うときはWin+F12で
; USモードをOFFに戻せば、素通し(=Windowsの現在のレイアウト通り)になる。
;
; 対応キー: `~ 2@ 6^ 7& 8* 9( 0) -_ =+ [{ ]} \| ;: '"
; JIS特有の 無変換/変換/かな/ろ キーはUSキーボードに物理的に存在しないため対象外。
;
; 注意: Shiftとの組み合わせのみ面倒を見ている。Ctrl+[ のような
; 制御用ショートカットは現在のOSレイアウト(JIS)通りに動作する(制限事項)。
; ------------------------------------------------------------
g_USMode := true

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

; "*" を付けることで、Shiftなど他の修飾キーが同時に押されていても
; (押されていなくても)確実に発火するようにする。
; これを付けないと「他の修飾キーが一切押されていない状態」でしか
; 発火せず、Shiftと組み合わせた記号入力(Shift+2 → @ など)が
; 一切反応しなくなる。
for k in RemapKeys
    Hotkey "*sc" k["sc"], RemapHandler.Bind(k["sc"], k["un"], k["sh"])

; NOTE: ThisHotkeyは "*sc029" のようにHotkeyコマンドに渡した文字列が
; そのまま("*"付きで)渡ってくるため、{ThisHotkey}の形でSendに渡すと
; 無効なキー名としてランタイムエラーになる(=該当キーが一切入力できなくなる)。
; そのため素通し用のスキャンコードはBindで明示的に渡す。
RemapHandler(sc, un, sh, ThisHotkey) {
    global g_USMode

    NoteShiftUsedAsModifier() ; このキーが押された時点でShiftは修飾キー扱いにする

    shiftDown := GetKeyState("Shift", "P")

    if !g_USMode {
        ; 現在のOSレイアウト(JIS)のまま素通しさせる。
        ; {Blind} を付け、今押されている修飾キー(Shiftなど)の状態を
        ; 暗黙の挙動に頼らず明示的にそのまま維持して送る。
        SendInput "{Blind}{sc" sc "}"
        return
    }

    SendAsRealKey(shiftDown ? sh : un)
}

; targetChar を「今のキーボードレイアウト(JIS)でその文字を打つには
; 本来どのキーをどのShift状態で押すか」に変換し、そのキー入力として送る。
;
; SendText(文字を直接流し込む方式)は手軽だが、Windowsの通常の入力経路
; (キーボードレイアウト変換 → IME/TSF)を素通りしてしまうため、IMEが
; 変換中の文字列を保持している場合などに正しく振る舞わないことがある。
; ここでは VkKeyScanExW で「その文字を生成する実際のキー」を調べ、
; 本物のキー入力と同じ経路(SendInputでVKコードを送る)で送ることで、
; IME/TSFに正しく通るようにする。
SendAsRealKey(char) {
    hkl := GetForegroundKeyboardLayout()
    packed := DllCall("VkKeyScanExW", "ushort", Ord(char), "ptr", hkl, "short")

    ; -1: 現在のレイアウトではそもそも生成できない文字
    ; Shift以外の修飾(Ctrl/Altなど)が必要な場合も非対応。
    ; どちらの場合も安全側に倒し、文字を直接流し込むフォールバックにする。
    if (packed = -1 || ((packed >> 8) & 0xFF) > 1) {
        SendText(char)
        return
    }

    vk := packed & 0xFF
    needShift := (packed >> 8) & 1

    Send(needShift ? "{Shift down}" : "{Shift up}")
    Send("{vk" Format("{:X}", vk) "}")
    ; 合成イベントでずらしたShiftの論理状態を、実際の物理状態に戻す。
    ; ("P"モードは常に本物の物理状態を返すため、Shift+2のように
    ;  ユーザーがまだ物理的にShiftを押しっぱなしのケースでも正しく戻る)
    Send(GetKeyState("Shift", "P") ? "{Shift down}" : "{Shift up}")
}

GetForegroundKeyboardLayout() {
    hwnd := WinExist("A")
    if !hwnd
        return DllCall("GetKeyboardLayout", "uint", 0, "ptr")
    threadId := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    return DllCall("GetKeyboardLayout", "uint", threadId, "ptr")
}


; ------------------------------------------------------------
; US配列モードのトグル (Win+F12)
; ------------------------------------------------------------
ToggleUSMode(*) {
    global g_USMode
    g_USMode := !g_USMode
    UpdateTrayState()
    TrayTip("キー配列", g_USMode ? "USキーボード配列モード" : "JISキーボード配列モード(通常)")
}

; ノートPC本体キーボードはFnキーを押さないとF12が反応しない機種があるため、
; 念のため別系統のホットキーも用意しておく。どちらでも切り替え可能。
#F12::ToggleUSMode()
^!u::ToggleUSMode()


; ------------------------------------------------------------
; 緊急終了ホットキー
;   タスクトレイのアイコンは通知領域の「隠れているインジケーター」に
;   格納され気づきにくいことがあるため、万が一入力がおかしくなった
;   ときにトレイアイコンを探さなくても確実に終了できる手段を用意する。
;   remap対象のキー(数字/記号キー)は使わず、通常の文字入力とは
;   まず衝突しない組み合わせにしてある。
; ------------------------------------------------------------
^!+F12::ExitApp()


; ------------------------------------------------------------
; タスクトレイ
; ------------------------------------------------------------
TRAY_LABEL_INFO := "Shift-IME (LShift=OFF / RShift=ON)"
TRAY_LABEL_USMODE := "USキーボード配列モード (Win+F12)"
TRAY_LABEL_EMERGENCY := "緊急終了: Ctrl+Alt+Shift+F12"

A_TrayMenu.Delete()
A_TrayMenu.Add(TRAY_LABEL_INFO, (*) => "")
A_TrayMenu.Disable(TRAY_LABEL_INFO)
A_TrayMenu.Add(TRAY_LABEL_EMERGENCY, (*) => "")
A_TrayMenu.Disable(TRAY_LABEL_EMERGENCY)
A_TrayMenu.Add(TRAY_LABEL_USMODE, ToggleUSMode)
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())
A_TrayMenu.Default := "終了"
TraySetIcon("shell32.dll", 78)

UpdateTrayState() {
    global g_USMode
    if g_USMode
        A_TrayMenu.Check(TRAY_LABEL_USMODE)
    else
        A_TrayMenu.Uncheck(TRAY_LABEL_USMODE)
    A_IconTip := "Shift-IME  |  " (g_USMode ? "USキーボード配列" : "JISキーボード配列")
}
UpdateTrayState()
