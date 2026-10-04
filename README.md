# dobly-atmos-linux

Atmos-style sound and 360° spatial audio for Linux, built on PipeWire and
EasyEffects. One script installs everything, and a small background service
picks the right setup for whatever you are listening on — no manual switching.

> **Not Dolby.** This project is not affiliated with or endorsed by Dolby
> Laboratories. "Dolby" and "Dolby Atmos" are trademarks of Dolby Laboratories.
> Nothing here decodes Atmos content; it shapes ordinary stereo audio to get a
> similar sound: fuller bass, clearer dialogue, more air and a wider, more
> enveloping image.

## What you get

| Output | What is applied |
|---|---|
| **Speakers** (HDMI, line-out, laptop speakers) | EQ, bass enhancer, exciter, stereo widening and a crosstalk canceller that pushes the image out beyond the speakers |
| **Headphones** (headphone jack, USB/Bluetooth headsets) | EQ, bass enhancer, exciter, a touch of room reverb, and binaural 360: left and right become virtual speakers in front of you, with a delayed copy placed beside and behind you |

The audio path is:

```
apps -> EasyEffects (preset) -> Atmos 360 stage -> your default output device
```

The **Atmos 360 stage** is a PipeWire filter-chain sink. In headphone mode it
renders through an HRTF (the MIT KEMAR dummy-head measurements shipped with
libmysofa); in speaker mode it passes audio through untouched. It follows the
system's default output, so no device is hardcoded.

The **`atmos-auto` service** watches the default output device. When it
changes (you plug in headphones, connect a Bluetooth headset, switch to HDMI)
it loads the matching preset and flips the stage between binaural and
passthrough.

## Requirements

- A Linux desktop using systemd user services
- PipeWire 1.4 or newer with the SOFA spatializer (built against libmysofa)
- EasyEffects from your distribution's packages (not Flatpak). The speaker
  preset uses the Crosstalk Canceller, which needs EasyEffects 8
- Python 3

`install.sh` installs all of this on apt, dnf, pacman and zypper systems.

## Install

```sh
git clone https://github.com/venomous-maker/dobly-atmos-linux.git
cd dobly-atmos-linux
./install.sh
```

Run it as your normal user. `sudo` is only used for the package step.

| Option | Effect |
|---|---|
| `--skip-packages` | Don't install packages; only configure |
| `--no-autostart` | Don't start EasyEffects automatically at login |
| `--files-only` | Only copy files; leave services and EasyEffects alone |

The installer will:

1. Install PipeWire, WirePlumber, EasyEffects, the LSP and Calf plugins and libmysofa.
2. Copy the presets, the Atmos 360 stage config, the `atmos` command and the `atmos-auto` service into your home directory.
3. Point EasyEffects' output at the Atmos 360 stage (EasyEffects is restarted in the background for this).
4. Start EasyEffects at login and enable the auto-switch service.

## Usage

Once installed it runs by itself. The `atmos` command is there for checking
and overriding:

```sh
atmos status       # what was detected and what is applied
atmos auto         # detect the output automatically (default)
atmos headphones   # force headphone mode
atmos speakers     # force speaker mode
atmos off          # bypass all effects
atmos on           # turn effects back on
```

### When to override

Headphones plugged into a **monitor's** audio jack look like plain HDMI to the
system, so they are treated as speakers. Run `atmos headphones` for that case,
and `atmos auto` to hand control back.

### Tuning

Open EasyEffects and adjust the loaded preset, then save it under the same
name so the change survives the next device switch.

| If you hear | Change |
|---|---|
| Boomy or distorted bass | Lower Bass Enhancer *Amount* |
| Harsh or sibilant highs | Lower Exciter *Amount* |
| Hollow or phasey voices on speakers | Lower Crosstalk Canceller *Delay*, or disable it |
| Echoey headphones | Lower Reverb *Amount*, or disable it |

The crosstalk canceller only works when you sit centred between the speakers.

Leave EasyEffects' output device set to **Atmos 360**. Pointing it at a
hardware device skips the 360 stage.

## Disable or uninstall

```sh
./uninstall.sh --disable   # switch it off, keep the files
./install.sh --skip-packages   # switch it back on

./uninstall.sh             # remove everything this project installed
```

Both stop the auto-switch service, point EasyEffects back at the default
output device and bypass its effects. A full uninstall also deletes the
presets, the stage config, the `atmos` command and the service. PipeWire and
EasyEffects themselves are never removed.

## Files installed

| Path | Purpose |
|---|---|
| `~/.local/bin/atmos` | Control command and watcher |
| `~/.config/systemd/user/atmos-auto.service` | Runs the watcher |
| `~/.config/pipewire/filter-chain.conf.d/sink-atmos-360.conf` | The Atmos 360 stage |
| `~/.local/share/easyeffects/output/Atmos-*-360.json` | Presets (`~/.config/easyeffects/output/` on EasyEffects 7) |
| `~/.config/autostart/easyeffects-atmos.desktop` | Starts EasyEffects at login |
| `~/.config/atmos/mode` | Your `auto` / `headphones` / `speakers` choice |

## Limitations

- Stereo in, stereo out. Real 5.1/7.1 or Atmos tracks are downmixed by
  EasyEffects before they reach the 360 stage.
- Two speakers cannot place sound behind you; speaker mode widens, it does not surround.
- The HRTF is a generic dummy head, so how convincing headphone mode sounds varies from person to person.
- Developed and tested on Kali Linux (Debian-based) with PipeWire 1.6 and
  EasyEffects 8.2. The dnf, pacman and zypper package lists and the
  EasyEffects 7 path are best-effort and untested.

## Troubleshooting

```sh
atmos status
journalctl --user -u atmos-auto -n 20      # detection log
journalctl --user -u filter-chain -n 20    # Atmos 360 stage
```

- **No sound after install** — check that the system's output device is your
  real hardware, not "Atmos 360" or "Easy Effects Sink". The watcher corrects
  this by itself when it is running.
- **Nothing is applied after login** — EasyEffects must be running; re-run
  `./install.sh --skip-packages` without `--no-autostart`.

## License

[MIT](LICENSE)
