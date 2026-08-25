#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; 離席中もオンライン維持 (Microsoft Teams等の自動「退席中」対策)
;
; Teams は Windows の「最後に入力があった時刻」(GetLastInputInfo) を見て、
; 数分間なにも操作がないとステータスを自動的に「退席中」へ落とす。
; 逆に言えば、その時刻さえ更新され続けていれば「連絡可能」のまま保たれる。
; ここでは一定間隔でダミーのキーを送り、その時刻を更新し続ける。
;
; 設計方針
;   ・送るキーは F15。物理キーボードに存在しないキーで、文字入力にも
;     一般的なショートカットにも当たらないため、送っても何も起きない。
;     マウスカーソルを動かす方式と違い、ドラッグ中や描画ソフト上での
;     誤操作にもならない。
;   ・送るのは「直近 QUIET_TIME の間に一切入力がなかったとき」だけ。
;     操作中には割り込まないので、作業中の挙動には一切影響しない。
;
; 注意
;   ・Teams側で明示的に設定したステータス(取り込み中/退席中を手動選択、
;     会議中の自動切替)は上書きしない。あくまで「無操作による自動退席」
;     だけを防ぐ。
;   ・自分でロック(Win+L)した場合もTeamsは「退席中」になる。
; ============================================================

; ------------------------------------------------------------
; 設定
; ------------------------------------------------------------

; 監視の間隔(ms)。この周期で「無操作が続いているか」を確認する。
CHECK_INTERVAL := 60000

; 直前これだけ無操作だったらダミーキーを送る(ms)。
; CHECK_INTERVAL より少し短くしてあるので、離席中は実質 CHECK_INTERVAL ごとに
; 入力時刻が更新され、Teamsの退席判定(既定5分)には決して届かない。
QUIET_TIME := 55000

; 送出するキー。F13〜F24 は物理キーが存在せず、押しても何も起きない。
KEEPALIVE_KEY := "{F15}"

; 起動直後から有効にするか。false にすると停止状態で常駐する。
START_ENABLED := true


; ------------------------------------------------------------
; グローバルエラーハンドラ
;   未処理の例外でスクリプトごと落ちるとタスクトレイのアイコンも消え、
;   止めることも再開することもできなくなる。常駐だけは継続させる。
; ------------------------------------------------------------
OnError(OnUnhandledError)
OnUnhandledError(exc, mode) {
    TrayTip("Keep-Awake: エラーを検出しましたが継続します", exc.Message, "Icon!")
    return true
}


; ------------------------------------------------------------
; 本体
; ------------------------------------------------------------
; A_TimeIdle は GetLastInputInfo と同じ値、つまりTeamsが見ているのと同じ
; 「最後の入力からの経過時間」。自分が送ったキーでもリセットされる。
; 物理入力だけを見る A_TimeIdlePhysical ではない点に注意。ここで判定したいのは
; 「Teamsから見て無操作に見えているか」なので、A_TimeIdle が正しい。
KeepAwakeTick() {
    global QUIET_TIME, KEEPALIVE_KEY
    if (A_TimeIdle < QUIET_TIME)
        return ; 直前まで実際に操作している。割り込まない。
    SendInput(KEEPALIVE_KEY)
}

g_Enabled := false

SetEnabled(enable) {
    global g_Enabled, CHECK_INTERVAL
    g_Enabled := enable
    SetTimer(KeepAwakeTick, enable ? CHECK_INTERVAL : 0)
    UpdateTrayState()
}

Toggle(*) {
    global g_Enabled
    SetEnabled(!g_Enabled)
    TrayTip("オンライン維持", g_Enabled ? "ON (離席してもステータスを保つ)" : "OFF")
}

; 一時停止用。remap系ツールと衝突しないよう、通常の文字入力とは
; まず被らない組み合わせにしてある。
^!+k::Toggle()


; ------------------------------------------------------------
; タスクトレイ
; ------------------------------------------------------------
TRAY_LABEL_INFO := "Keep-Awake (Teamsの自動退席を防ぐ)"
TRAY_LABEL_TOGGLE := "有効 (Ctrl+Alt+Shift+K)"

A_TrayMenu.Delete()
A_TrayMenu.Add(TRAY_LABEL_INFO, (*) => "")
A_TrayMenu.Disable(TRAY_LABEL_INFO)
A_TrayMenu.Add(TRAY_LABEL_TOGGLE, Toggle)
A_TrayMenu.Add()
A_TrayMenu.Add("終了", (*) => ExitApp())
A_TrayMenu.Default := "終了"
TraySetIcon("shell32.dll", 44)

UpdateTrayState() {
    global g_Enabled, TRAY_LABEL_TOGGLE
    if g_Enabled
        A_TrayMenu.Check(TRAY_LABEL_TOGGLE)
    else
        A_TrayMenu.Uncheck(TRAY_LABEL_TOGGLE)
    A_IconTip := "Keep-Awake  |  " (g_Enabled ? "有効" : "停止中")
}

SetEnabled(START_ENABLED)
