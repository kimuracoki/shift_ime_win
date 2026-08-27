#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SendMode "Input"

; 既定のIMEウィンドウ(下の IME_Wnd を参照)は隠しウィンドウなので、
; SendMessage で掴むために必要。
DetectHiddenWindows true

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
;     (IMEがONの間はMS-IME自身がUS配列として解釈するため、リマップはしない)
;   ・Warpで「IMEがONのとき」に限り jk → IME OFF + Esc。
;     (nvimの inoremap jk <Esc> はIMEがONだとjもkもIMEに吸われて届かないため)
;
; USキーボードでも動作する理由
;   LShift/RShiftや各記号キーはすべて「物理キー位置」で判定しており
;   (仮想キー、またはスキャンコード)、Windowsのキーボードレイアウト設定
;   (JIS/US)には依存しない。
; ============================================================


; ------------------------------------------------------------
; IME ON/OFF
; ------------------------------------------------------------
; IMEの状態は「既定のIMEウィンドウ」に WM_IME_CONTROL を送って読み書きする。
; これは定番ライブラリ IME.ahk と同じ方式。
;
; ImmGetOpenStatus / ImmSetOpenStatus を直接呼ぶ方式は、IMM32を無効化して
; TSFだけでIMEを扱うアプリ(Warp、Chrome、WinUI3系など)には効かない。
; 実測(Warp): ImmGetContext は 0 を返し状態を読めない。一方
; ImmGetDefaultIMEWnd + IMC_GETOPENSTATUS は正しい値を返す。
; 既定のIMEウィンドウはスレッドごとに必ず作られるため、この経路なら
; IMM32非対応のアプリでも読み書きが通る。
WM_IME_CONTROL := 0x0283
IMC_GETOPENSTATUS := 0x0005
IMC_SETOPENSTATUS := 0x0006

; フォーカスのあるコントロールが属するスレッドの、既定のIMEウィンドウ。
IME_Wnd() {
    hwnd := GetFocusedHwnd()
    if !hwnd
        return 0
    return DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr")
}

; IMEがONなら true / OFFなら false / 取得できなければ "" を返す。
IME_Get(timeoutMs := 1000) {
    global WM_IME_CONTROL, IMC_GETOPENSTATUS

    imeWnd := IME_Wnd()
    if !imeWnd
        return ""
    try
        return SendMessage(WM_IME_CONTROL, IMC_GETOPENSTATUS, 0, , "ahk_id " imeWnd, , , , timeoutMs) ? true : false
    catch ; 相手が応答しない(ハング中など)
        return ""
}

; 切り替えられたら true。
IME_Set(state) {
    global WM_IME_CONTROL, IMC_SETOPENSTATUS

    imeWnd := IME_Wnd()
    if !imeWnd
        return false
    try
        SendMessage(WM_IME_CONTROL, IMC_SETOPENSTATUS, state ? 1 : 0, , "ahk_id " imeWnd, , , , 1000)
    catch
        return false
    return true
}

; state: true = ON(かな入力) / false = OFF(直接入力)
;
; 戻り値は「同期メッセージで切り替えたか」。true なら、戻った時点で
; 既に切り替わっていることが保証される。false(仮想キーへのフォールバック)の
; ときだけ、後続処理は反映を待つ必要がある。
SetIME(state) {
    if IME_Set(state) {
        InvalidateIMECache()
        return true
    }

    ; フォールバック: IME ON/OFF専用の仮想キー (VK_IME_ON=0x16 / VK_IME_OFF=0x1A)。
    ; 既定のIMEウィンドウが取れないアプリのための保険。
    SendInput(state ? "{vk16}" : "{vk1A}")
    InvalidateIMECache()
    return false
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
;   使われたか」を判定し、使われていなければ単体タップとみなす。
;   他のキーが使われた場合は、Shift本来の修飾キー動作のみを行い
;   IME切り替えは発生させない。
;
;   判定は2本立てにしている。
;     (1) A_PriorKey
;         「Shiftを離す直前に押されていたキー」。それがShift自身なら
;         単体タップ、それ以外(a や Left など)なら修飾キーとして
;         使われたことになる。英字キーやShift+矢印もこれで拾える。
;     (2) g_L/RShiftUsedAsModifier フラグ
;         リマップ対象の記号キー(RemapHandler)は自前でキーを送出する
;         ため、A_PriorKeyが送出したキー側で上書きされて紛れやすい。
;         そのため記号キー側は押された時点で明示的にフラグを立てる。
;
;   NOTE: 以前は (2) のフラグだけで判定していたが、フラグを立てるのは
;   RemapHandler(記号キー)だけだったため、Shiftを押しながら英字を打つと
;   「単体タップ」と誤判定されていた。結果、右Shiftで大文字を打つたびに
;   IMEがONになっていた。(1) を足してこれを塞いでいる。
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
    if (!g_LShiftUsedAsModifier && A_PriorKey = "LShift")
        SetIME(false)
}
OnRShiftUp() {
    global g_RShiftUsedAsModifier
    if (!g_RShiftUsedAsModifier && A_PriorKey = "RShift")
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
; ただし、IMEがONの間はこのリマップを行わず素通しさせる。MS-IMEは、IMEがONの
; ときだけキーをスキャンコード(物理キー位置)から自前でUS配列として解釈するため、
; 何もしなくても既にUSキーボードの印字どおりの記号が出るからである。
; そこにこちらの変換を重ねると二重変換になり、キー1つ分ズレた記号が出る
; (@ を押すと 「、[ を押すと 」 など)。詳細は RemapHandler のコメントを参照。
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

    ; 素通しさせる条件は2つ。どちらも「今このキーは、こちらが手を出さなくても
    ; 印字どおりの文字になる」状態。
    ;
    ;   (1) USモードOFF: ノートPC本体のJISキーボードを使っている。
    ;       現在のOSレイアウト(JIS)のまま素通しさせる。
    ;
    ;   (2) IMEがON: MS-IMEは、IMEがONの間だけキーをスキャンコード(物理キー位置)
    ;       から自前でUS配列として解釈する。つまりIME ONの間は、こちらが何もしなくても
    ;       既にUSキーボードの印字どおりの記号が出る。
    ;       (実測: IME ON + 素通しで sc01A → 「、Shift+sc003 → ＠。US印字どおり。
    ;        メモ帳・ブラウザでも同じなのでアプリ固有ではなくMS-IME全体の挙動)
    ;       ここで下の SendAsRealKey まで通してしまうと、
    ;         こちら: 文字 → 「JIS配列でその文字を打つキー」に変換して送出
    ;         IME側 : 送られたキーを「US配列」として解釈し直す
    ;       と二重変換になり、キー1つ分ズレた記号が出る
    ;       (@ を押すと 「、[ を押すと 」 など)。
    ;
    ; NOTE: IMEがOFFのときは逆に、OSのレイアウト(JIS)でVKから文字が決まるため
    ; SendAsRealKey による変換が必要になる。IMEのON/OFFで必要な処理が正反対に
    ; なるので、状態を見ずに片方だけを選ぶことはできない。
    if (!g_USMode || IsIMEOn()) {
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
; jk で Esc + IME OFF (nvim 用)
;
; nvim 側には inoremap jk <Esc> があるが、IMEがONの間は j も k も
; IMEに吸われてローマ字変換バッファに入ってしまい、nvimまで届かない。
; そのため「IMEがONのときだけ」AHK側で jk を横取りし、
; IMEをOFFにしてから Esc をnvimに送る。
;
; 設計方針
;   ・IMEがOFFのときは一切介入しない。nvim側の jk マッピングがそのまま
;     効くし、ノーマルモードの j 移動にも遅延が出ない。
;   ・対象プロセス(既定はWarp)以外でも介入しない。日本語入力の
;     「じゃ/じゅ/じょ」等に余計な遅延と誤爆を持ち込まないため。
;   ・nvimかシェルかまでは区別しない。Warpのウィンドウタイトルは
;     Warpが独自に付けていて動いているプログラムを表さないため、
;     AHK側だけでは判別できない。日本語のローマ字入力で jk が並ぶことは
;     まずないので、シェル側での誤爆は実害が出ない範囲とみなす。
;   ・j は押された時点では送らずに保留し、続く1キーを見てから判断する。
;     k なら Esc、それ以外なら「j → そのキー」の順で改めて送出する。
;     先に j を通してしまうとIMEの変換バッファに ｊ が残り、
;     後から消す手段が不確実になるので、必ず保留してから判断する。
; ------------------------------------------------------------

; 対象プロセス。ここに exe 名を足せば他のターミナル/エディタでも有効になる。
; 例: JK_TARGET_PROCESSES := ["warp.exe", "WindowsTerminal.exe", "neovide.exe"]
JK_TARGET_PROCESSES := ["warp.exe"]

; j を押してから k を待つ猶予(ミリ秒)。
; nvim側の timeoutlen (このPCでは300) と揃えてある。
JK_TIMEOUT := 300

; SetIME() が仮想キー送出にフォールバックしたときだけ、反映を待つ時間。
; 同期メッセージで切り替えられた場合は待つ必要がない。
JK_IME_OFF_FALLBACK_DELAY := 20

; スキャンコード(物理キー位置)で指定する。US/JISどちらのレイアウト設定でも
; 同じ物理キーを指す。sc024 = j / sc025 = k。
JK_SC_J := "sc024"
JK_SC_K := "sc025"

; 押しっぱなしの状態そのものに意味があるキー。保留中も止めずに素通しし、
; 「次に押されたキー」としても数えない。
JK_MODIFIER_KEYS := "{LShift}{RShift}{LControl}{RControl}{LAlt}{RAlt}{LWin}{RWin}"


IsJkTargetWindow() {
    global JK_TARGET_PROCESSES
    try
        proc := WinGetProcessName("A")
    catch
        return false
    for p in JK_TARGET_PROCESSES
        if (proc = p) ; AHKの = は大文字小文字を区別しない
            return true
    return false
}

; IMEがONかどうか。状態が取れないときは介入しない側に倒す。
;
; これは #HotIf から、つまりキーボードフックの経路から毎回呼ばれる。
; IME_Get() はプロセス間の同期メッセージなので、相手(ターミナル)が
; メッセージを処理できない状態だと、その間キー入力全体が止まる。
; Windows全体が固まって見えるので、ここでは
;   ・問い合わせのタイムアウトを短くする
;   ・直近の結果をごく短時間だけ使い回す
; の両方で、1キーあたりの最悪待ち時間を抑える。
IME_QUERY_TIMEOUT := 100 ; ms
IME_CACHE_TTL := 50      ; ms

g_ImeCachedAt := 0
g_ImeCached := false

; 自分でIMEを切り替えたときは、次の問い合わせを必ず実測させる。
InvalidateIMECache() {
    global g_ImeCachedAt
    g_ImeCachedAt := 0
}

IsIMEOn() {
    global g_ImeCachedAt, g_ImeCached, IME_QUERY_TIMEOUT, IME_CACHE_TTL

    if (g_ImeCachedAt && A_TickCount - g_ImeCachedAt <= IME_CACHE_TTL)
        return g_ImeCached

    g_ImeCached := (IME_Get(IME_QUERY_TIMEOUT) = true)
    g_ImeCachedAt := A_TickCount
    return g_ImeCached
}

; 判定は軽い順に並べる(ウィンドウ → IME)。
#HotIf IsJkTargetWindow() && IsIMEOn()
; 修飾キーなしの j のみ。Shift+J や Ctrl+J は素通しさせたいので "*" は付けない。
sc024::HandleJ()
#HotIf

HandleJ() {
    global JK_TIMEOUT, JK_SC_J, JK_SC_K

    loop {
        next := WaitNextKey(JK_TIMEOUT)

        ; 時間切れ。ただの j だったので送る。
        if !next {
            ReplayKey(JK_SC_J)
            return
        }

        ; jk 成立
        if (next = JK_SC_K) {
            EscapeFromIME()
            return
        }

        ; jk ではなかった。保留していた j を先に送り、入力順を保つ。
        ReplayKey(JK_SC_J)

        ; "jj" の2つ目は、次が k なら jk として成立させたいので再び保留する。
        if (next = JK_SC_J)
            continue

        ReplayKey(next)
        return
    }
}

; j を保留している間、次の「修飾キー以外のキー」をひとつ待つ。
;
; 待っている間のキーはすべてこちらで止める(S)。止めないと、保留中の j より
; 先にアプリへ届いて入力順が入れ替わる。例外は修飾キーで、これは押されている
; 状態そのものに意味があるため素通しし、「次のキー」としても数えずに待ち続ける。
;
; 戻り値: "sc025" のようなスキャンコード文字列。時間切れなら 0。
g_JkNextKey := 0

WaitNextKey(timeoutMs) {
    global g_JkNextKey, JK_MODIFIER_KEYS

    g_JkNextKey := 0

    ih := InputHook("L0 T" (timeoutMs / 1000)) ; L0: 文字は集めない。通知だけ使う
    ih.KeyOpt("{All}", "NS")                   ; N=通知する / S=アプリへ通さない
    ih.KeyOpt(JK_MODIFIER_KEYS, "-S")          ; 修飾キーだけは素通し
    ih.OnKeyDown := OnJkWaitKey
    ih.Start()
    ih.Wait()

    return g_JkNextKey
}

OnJkWaitKey(hook, vk, sc) {
    global g_JkNextKey

    if IsModifierVK(vk)
        return

    g_JkNextKey := Format("sc{:03X}", sc)
    hook.Stop()
}

IsModifierVK(vk) {
    static mods := Map(
        0x10, true, 0x11, true, 0x12, true, ; Shift / Ctrl / Alt (左右不問)
        0xA0, true, 0xA1, true,             ; LShift / RShift
        0xA2, true, 0xA3, true,             ; LCtrl / RCtrl
        0xA4, true, 0xA5, true,             ; LAlt / RAlt
        0x5B, true, 0x5C, true)             ; LWin / RWin
    return mods.Has(vk)
}

; 物理キー位置(スキャンコード)そのままで送り直す。
; {Blind} を付けるのは、今押されている修飾キーをAHKが勝手に上げ下げせず、
; ユーザーが押している状態のまま適用させるため。
ReplayKey(sc) {
    SendInput("{Blind}{" sc "}")
}

EscapeFromIME() {
    global JK_IME_OFF_FALLBACK_DELAY

    ; 先にIMEをOFFにする。変換中の文字列が残っている場合、先にEscを送ると
    ; IMEがEscを食って変換を取り消してしまうため、必ずOFFを先に行う。
    if !SetIME(false)
        Sleep(JK_IME_OFF_FALLBACK_DELAY) ; 仮想キー送出は非同期なので反映を待つ

    SendInput("{Escape}")
}

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
TRAY_LABEL_JK := "jk = Esc + IME OFF (IME ON時 / Warp)"
TRAY_LABEL_EMERGENCY := "緊急終了: Ctrl+Alt+Shift+F12"

A_TrayMenu.Delete()
A_TrayMenu.Add(TRAY_LABEL_INFO, (*) => "")
A_TrayMenu.Disable(TRAY_LABEL_INFO)
A_TrayMenu.Add(TRAY_LABEL_JK, (*) => "")
A_TrayMenu.Disable(TRAY_LABEL_JK)
A_TrayMenu.Add(TRAY_LABEL_EMERGENCY, (*) => "")
A_TrayMenu.Disable(TRAY_LABEL_EMERGENCY)
A_TrayMenu.Add(TRAY_LABEL_USMODE, ToggleUSMode)
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())
A_TrayMenu.Default := "終了"
TraySetIcon("shell32.dll", 174)

UpdateTrayState() {
    global g_USMode
    if g_USMode
        A_TrayMenu.Check(TRAY_LABEL_USMODE)
    else
        A_TrayMenu.Uncheck(TRAY_LABEL_USMODE)
    A_IconTip := "Shift-IME  |  " (g_USMode ? "USキーボード配列" : "JISキーボード配列")
}
UpdateTrayState()
