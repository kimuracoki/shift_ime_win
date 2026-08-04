# Shift IME Toggle + JIS/US配列リマップ (Win11 / AutoHotkey v2)

左Shiftキーを押すとIMEオフ（半角/直接入力）、右Shiftキーを押すとIMEオン（かな入力）に切り替える常駐ツールです。
USキーボードでも動作します。あわせて、JIS配列ノートPC本体とUSキーボードを併用する場合向けに、
`Win+F12` で記号キーの配列をJIS⇔USに切り替えるリマップ機能も入っています。

## 前提となる使い方

Windowsの「入力方式」は**日本語IME1本だけ**を使う想定です（英語入力用に別の入力方式へ切り替える運用ではない）。
日本語IMEを開いたまま英字を打つ・閉じて直接入力する、をShiftキーで行き来するイメージです。
英語入力用に「English(US)」など別の入力方式に切り替えて使っている場合、切り替え中はIME自体が存在しないため
このツールのIME ON/OFFは効きません（その場合は別方式の検討が必要です）。

## 仕組み

### 1. Shift IME切り替え
- `LShift` / `RShift` は AutoHotkey が仮想キー（VK_LSHIFT / VK_RSHIFT）で判定するため、
  物理キーボードの配列（US/JIS）に依存しません。専用の「かな」キーは一切使いません。
- IMEのON/OFFはキー送信ではなく、`imm32.dll` の `ImmSetOpenStatus` をAPIで直接呼び出して
  切り替えています。MS-IME・Google 日本語入力など IMM32 互換のIMEであれば、
  アプリやキーボード設定に関係なく確実に効きます。
- ホットキーには `~` を付けているため、Shiftキー本来の機能（大文字入力、Shift+矢印など）は
  そのまま生きたまま、追加でIME切り替えが発動します。
- フォーカスのある子コントロール（エディットボックス等）を `GetGUIThreadInfo` で正確に取得してから
  IME状態を切り替えるため、ウィンドウによって効かないという問題が起きにくくなっています。

### 2. JIS ⇔ US 記号キーリマップ（`Win + F12` でトグル）
- Windowsのキーボードレイアウト設定は常に1つ（このPCではJIS 106/109）で、繋いだ物理キーボードを
  自動判別しません。そのためUSキーボードを繋いだままJISレイアウト設定だと、記号キー
  （`` ` `` `2@` `6^` `7&` `8*` `9(` `0)` `-_` `=+` `[{` `]}` `\|` `;:` `'"`）の印字と実際に
  入力される文字がズレます。
- スキャンコード（物理キー位置。レイアウトに依存しない）を直接フックし、USモードが有効なときだけ
  USキーボードの印字通りの文字を送出することでズレを解消します。
- デフォルトはOFF（JIS配列＝ノートPC本体のキーボード用）。USキーボードを接続したら `Win+F12` でON、
  外して本体キーボードに戻すときはもう一度 `Win+F12` でOFFにしてください。タスクトレイのメニューからも
  ON/OFFを切り替えられ、現在の状態はメニューのチェック印とアイコンのツールチップで確認できます。
- 制限事項: Shiftとの組み合わせのみ対応しています。`Ctrl+[` のような制御用ショートカットは
  現在のOSレイアウト（JIS）通りに動作します。JIS特有の「無変換/変換/かな/ろ」キーはUSキーボードに
  物理的に存在しないため対象外です。

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
