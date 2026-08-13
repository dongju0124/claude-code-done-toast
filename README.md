# claude-code-done-toast

A desktop toast notification for [Claude Code](https://claude.com/claude-code) on **Windows**.
When Claude finishes a turn, a small card slides into the bottom-right corner of your screen.
Click it and your Claude Code terminal comes back to the front.

> **Windows only.** It is a single PowerShell script using WinForms and a few `user32.dll` calls.
> Most notification-hook examples out there are macOS-flavoured (`osascript`, `afplay`); this is the Windows counterpart.

## Why

Claude Code often runs for minutes at a time. You alt-tab away, start reading something else,
and then forget to check whether it finished. A toast fixes that — without dragging you
out of whatever you are typing.

Three details make it usable rather than annoying:

- **It never steals focus.** The window is created with `WS_EX_NOACTIVATE`, so it appears without
  taking keyboard focus from the app you are in.
- **Clicking it takes you back.** It walks the parent process chain to find the terminal
  hosting the session (Windows Terminal, conhost, WezTerm, VS Code, …), restores it if minimised,
  and raises it — working around the foreground-lock rules via `AttachThreadInput`.
- **It stacks.** Run several sessions at once and the toasts pile upward instead of overlapping.

## Install

### Automatic

```powershell
git clone https://github.com/dongju0124/claude-code-done-toast.git
cd claude-code-done-toast
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

This copies the script to `%USERPROFILE%\.claude\hooks\` and adds the `Stop` hook to your
`settings.json`. Existing settings are preserved and a timestamped `.bak` is written first.
Running it twice is safe — it replaces its own entry rather than piling up duplicates.

Restart Claude Code afterwards.

To remove everything again:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

### Manual

1. Copy `done-toast.ps1` to `%USERPROFILE%\.claude\hooks\`.
2. Merge the block below into `%USERPROFILE%\.claude\settings.json`, replacing `<YourName>`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:/Users/<YourName>/.claude/hooks/done-toast.ps1\"",
            "async": true
          }
        ]
      }
    ]
  }
}
```

Use forward slashes in the path — it avoids backslash-escaping problems inside JSON.

> **`"async": true` is not optional.** The toast stays on screen until clicked, so without
> `async` Claude Code would block on every single turn waiting for the hook to exit.

## Configuration

Everything worth changing sits near the top of `done-toast.ps1`.

| What | Where | Notes |
| --- | --- | --- |
| Auto-dismiss | `$DISMISS_MS` (line 6) | `0` keeps it up until clicked. Set `5000` for a 5-second toast. |
| Body text | `$bCodes` (line 12) | Currently Korean for "작업 완료" (*work complete*). |
| Accent bar colour | `$accent.BackColor` | Defaults to Claude orange, `RGB(216,122,87)`. |
| Card size / position | `$form.Width` / `$form.Height` / `$form.Left` / `$form.Top` | Anchored to the working area of whichever monitor the mouse is on. |

### About that `$bCodes` line

The body text is built from Unicode code points rather than written literally:

```powershell
$bCodes = 0xC791,0xC5C5,0x20,0xC644,0xB8CC   # "작업 완료"
$bodyText = -join ($bCodes | ForEach-Object { [char]$_ })
```

That looks odd, and it is deliberate. Windows PowerShell 5.1 reads a `.ps1` with no byte-order
mark as ANSI in the system code page, so non-ASCII string literals turn to mojibake on machines
whose locale differs from the author's. Code points sidestep the encoding entirely.

If your text is plain ASCII, just write it normally:

```powershell
$bodyText = 'Done'
```

For anything else, convert each character to `0xXXXX` and keep the existing form. Any online
"unicode code point converter" will do it.

## How it works

Claude Code fires the [`Stop` hook](https://docs.claude.com/en/docs/claude-code/hooks) when it
finishes responding. The hook runs `done-toast.ps1`, which:

1. Drains the hook payload from stdin (unused, but it must be consumed).
2. Counts existing windows titled `ClaudeCodeToast` to work out the vertical offset.
3. Builds a borderless top-most `Form` subclassed to suppress activation.
4. On click, resolves the session's terminal window and raises it, then closes.

The terminal lookup tries, in order: the console window of the hook process, the parent process
chain (stopping at system boundary processes such as `explorer` or `sihost` so it cannot latch
onto an unrelated GUI window), any running terminal emulator, then any shell or editor window.

## Troubleshooting

**Nothing appears.** Run the script by hand — `powershell -ExecutionPolicy Bypass -File .\done-toast.ps1` —
and see whether the toast shows. If it does, the hook registration is the problem; check
`settings.json` parses as valid JSON and that the path is correct. `claude --debug` prints hook
execution details.

**Execution policy blocks it.** The install script already passes `-ExecutionPolicy Bypass` in the
hook command. If you registered the hook manually, add that flag.

**Claude Code hangs after each turn.** You are missing `"async": true`.

**Clicking raises the wrong window.** With several terminals open the heuristic can pick the wrong
one. Narrow the `$termRe` regex in `Get-TargetWindow` to just the terminal you actually use.

## License

MIT — see [LICENSE](LICENSE).

---

## 한국어

Claude Code가 한 턴을 끝내면 화면 우측 하단에 토스트를 띄우는 **Windows용** 알림 훅입니다.
토스트를 클릭하면 해당 세션의 터미널 창이 앞으로 올라옵니다.

- **포커스를 뺏지 않습니다.** `WS_EX_NOACTIVATE`로 만들어져, 타이핑 중이어도 방해받지 않습니다.
- **클릭하면 돌아갑니다.** 부모 프로세스 체인을 따라 세션 터미널(Windows Terminal, conhost, WezTerm, VS Code 등)을 찾아 복원·전면화합니다.
- **여러 개가 쌓입니다.** 세션을 여러 개 돌려도 겹치지 않고 위로 쌓입니다.

### 설치

```powershell
git clone https://github.com/dongju0124/claude-code-done-toast.git
cd claude-code-done-toast
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`%USERPROFILE%\.claude\hooks\`에 스크립트를 복사하고 `settings.json`에 `Stop` 훅을 등록합니다.
기존 설정은 보존되며, 수정 전 타임스탬프가 붙은 `.bak` 파일을 남깁니다. 두 번 실행해도 중복되지 않습니다.
설치 후 Claude Code를 재시작하세요.

제거는 `install.ps1 -Uninstall` 입니다.

### 주의할 점

- **`"async": true`는 필수입니다.** 토스트가 클릭 전까지 안 닫히는 설정이라, 빼면 매 턴마다 Claude Code가 멈춰 있습니다.
- 자동으로 닫히게 하려면 `done-toast.ps1` 6번 줄 `$DISMISS_MS`를 `5000` 등으로 바꾸세요.
- 문구는 12번 줄 `$bCodes`에 유니코드 코드포인트로 박혀 있습니다. PowerShell 5.1이 BOM 없는 `.ps1`을 시스템 코드페이지(한국어 환경이면 CP949)로 읽는 탓에, 한글을 그대로 쓰면 다른 로캘에서 깨지기 때문입니다. 영문으로 바꿀 거면 `$bodyText = 'Done'` 처럼 그냥 쓰면 됩니다.
