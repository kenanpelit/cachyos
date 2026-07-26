# margo-osc Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge modernz.lua + progressbar.lua + pause_indicator_lite.lua into one `margo-osc` mpv script, keeping the thin persistent bottom bar and a single center pause glyph.

**Architecture:** modernz is the base. Fork it to `margo-osc.lua`, enable its native `persistentprogress` for the thin bottom bar (replacing progressbar), integrate pause_indicator_lite's center glyph as a self-contained feature block, and delete the other two scripts. modernz's body stays byte-for-byte except the appended pause block, so behavior equivalence is provable.

**Tech Stack:** Lua 5.1 / LuaJIT (mpv scripting), mpv `--config-dir` for isolated verification, `socat` + IPC for binding/property checks.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-26-margo-osc-merge-design.md`
- Internal mpv script name derives from filename: `margo-osc.lua` → `margo_osc`.
- All verification runs against an ISOLATED config copy (`--config-dir`), NEVER the live `~/.config/mpv`.
- Work dir: `/home/kenan/.cachy/modules/mpv/dotfiles/mpv` (call it `$M`).
- `mpv.conf` keeps `osc=no` (unchanged) — the builtin OSC stays off.
- Center pause click-to-pause default: `keybind_allow=no` (glyph is visual only; modernz owns mouse clicks).
- Do NOT port: system clock, `.`/`,` frame-step keys (mpv builtin).
- Back up all mpv scripts/confs before the first deletion.

---

### Task 1: Fork modernz → margo-osc (rename + reference updates)

Rename the script and its config, update every internal `modernz` reference, and prove the renamed script behaves exactly like modernz (no feature change yet).

**Files:**
- Create: `$M/scripts/margo-osc.lua` (copy of `modernz.lua`)
- Create: `$M/script-opts/margo-osc.conf` (copy of `modernz.conf`)
- Modify: `$M/input.conf` (line with `modernz/visibility`)
- Delete: `$M/scripts/modernz.lua`, `$M/script-opts/modernz.conf`

**Interfaces:**
- Produces: mpv script identity `margo_osc` with bindings `margo_osc/visibility`, `margo_osc/progress-toggle` and messages `osc-visibility`/`osc-show`/`osc-hide`/`osc-idlescreen`/`thumbfast-info` (names unchanged; only the script-name prefix changes).

- [ ] **Step 1: Back up current mpv scripts/confs**

```bash
BK=~/.cachy-mpv-backup-$(date +%Y%m%d-%H%M%S); mkdir -p $BK
cp -a /home/kenan/.cachy/modules/mpv/dotfiles/mpv/scripts \
      /home/kenan/.cachy/modules/mpv/dotfiles/mpv/script-opts \
      /home/kenan/.cachy/modules/mpv/dotfiles/mpv/input.conf "$BK"/
echo "backup: $BK"
```

- [ ] **Step 2: Copy modernz → margo-osc (script + conf), then git rm originals**

```bash
cd /home/kenan/.cachy/modules/mpv/dotfiles/mpv
git mv scripts/modernz.lua scripts/margo-osc.lua
git mv script-opts/modernz.conf script-opts/margo-osc.conf
```

- [ ] **Step 3: Update internal `modernz` script-name references**

In `script-opts/margo-osc.conf`, replace every `script-message-to modernz ` with `script-message-to margo_osc ` (≈9 lines: title/playlist/volume/track/chapter mouse commands):

```bash
sed -i 's/script-message-to modernz /script-message-to margo_osc /g' script-opts/margo-osc.conf
```

In `input.conf`, update the DEL binding:

```bash
sed -i 's#script-binding modernz/visibility#script-binding margo_osc/visibility#' input.conf
```

- [ ] **Step 4: Verify no stale `modernz` references remain**

Run:
```bash
grep -rn 'modernz' scripts/margo-osc.lua script-opts/margo-osc.conf input.conf mpv.conf | grep -viE 'modernx|ModernZ \(http|derivative|maoiscat|cyl0|dexeonify' || echo "CLEAN"
```
Expected: `CLEAN` (only license/attribution comments may mention ModernZ; no `script-binding modernz/` or `script-message-to modernz`).

- [ ] **Step 5: Verify margo-osc loads and DEL toggles visibility (isolated config)**

```bash
SB=/tmp/claude-1000/-home-kenan--cachy/9f87290e-5fa7-48f3-8e48-74b6e300cd1e/scratchpad
rm -rf $SB/mo && cp -r /home/kenan/.cachy/modules/mpv/dotfiles/mpv $SB/mo
rm -f $SB/mo.sock
(mpv --config-dir=$SB/mo --vo=null --ao=null --idle=yes --input-ipc-server=$SB/mo.sock --log-file=$SB/mo.log --msg-level=all=v >/dev/null 2>&1 &)
for i in $(seq 12); do [ -S $SB/mo.sock ] && break; sleep 1; done; sleep 2
printf '{"command":["keypress","DEL"]}\n' | socat - $SB/mo.sock >/dev/null 2>&1; sleep 0.5
grep -E 'margo_osc|Can.t find script' $SB/mo.log | tail -5
pkill -x mpv
```
Expected: `script-binding margo_osc/visibility` dispatched, no "Can't find script" error, no Lua error.

- [ ] **Step 6: Commit**

```bash
cd /home/kenan/.cachy
git add modules/mpv/dotfiles/mpv/scripts/margo-osc.lua modules/mpv/dotfiles/mpv/script-opts/margo-osc.conf modules/mpv/dotfiles/mpv/input.conf modules/mpv/dotfiles/mpv/scripts/modernz.lua modules/mpv/dotfiles/mpv/script-opts/modernz.conf
git commit -m "mpv: rename modernz OSC to margo-osc (script identity margo_osc)"
```

---

### Task 2: Thin bottom bar via persistentprogress; drop progressbar

Turn on modernz's native persistent progress bar to reproduce the thin bottom line the user likes, verify the look, then delete progressbar.lua.

**Files:**
- Modify: `$M/script-opts/margo-osc.conf` (`persistentprogress`, `persistentprogressheight`)
- Delete: `$M/scripts/progressbar.lua`

**Interfaces:**
- Consumes: `margo_osc` script from Task 1.

- [ ] **Step 1: Enable persistentprogress in margo-osc.conf**

Set `persistentprogress=yes` and start with a thin height matching progressbar's ~3px look:
```bash
cd /home/kenan/.cachy/modules/mpv/dotfiles/mpv
sed -i 's/^persistentprogress=.*/persistentprogress=yes/' script-opts/margo-osc.conf
sed -i 's/^persistentprogressheight=.*/persistentprogressheight=3/' script-opts/margo-osc.conf
grep -nE 'persistentprogress' script-opts/margo-osc.conf
```
Expected: `persistentprogress=yes`, `persistentprogressheight=3`.

- [ ] **Step 2: Visually verify the thin bar during playback (isolated config)**

Generate a test clip and drive mpv with a window to eyeball the bottom bar, OR capture a frame. Compare against current progressbar look (the user likes the thin persistent bottom line).
```bash
SB=/tmp/claude-1000/-home-kenan--cachy/9f87290e-5fa7-48f3-8e48-74b6e300cd1e/scratchpad
ffmpeg -f lavfi -i testsrc=d=30:s=1280x720 -c:v libx264 -y $SB/t.mp4 >/dev/null 2>&1
rm -rf $SB/mo2 && cp -r /home/kenan/.cachy/modules/mpv/dotfiles/mpv $SB/mo2
# Run with a real window so the bar is visible; user confirms the thin bottom line looks right.
mpv --config-dir=$SB/mo2 --pause $SB/t.mp4
```
Expected: a thin persistent progress line at the very bottom during playback.
DECISION GATE: if the look is acceptable → proceed. If NOT (user wants progressbar's exact bar), STOP and switch to the fallback: extract progressbar.lua's `render_persistentprogressbar` block into margo-osc.lua and set `persistentprogress=no`. Do not delete progressbar.lua in that case until the renderer is ported.

- [ ] **Step 3: Delete progressbar.lua**

```bash
cd /home/kenan/.cachy/modules/mpv/dotfiles/mpv
git rm scripts/progressbar.lua
```

- [ ] **Step 4: Verify only ONE seekbar/progress source remains, no Lua errors**

```bash
SB=/tmp/claude-1000/-home-kenan--cachy/9f87290e-5fa7-48f3-8e48-74b6e300cd1e/scratchpad
rm -rf $SB/mo3 && cp -r /home/kenan/.cachy/modules/mpv/dotfiles/mpv $SB/mo3
timeout 12 mpv --config-dir=$SB/mo3 --vo=null --ao=null --idle=yes --log-file=$SB/mo3.log --msg-level=all=v $SB/t.mp4 >/dev/null 2>&1
grep -iE 'progressbar|torque|Lua error|attempt to' $SB/mo3.log | head
echo "(progressbar/torque satırı OLMAMALI)"
```
Expected: no `progressbar`/`torque` load lines, no Lua errors.

- [ ] **Step 5: Commit**

```bash
cd /home/kenan/.cachy
git add modules/mpv/dotfiles/mpv/script-opts/margo-osc.conf modules/mpv/dotfiles/mpv/scripts/progressbar.lua
git commit -m "mpv: margo-osc thin bottom bar via persistentprogress; drop progressbar.lua"
```

---

### Task 3: Integrate center pause glyph; drop pause_indicator_lite

Graft pause_indicator_lite's center-screen pause glyph into margo-osc.lua as a self-contained block, carry its options into margo-osc.conf (with `keybind_allow=no`), and delete the standalone script.

**Files:**
- Modify: `$M/scripts/margo-osc.lua` (append pause-glyph feature block)
- Modify: `$M/script-opts/margo-osc.conf` (append `# Center pause indicator` option section)
- Delete: `$M/scripts/pause_indicator_lite.lua`, `$M/script-opts/pause_indicator_lite.conf`

**Interfaces:**
- Consumes: `margo_osc` script from Tasks 1-2.

- [ ] **Step 1: Read both source files to plan the graft**

Read `scripts/pause_indicator_lite.lua` in full (218 lines) and the tail of `scripts/margo-osc.lua` (after its final `mp.register_script_message(...)` / `mp.add_key_binding(...)` block near the end). Identify pause_indicator_lite's: option table, `read_options`, the 3 `create_osd_overlay` handles, the pause-state event/observer, and its forced `pause-indicator` input section.

- [ ] **Step 2: Append the pause-glyph block into margo-osc.lua**

At the END of `scripts/margo-osc.lua`, add a self-contained block (wrapped in `do ... end`) that:
- Declares its own local option table seeded from pause_indicator_lite's defaults, read via `require('mp.options').read_options(pi_opts, 'margo-osc')` so it reads the pause-indicator keys from `margo-osc.conf` (NOT a separate file).
- Creates its own osd overlays (do not reuse modernz's overlay ids).
- Observes `pause` and renders/clears the center glyph, exactly as pause_indicator_lite did.
- Honors `keybind_allow`: when `no` (the default), does NOT register the `mbtn_left` forced section (avoids clashing with modernz's mouse handling). When `yes`, registers it as pause_indicator_lite did.

Keep the ported logic identical to the source; only change: option source (margo-osc.conf), overlay id namespacing, and the `keybind_allow` gate default.

- [ ] **Step 3: Append the pause-indicator option section to margo-osc.conf**

Copy the non-comment options from `script-opts/pause_indicator_lite.conf` into a new section at the end of `script-opts/margo-osc.conf`, changing `keybind_allow=yes` to `keybind_allow=no`:
```
# ── Merkez pause göstergesi (pause_indicator_lite'tan entegre) ──
indicator_icon=pause
indicator_stay=yes
indicator_timeout=0.6
keybind_allow=no
keybind_set=mbtn_left
keybind_mode=onpause
keybind_eof_disable=yes
icon_color=#FFFFFF
icon_border_color=#111111
icon_border_width=1.5
icon_opacity=40
rectangles_width=30
rectangles_height=80
rectangles_spacing=20
triangle_width=80
triangle_height=80
flash_play_icon=yes
flash_icon_timeout=0.3
fluent_icons=no
fluent_icon_size=80
```

- [ ] **Step 4: Verify syntax**

```bash
cd /home/kenan/.cachy/modules/mpv/dotfiles/mpv
luajit -bl scripts/margo-osc.lua >/dev/null && echo "OK margo-osc.lua" || luajit -bl scripts/margo-osc.lua 2>&1 | head -3
```
Expected: `OK margo-osc.lua`.

- [ ] **Step 5: Delete pause_indicator_lite files**

```bash
cd /home/kenan/.cachy/modules/mpv/dotfiles/mpv
git rm scripts/pause_indicator_lite.lua script-opts/pause_indicator_lite.conf
```

- [ ] **Step 6: Verify SINGLE center pause glyph on pause, no double, no Lua errors**

```bash
SB=/tmp/claude-1000/-home-kenan--cachy/9f87290e-5fa7-48f3-8e48-74b6e300cd1e/scratchpad
rm -rf $SB/mo4 && cp -r /home/kenan/.cachy/modules/mpv/dotfiles/mpv $SB/mo4
rm -f $SB/mo4.sock
(mpv --config-dir=$SB/mo4 --vo=null --ao=null --input-ipc-server=$SB/mo4.sock --log-file=$SB/mo4.log --msg-level=all=v $SB/t.mp4 >/dev/null 2>&1 &)
for i in $(seq 12); do [ -S $SB/mo4.sock ] && break; sleep 1; done; sleep 2
printf '{"command":["set_property","pause",true]}\n' | socat - $SB/mo4.sock >/dev/null 2>&1; sleep 0.5
grep -iE 'pause_indicator|Lua error|attempt to' $SB/mo4.log | head
echo "(pause_indicator load satırı OLMAMALI; hata OLMAMALI)"
# Optional windowed eyeball: mpv --config-dir=$SB/mo4 $SB/t.mp4  → tek merkez pause ikonu
pkill -x mpv
```
Expected: no `pause_indicator` load line, no Lua error; windowed check shows exactly one center pause glyph.

- [ ] **Step 7: Commit**

```bash
cd /home/kenan/.cachy
git add modules/mpv/dotfiles/mpv/scripts/margo-osc.lua modules/mpv/dotfiles/mpv/script-opts/margo-osc.conf modules/mpv/dotfiles/mpv/scripts/pause_indicator_lite.lua modules/mpv/dotfiles/mpv/script-opts/pause_indicator_lite.conf
git commit -m "mpv: integrate center pause glyph into margo-osc; drop pause_indicator_lite"
```

---

### Task 4: Full verification + graph update

Confirm the whole system: one OSC, thin bar, single pause glyph, DEL works, no dangling references, update the knowledge graph.

**Files:** none created; verification + `graphify update`.

- [ ] **Step 1: Confirm scripts/ has margo-osc and NOT the three old scripts**

```bash
cd /home/kenan/.cachy/modules/mpv/dotfiles/mpv
ls scripts/ | grep -E 'margo-osc|modernz|progressbar|pause_indicator'
```
Expected: only `margo-osc.lua`; no modernz/progressbar/pause_indicator_lite.

- [ ] **Step 2: Confirm no dangling references anywhere in the mpv module**

```bash
cd /home/kenan/.cachy
grep -rniE 'modernz/|progressbar|pause_indicator|torque' modules/mpv/dotfiles/mpv/ --include='*.conf' --include='*.lua' | grep -viE 'ModernZ \(http|derivative|maoiscat|cyl0|dexeonify|LGPL' || echo "NO DANGLING REFS"
```
Expected: `NO DANGLING REFS`.

- [ ] **Step 3: End-to-end functional check (isolated config)**

```bash
SB=/tmp/claude-1000/-home-kenan--cachy/9f87290e-5fa7-48f3-8e48-74b6e300cd1e/scratchpad
rm -rf $SB/mo5 && cp -r /home/kenan/.cachy/modules/mpv/dotfiles/mpv $SB/mo5
rm -f $SB/mo5.sock
(mpv --config-dir=$SB/mo5 --vo=null --ao=null --input-ipc-server=$SB/mo5.sock --log-file=$SB/mo5.log --msg-level=all=v $SB/t.mp4 >/dev/null 2>&1 &)
for i in $(seq 12); do [ -S $SB/mo5.sock ] && break; sleep 1; done; sleep 2
printf '{"command":["keypress","DEL"]}\n' | socat - $SB/mo5.sock >/dev/null 2>&1; sleep 0.4
printf '{"command":["set_property","pause",true]}\n' | socat - $SB/mo5.sock >/dev/null 2>&1; sleep 0.4
echo "=== owner=margo_osc bağlama sayısı ==="
printf '{"command":["get_property","input-bindings"]}\n' | socat - $SB/mo5.sock 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin)['data']; print(sum(1 for b in d if b.get('owner')=='margo_osc'))"
echo "=== Lua hataları ==="; grep -iE 'Lua error|attempt to' $SB/mo5.log | head
pkill -x mpv
```
Expected: margo_osc has bindings (>0), no Lua errors, DEL + pause dispatched.

- [ ] **Step 4: Update knowledge graph**

```bash
cd /home/kenan/.cachy && graphify update .
```

- [ ] **Step 5: Final commit (if graph or stray files changed)**

```bash
cd /home/kenan/.cachy
git add -A modules/mpv graphify-out
git commit -m "mpv: finalize margo-osc merge (graph update)" || echo "nothing to commit"
```

---

## Self-Review

**Spec coverage:**
- modernz base fork → Task 1 ✓
- persistentprogress thin bar → Task 2 ✓
- center pause integration → Task 3 ✓
- drop progressbar + pause_indicator_lite → Tasks 2, 3 ✓
- script-name reference updates (input.conf, margo-osc.conf) → Task 1 ✓
- click-to-pause default off → Task 3 Step 3 ✓
- persistentprogress look fallback (approach 3) → Task 2 Step 2 DECISION GATE ✓
- out of scope (clock, frame-step) → Global Constraints ✓
- isolated-config verification → every task's verify step ✓

**Placeholder scan:** No TBD/TODO. Task 3 Steps 1-2 describe a copy-and-adapt of an existing 218-line file rather than pasting it verbatim — the source file is the reference; the adaptations (option source, overlay namespacing, keybind_allow gate) are spelled out.

**Type consistency:** Script identity `margo_osc` used consistently across tasks. Config keys (`persistentprogress`, `persistentprogressheight`, pause-indicator keys) match the source files verified during design.
