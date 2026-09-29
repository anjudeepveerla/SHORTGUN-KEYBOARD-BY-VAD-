# ShotgunKeyboard

A small, open-source desktop app that plays a sound effect whenever you press a key. It runs on macOS and Windows.

[Download the latest release](https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-/releases/latest) · [Source code](https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-)

## Downloads

| Computer | Download |
| --- | --- |
| Mac with Apple Silicon (M1 or newer) | [macOS arm64 DMG](https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-/releases/latest/download/ShotgunKeyboard-macOS-arm64.dmg) |
| Mac with Intel processor | [macOS Intel DMG](https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-/releases/latest/download/ShotgunKeyboard-macOS-x86_64.dmg) |
| Windows 10/11, 64-bit | [Windows portable EXE](https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-/releases/latest/download/ShotgunKeyboard-Windows-x64.exe) |

Windows apps use .exe; .apk files are for Android. The Windows download is a portable app, so no separate .NET installation is needed.

## Use

The main window has 18 bundled effects: six original generated sounds plus 12 MP3s. **Gunshot J Budden** is selected by default on a fresh install. Select one sound for every key press. Turn on **Multiple sounds** to check several; each key press then picks one at random. You can add your own audio files, remove added sounds, adjust the volume, test a sound, or turn **Armed** off.

The included MP3s are Apple Pay, Movie 1, Rizz Sound Effect, Wrong Answer, Yes Lara Voice, Shocked, Punch, Maro Jump, Gunshot J Budden, Ding, Anime Ahh, and 67. Existing users keep their current selection when they update.

- **macOS:** The app opens as a desktop window and appears in the Dock. The 🔊 menu bar icon opens the window. Closing the window keeps the sounds active. Drag the app from the DMG into Applications. macOS requires **Input Monitoring** and **Accessibility** access under **System Settings → Privacy & Security**; quit and reopen the app after granting access.
- **Windows:** Open the Windows EXE. The desktop window contains the controls. Closing it keeps the app running in the notification area; double-click the tray icon to reopen it, or right-click the icon to quit.

These builds are unsigned and the macOS DMGs are not notarized. Your operating system may show an unknown-publisher warning. You can review and build the source below.

## Build from source

### macOS

Requires macOS 12 or newer, Swift Command Line Tools, and Python 3.

~~~sh
git clone https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-.git
cd SHORTGUN-KEYBOARD-BY-VAD-
./build-dmg.sh
~~~

The app is written in one main.swift file. build.sh compiles and ad-hoc signs it; build-dmg.sh packages it in dist/. Run these on the target Mac architecture: Apple Silicon builds arm64, Intel builds x86_64.

### Windows

Requires Windows 10/11, Python 3, and the .NET 10 SDK to build. The first build downloads the [MIT-licensed NAudio package](https://www.nuget.org/packages/NAudio).

~~~powershell
git clone https://github.com/anjudeepveerla/SHORTGUN-KEYBOARD-BY-VAD-.git
cd SHORTGUN-KEYBOARD-BY-VAD-
.\windows\build.ps1
~~~

The self-contained EXE is written to dist/ShotgunKeyboard-Windows-x64.exe. On macOS, ./build-windows.sh can cross-compile the same EXE with a local .NET 10 SDK.

## Privacy and sounds

ShotgunKeyboard responds to key-down events but does not record key names or typed text. Its status display counts events so you can tell whether monitoring works. It makes no network requests. Imported sounds are copied into the app's local support folder and your selection is stored locally.

The six built-in WAV files are synthesized from generate_sound.py using only Python's standard library. The 12 MP3s are included in the public source and downloads with the contributor's confirmed redistribution permission. See [sound asset rights](SOUND_ASSETS.md) for the distinction between these files and the MIT-licensed source code.

## License

The app's source code and generated sounds are available under the [MIT License](LICENSE). The 12 contributed MP3s have separate rights described in [sound asset rights](SOUND_ASSETS.md). The Windows build uses NAudio, also MIT licensed; see [third-party notices](THIRD_PARTY_NOTICES.md).
