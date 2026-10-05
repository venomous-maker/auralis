# Auralis

Atmos-style sound, 360° spatial audio and microphone noise suppression for
Linux, built on PipeWire and EasyEffects. One script installs everything, and
a small background service picks the right setup for whatever you are
listening on — no manual switching.

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
apps -> EasyEffects (preset) -> Auralis 360 stage -> your default output device
```

The **Auralis 360 stage** is a PipeWire filter-chain sink. In headphone mode it
renders through an HRTF (the MIT KEMAR dummy-head measurements shipped with
libmysofa); in speaker mode it passes audio through untouched. It follows the
system's default output, so no device is hardcoded.

The **`auralis-auto` service** starts with your desktop session and watches
the default output device. When it
changes (you plug in headphones, connect a Bluetooth headset, switch to HDMI)
it loads the matching preset and flips the stage between binaural and
passthrough.

**Microphone noise suppression** runs on the input side: a high-pass filter,
RNNoise (a neural noise remover) and a limiter. It removes steady background
noise such as fans, hum and keyboard clatter from what others hear. Apps pick
it up automatically through EasyEffects' virtual microphone, "Easy Effects
Source". This is not active noise cancellation for your own ears; that needs
microphones inside the headphones and cannot be done in software.

## Requirements

- A Linux desktop using systemd user services
- PipeWire 1.4 or newer with the SOFA spatializer (built against libmysofa)
- EasyEffects from your distribution's packages (not Flatpak). The speaker
  preset uses the Crosstalk Canceller, which needs EasyEffects 8
- `pactl` 16 or newer (pulseaudio-utils / libpulse)
- Python 3

`install.sh` installs all of this on apt, dnf, pacman and zypper systems.

## Install

```sh
git clone https://github.com/venomous-maker/auralis.git
cd auralis
./install.sh
```

Run it as your normal user. `sudo` is only used for the package step.

| Option | Effect |
|---|---|
| `--skip-packages` | Don't install packages; only configure |
| `--no-autostart` | Don't start EasyEffects automatically at login |
| `--no-mic` | Don't turn on microphone noise suppression |
| `--files-only` | Only copy files; leave services and EasyEffects alone |

The installer will:

1. Install PipeWire, WirePlumber, EasyEffects, the LSP and Calf plugins and libmysofa.
2. Copy the presets, the Auralis 360 stage config, the `auralis` command and the `auralis-auto` service into your home directory.
3. Point EasyEffects' output at the Auralis 360 stage (EasyEffects is restarted in the background for this).
4. Turn on microphone noise suppression.
5. Start EasyEffects at login and enable the auto-switch service.

## Usage

Once installed it runs by itself. The `auralis` command is there for checking
and overriding:

```sh
auralis status       # what was detected and what is applied
auralis auto         # detect the output automatically (default)
auralis headphones   # force headphone mode
auralis speakers     # force speaker mode
auralis mic on       # microphone noise suppression on (default)
auralis mic off      # microphone noise suppression off
auralis off          # bypass all effects
auralis on           # turn effects back on
```

### When to override

Headphones plugged into a **monitor's** audio jack look like plain HDMI to the
system, so they are treated as speakers. Run `auralis headphones` for that
case, and `auralis auto` to hand control back.

### Tuning

Open EasyEffects and adjust the loaded preset, then save it under the same
name so the change survives the next device switch.

| If you hear | Change |
|---|---|
| Boomy or distorted bass | Lower Bass Enhancer *Amount* |
| Harsh or sibilant highs | Lower Exciter *Amount* |
| Hollow or phasey voices on speakers | Lower Crosstalk Canceller *Delay*, or disable it |
| Echoey headphones | Lower Reverb *Amount*, or disable it |
| Your voice cuts in and out on calls | Lower RNNoise *VAD threshold* in the input preset, or run `auralis mic off` |

The crosstalk canceller only works when you sit centred between the speakers.

Leave EasyEffects' output device set to **Auralis 360**. Pointing it at a
hardware device skips the 360 stage.

## Disable or uninstall

```sh
./uninstall.sh --disable        # switch it off, keep presets and the command
./install.sh --skip-packages    # switch it back on

./uninstall.sh                  # remove everything this project installed
```

Both stop the auto-switch service, take down the Auralis 360 stage, point
EasyEffects back at the default output device and bypass its effects. A full
uninstall also deletes the presets, the `auralis` command and the service. PipeWire and
EasyEffects themselves are never removed.

## Files installed

| Path | Purpose |
|---|---|
| `~/.local/bin/auralis` | Control command and watcher |
| `~/.config/systemd/user/auralis-auto.service` | Runs the watcher |
| `~/.config/pipewire/filter-chain.conf.d/sink-auralis-360.conf` | The Auralis 360 stage |
| `~/.local/share/easyeffects/output/Auralis-*.json` | Speaker and headphone presets |
| `~/.local/share/easyeffects/input/Auralis-Mic*.json` | Microphone presets |
| `~/.config/autostart/easyeffects-auralis.desktop` | Starts EasyEffects at login |
| `~/.config/auralis/mode` | Your `auto` / `headphones` / `speakers` choice |

On EasyEffects 7 the presets go to `~/.config/easyeffects/` instead.

## Limitations

- Stereo in, stereo out. Real 5.1/7.1 or Atmos tracks are downmixed by
  EasyEffects before they reach the 360 stage.
- Two speakers cannot place sound behind you; speaker mode widens, it does not surround.
- A mode change made while nothing is playing takes effect a moment into the next playback.
- Microphone noise suppression has not been tuned by ear on many voices; RNNoise can clip quiet speech.
- The HRTF is a generic dummy head, so how convincing headphone mode sounds varies from person to person.
- Developed and tested on Kali Linux (Debian-based) with PipeWire 1.6 and
  EasyEffects 8.2. The dnf, pacman and zypper package lists and the
  EasyEffects 7 path are best-effort and untested.

## Troubleshooting

```sh
auralis status
journalctl --user -u auralis-auto -n 20    # detection log
journalctl --user -u filter-chain -n 20    # Auralis 360 stage
```

- **No sound after install** — check that the system's output device is your
  real hardware, not "Auralis 360" or "Easy Effects Sink". The watcher corrects
  this by itself when it is running.
- **EasyEffects crash reports at login** — versions before the service was
  tied to the graphical session started the watcher too early. Update and
  re-run the installer: `git pull && ./install.sh --skip-packages`.
- **Nothing is applied after login** — EasyEffects must be running; re-run
  `./install.sh --skip-packages` without `--no-autostart`.
- **Others can't hear noise suppression working** — the calling app must use
  "Easy Effects Source" as its microphone.

## License

[MIT](LICENSE)
