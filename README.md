# handyOverlay

Tools for running [Handy](https://github.com/cjpais/Handy) (speech-to-text) well on **niri / Wayland**
with [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell):

1. a **DMS daemon plugin** that draws a floating pill with a live mic waveform while Handy records
   and transcribes (for setups where Handy's own overlay can't render), and
2. **extras** for a hotkey, autostart, pausing/resuming media while you dictate, and a workaround for a
   USB audio conflict.

## Which setup do I need?

| Handy install | Handy's own overlay on niri | What to use |
|---|---|---|
| **Native package** (`.deb` / `.rpm`, v0.9.8 or newer) | Works. Set overlay style to **Live** to see the words as you speak (needs a streaming model, e.g. Parakeet Unified EN). | You don't need the DMS plugin. Use the hotkey and extras below. |
| **AppImage** (tested 0.9.6) | Doesn't work: its `linuxdeploy` GTK hook forces `GDK_BACKEND=x11`, so `gtk-layer-shell` can't initialize ("GTK layer shell not available"). | Install the DMS plugin below for a waveform pill. |

Notes:
- Handy's streaming text is only shown in its own overlay. It isn't written to its log, even with
  `--debug`, so this plugin can't display live text.
- The aarch64 `.deb` first appeared in v0.9.8; v0.9.6 only had an AppImage for aarch64.
- Launch the native package with `env GDK_BACKEND=wayland handy` and **without**
  `HANDY_NO_GTK_LAYER_SHELL` (see [Handy PR #2040](https://github.com/cjpais/Handy/pull/2040)). Verify in
  `~/.local/share/com.pais.handy/logs/handy.log`: it should say `GTK layer shell initialized for overlay window`.
- Tested on Ubuntu 26.04 aarch64, niri 26.04, DMS, PipeWire, Handy 0.9.8 `.deb`. Autostart and the first
  dictation after login were not yet verified. The first transcription after a fresh start was slow once
  (about 16 s for 6 s of audio, probably one-time Vulkan warm-up), then ~0.1 s.

## The DMS plugin (AppImage users)

- `Daemon.qml` follows Handy's log (`~/.local/share/com.pais.handy/logs/handy.log`) with `tail -F` and tracks
  `idle → recording → transcribing → idle` from its `TranscribeAction::start/stop` lines. This depends on
  Handy's log wording.
- While recording, `level.py` meters the default microphone through `arecord` and prints an RMS level about
  25 times a second; the pill draws it as bars. While transcribing it shows a slow wave.
- The pill is click-through, sits at the bottom centre of the focused output, and fades out when done
  (30 s watchdog so it can never get stuck).

Install:

```bash
git clone https://github.com/remydw/handyOverlay ~/.config/DankMaterialShell/plugins/handyOverlay
dms ipc call plugin-scan rescan handyOverlay
dms ipc call plugins enable handyOverlay
```

Needs `python3` and `arecord` (alsa-utils). Handy must use the system **default** microphone, not a
hardware device chosen by name (Handy opens those exclusively, so the meter can't share them).
If you switch to the native package, disable it so two indicators don't stack:
`dms ipc call plugins disable handyOverlay`.

## Hotkey and autostart (niri)

Global shortcuts via `rdev` don't work on Wayland, so Handy is driven by a signal: **SIGUSR2** toggles
transcription (`SIGUSR1` belongs to WebKitGTK). `extras/handy.kdl` binds `Mod+S` and autostarts Handy hidden
(pick the native-package or AppImage line, replace `/home/YOU`, and include it from `config.kdl`).
Keep `repeat=false`, otherwise a held key sends several signals that cancel each other.
For a plain setup, the bind can simply be `spawn "pkill" "-USR2" "-x" "handy"`.

## Extras: pause media and the USB audio conflict

On the machine this was built on (aarch64, xHCI), a USB microphone can't start while a USB speaker
dongle holds its playback endpoint, and the reverse. The kernel logs `Not enough bandwidth for altsetting 1`
and `usb_set_interface failed (-12)`, PipeWire reports `set_hw_params: Cannot allocate memory`, and Handy
records zero samples. The speaker sink stays held for seconds after audio stops (a paused Chrome stream
keeps it busy for ~10 s). If you hit the same thing, `extras/` has a workaround:

- `51-usb-audio.conf` → `~/.config/wireplumber/wireplumber.conf.d/`: release both USB nodes after 1 s idle
  instead of 5 s. Then `systemctl --user restart wireplumber`.
- `handy-toggle` → `~/.local/bin/` (executable). Bind it instead of the bare `pkill`:
  - on start it pauses the MPRIS players that are playing (remembering them), moves the default output to
    HDMI so streams leave the USB sink, waits until the sink suspends (about 1.5 s), then toggles Handy;
  - on stop it signals Handy, waits for the mic to release, restores the default output, and resumes the
    players it paused;
  - timing goes to `~/.cache/handy-toggle.log`.

The device names inside `handy-toggle` (`alsa_output.usb-10ae_USB_Audio`, `alsa_input.usb-Generic_USB_Audio`,
the HDMI sink `alsa_output.pci-0000_c1_00.1.hdmi`) are specific to one machine; change them to match
`pw-cli ls Node`. If you have no such conflict, you don't need `handy-toggle` or the WirePlumber file.

## Troubleshooting

- Recording gives `sample count: 0`: the mic is quiet or busy. Check `journalctl -k -b | grep -i bandwidth`
  and `journalctl --user | grep 'Cannot allocate'`.
- Hotkey does nothing: `pgrep -x handy` must match, and `repeat=false` must be set.
- Pill never shows: check `dms ipc call plugins status handyOverlay` and that Handy logs to the default path.

## License

MIT
