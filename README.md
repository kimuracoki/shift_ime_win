# Shift IME Toggle (Win11 / AutoHotkey v2)

左Shiftキーを押すとIMEオフ（半角/直接入力）、右Shiftキーを押すとIMEオン（かな入力）に切り替える常駐ツールです。
USキーボードでも動作します。

## 仕組み

- `LShift` / `RShift` は AutoHotkey が仮想キー（VK_LSHIFT / VK_RSHIFT）で判定するため、
  物理キーボードの配列（US/JIS）に依存しません。専用の「かな」キーは一切使いません。
- IMEのON/OFFはキー送信ではなく、`imm32.dll` の `ImmSetOpenStatus` をAPIで直接呼び出して
  切り替えています。MS-IME・Google 日本語入力など IMM32 互換のIMEであれば、
  アプリやキーボード設定に関係なく確実に効きます。
- ホットキーには `~` を付けているため、Shiftキー本来の機能（大文字入力、Shift+矢印など）は
  そのまま生きたまま、追加でIME切り替えが発動します。
- フォーカスのある子コントロール（エディットボックス等）を `GetGUIThreadInfo` で正確に取得してから
  IME状態を切り替えるため、ウィンドウによって効かないという問題が起きにくくなっています。

## ファイル

- `shift_ime.ahk` … AutoHotkey v2 ソースコード
- `shift_ime.exe` … コンパイル済み実行ファイル（そのまま実行可能、AutoHotkeyのインストール不要）

## 使い方

`shift_ime.exe` をダブルクリックするだけで常駐します。タスクトレイのアイコンから「終了」を選ぶと終了します。

## Windows起動時に自動実行したい場合

1. `Win + R` → `shell:startup` → Enter でスタートアップフォルダを開く
2. `shift_ime.exe` のショートカットをそのフォルダに置く

## ソースを変更した場合の再コンパイル方法

AutoHotkey v2 と Ahk2Exe コンパイラがインストール済みであれば、以下で再コンパイルできます。

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\Compiler\Ahk2Exe.exe" `
  /in "shift_ime.ahk" `
  /out "shift_ime.exe" `
  /base "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe"
```

(このセットアップでは `winget install AutoHotkey.AutoHotkey` でAutoHotkey v2本体を、
GitHubの [AutoHotkey/Ahk2Exe](https://github.com/AutoHotkey/Ahk2Exe) releases から
コンパイラ本体をそれぞれ導入済みです。)
