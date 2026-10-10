# lowkey from the terminal


Note a task or check the current one without leaving the terminal. With lowkey open on the same data
directory, commands go to the window — a change shows up there at once and can be undone there; with it
closed, lowkey reads and saves `state.json` itself. Nothing here talks to the network.

```sh
lowkey add "fix login tomorrow 14:00 p1 #backend // check the refresh token"   # read like quick capture
lowkey now                    # the task with a running timer, else the one your git branch names
lowkey list --status prog     # also --profile <name>, --json
lowkey today                  # overdue first, then in progress, scheduled or due today
lowkey done APP-12
lowkey open APP-12            # show it in the window (starts lowkey if it is closed)
lowkey sched . tomorrow 14:00 # plan it for a day ("." = the task your git branch names); "none" clears
lowkey due APP-12 fri         # its deadline; on a tracker card it is your own date, the tracker keeps its own
lowkey est . 1h30m            # the estimate; "none" clears
lowkey someday APP-12         # park it (and "someday APP-12 off" to take it back)
lowkey help
```

Each change answers with one line of fact in the app's language (`--json` gives the task instead).

`lowkey now` prints nothing and exits 0 when there is no current task, so it fits a shell prompt.
`--format` takes `{id} {title} {status} {priority} {profile} {source} {elapsed}`:

```toml
# starship.toml
[custom.lowkey]
command = "lowkey now --format '{id} {title}'"
when = true
format = "[$output]($style) "
```

```sh
# bash / zsh
PS1='$(lowkey now --format "[{id}] ")'"$PS1"
```

Exit codes: `0` ok, `1` usage, `2` no such task, profile or column, `3` data error. `--data-dir` and
`HEAP_DATA_DIR` work as for the app.

**Windows:** in cmd and PowerShell use `lowkey-cli` (it sits next to `lowkey.exe`): lowkey.exe is a
windowed program, so those shells neither wait for it nor see its output. `lowkey-cli` answers `now`,
`list` and `today` itself, fast enough for a prompt, and passes the rest to lowkey.exe. Add the install
folder to `PATH`, and `Set-Alias lowkey lowkey-cli` in your PowerShell profile if you like the short name.
In git-bash plain `lowkey` works too.

