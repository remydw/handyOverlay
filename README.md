# handyOverlay

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) daemon plugin that shows a
floating pill with a live mic waveform while [Handy](https://github.com/cjpais/Handy) (speech-to-text)
is recording or transcribing, on niri / Wayland.

Handy's own overlay needs `gtk-layer-shell`, which doesn't work from the AppImage on niri, and
`HANDY_NO_GTK_LAYER_SHELL=1` (needed so niri doesn't treat the overlay as the active window and
break the paste target) disables it. This plugin replaces it with a native Quickshell layer-shell
window.

## How it works

- `Daemon.qml` follows Handy's log (`~/.local/share/com.pais.handy/logs/handy.log`) with `tail -F`
  and tracks `idle → recording → transcribing → idle` from its `TranscribeAction::start/stop` lines.
- While recording, `level.py` meters the default microphone through `arecord` and prints an RMS
  level ~25 times a second; the pill draws it as bars. While transcribing it shows a slow wave.
- The pill is click-through, sits at the bottom centre of the focused output, and fades out when
  done (with a 30 s watchdog so it can never get stuck).

It depends on Handy's log wording, so a Handy update could break it. Tested with Handy 0.9.6.

## Install

```bash
git clone https://github.com/remydw/handyOverlay ~/.config/DankMaterialShell/plugins/handyOverlay
dms ipc call plugin-scan rescan handyOverlay
dms ipc call plugins enable handyOverlay
```

Needs `python3` and `arecord` (alsa-utils). Handy must be on the system default microphone
(not a hardware device chosen by name, which Handy opens exclusively and the meter can't share).

## Hotkey (niri / Wayland)

`rdev` global shortcuts don't work on Wayland, so Handy is driven by a signal: **SIGUSR2** toggles
transcription (`SIGUSR1` is used by WebKitGTK). `extras/handy.kdl` binds `Mod+S`, and autostarts
Handy hidden; adjust the paths and include it from `config.kdl`. Use `repeat=false`, otherwise a
held key sends several signals and cancels itself.

## Extras: USB audio conflict workaround

On the machine this was built on (aarch64, xHCI), a USB microphone cannot start while a USB
speaker dongle holds its playback endpoint, and vice versa. The kernel logs
`Not enough bandwidth for altsetting 1` / `usb_set_interface failed (-12)`, PipeWire reports
`set_hw_params: Cannot allocate memory`, and Handy records zero samples. If you hit the same
thing, `extras/` contains the workaround:

- `51-usb-audio.conf` → `~/.config/wireplumber/wireplumber.conf.d/`: release both USB nodes after
  1 s idle instead of 5 s.
- `handy-toggle` → `~/.local/bin/`: on start, pause the MPRIS players that are playing (remembering
  them), move the default output to HDMI so streams leave the USB sink, wait for it to suspend,
  then toggle Handy. On stop, wait for the mic to release, restore the default output, and resume
  the players it paused.

The device names in `handy-toggle` (`alsa_output.usb-10ae_USB_Audio`, `alsa_input.usb-Generic_USB_Audio`,
the HDMI sink) are specific to one machine; change them to match `pw-cli ls Node`. If you have no
such conflict you only need the plugin and a plain `pkill -USR2 -x handy` bind.

## License

MIT
