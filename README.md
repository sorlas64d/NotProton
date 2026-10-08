# NotProton, Sikarugir edition

Play Windows-only Steam games in the **macOS Steam client**, using the free
[Sikarugir](https://github.com/Sikarugir-App/Sikarugir) Wine engine. No CrossOver license needed.

This is a fork of [NotProtonNot/NotProton](https://github.com/NotProtonNot/NotProton), which
brings Steam Play (the Proton experience from Linux) to macOS Steam but runs games with CrossOver,
a paid app. This fork adds Sikarugir as a second runtime. CrossOver keeps working as before;
you only need one of the two.

- Windows-only games install and launch from Steam like native ones. No wrappers, no bottles.
- Games talk to the macOS Steam client through Valve's Proton bridge, as in upstream NotProton.
- Graphics through DXMT, D3DMetal or DXVK, chosen per game from Steam.

Confirmed working: How to Fish, on macOS 27 with Sikarugir's `WS12WineSikarugir11.0` engine.

> [!IMPORTANT]
> There are no prebuilt downloads of this version. You build the app yourself, with one
> script, as described below. The first build takes 30 to 45 minutes.

## Contents

- [Requirements](#requirements)
- [Installing](#installing)
- [Playing games](#playing-games)
- [Troubleshooting](#troubleshooting)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [How this fork differs from upstream](#how-this-fork-differs-from-upstream)
- [Credits and licenses](#credits-and-licenses)

## Requirements

**To play:**

- A Mac with Apple Silicon, on macOS 26 or later
- [Rosetta 2](https://support.apple.com/en-us/102527): `softwareupdate --install-rosetta --agree-to-license`
- Steam for Mac, on a client version NotProton supports (see [Steam updates](#steam-updates))
- [Sikarugir](https://github.com/Sikarugir-App/Sikarugir) with the **WS12WineSikarugir11.0**
  engine, revision 0 or 1

**To build:**

- [Xcode](https://apps.apple.com/app/xcode/id497799835), the full app. The Command Line Tools
  alone are not enough.
- [Homebrew](https://brew.sh)
- About 10 GB of free space and an internet connection

## Installing

### 1. Install Sikarugir and get its engine

```sh
brew install --cask Sikarugir-App/sikarugir/sikarugir
```

Open **Sikarugir Creator** and create one wrapper using the **WS12WineSikarugir11.0** engine.
NotProton doesn't use the wrapper. Creating it makes Sikarugir download the two things NotProton
needs:

- the engine, into `~/Library/Application Support/Sikarugir/Engines/`
- the Template (graphics layers and libraries), into `~/Library/Application Support/Sikarugir/Template/`

You can delete the wrapper afterwards. Keep Sikarugir's `Engines` and `Template` folders until
NotProton has set itself up (step 5).

### 2. Prepare Xcode and Homebrew

Install Xcode, then accept its license and install its first-launch components. These commands
call Xcode directly, so they work even when your active developer tools are the Command Line
Tools:

```sh
sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -license accept
sudo /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -runFirstLaunch
brew install mingw-w64 bison cmake
```

### 3. Build the app

```sh
git clone https://github.com/sorlas64d/NotProton.git
cd NotProton
./build-sikarugir-app.sh
```

The script checks every prerequisite first and tells you how to fix anything missing. Then it
builds everything in order. If it stops partway, fix what it reports and run it again; finished
steps are skipped.

The result is `out/NotProton.app`. Building changes nothing outside the `NotProton` folder.

### 4. Install NotProton into Steam

1. **Quit Steam completely** (Steam > Quit Steam).
2. **Open `out/NotProton.app`.** It isn't notarized, so the first time macOS may refuse to open
   it. Right-click it and choose **Open**, or allow it under System Settings > Privacy & Security.
3. On the **Status** tab, click **Install** in the Steam section.

Install patches Steam to load NotProton and keeps a backup so it can be undone. It also downloads
a few components from Valve. Then it sets up the compatibility tool from your Sikarugir engine,
which takes about a minute.

### 5. Check the compatibility tool

In the **Sikarugir** section of the Status tab:

- The `WS12WineSikarugir11.0` row should read **Engine Sikarugir 11.0 revision 0** (or 1) in green.
- If it says **not set up**, click **Set Up** on that row.
- A **CrossOver: Not found** row is expected if you don't have CrossOver.
- If the components section lists anything missing, click **Fetch Valve Binaries**.

NotProton keeps its own copy of the engine and the Template's libraries, so Sikarugir updating or
replacing its Template later doesn't affect it.

### 6. Block Steam updates (recommended)

Turn on **Block Steam client updates** on the Status tab. NotProton supports specific Steam
client builds, and a Steam update can stop it working until NotProton is updated too.

## Playing games

Start Steam, install a Windows-only game and press **Play**. That's all: NotProton assigns itself
to any game that only has a Windows version.

- **Games that also have a Mac version** run natively as usual. To run the Windows version
  instead, open the game's **Properties > Compatibility** and choose the tool named after your
  engine, such as **Sikarugir 11.0 revision 1**.
- **To stop NotProton running a game**, choose "none" in the same place.

### Graphics

Each game's **Properties > Compatibility** page has a **Graphics** option:

| Option | What it uses | Notes |
|--------|--------------|-------|
| **Automatic** | DXMT | The default, and Sikarugir's default. Try this first. |
| **DXMT** | DirectX 10 and 11 translated to Metal | Supports DirectX 11.1. |
| **D3DMetal** | Apple's DirectX 11 and 12 to Metal, from the Game Porting Toolkit | Try it when a game misbehaves on DXMT, or for DirectX 12 games. |
| **DXVK** | DirectX 9 to 11 translated to Vulkan, then to Metal | Supports DirectX 11.0. |
| **WineD3D** | Wine's own renderer, on OpenGL | Can't run DirectX 11 games on macOS. Only for old DirectX 9 games. |

The same page has a few switches:

- **MSync:** faster thread synchronization. Turn it on if a game stutters or stalls under load.
- **Metal HUD:** shows frame rate and frame times.
- **High Resolution:** renders at full Retina resolution.

### Expect some stutter at first

Games often stutter the first time they show a new effect, area or menu, while the shaders are
translated to Metal. macOS caches the results, so it settles as you play. If the stutter doesn't
go away, try turning on MSync or switching the graphics option to D3DMetal.

## Troubleshooting

When something goes wrong, these two logs say what happened:

- `<Steam library>/steamapps/compatdata/<app id>/notproton-run.log`: the launch steps. A line near
  the top reads `runner=sikarugir renderer=...`.
- `~/Library/Application Support/notproton/launchers/<app id>/notproton-wine.log`: Wine's output
  while the game runs.

The app ID is the number in the game's Steam store URL.

| Problem | Fix |
|---------|-----|
| The game says it **failed to initialize graphics** or **DirectX 11** | Set its Graphics option to Automatic, DXMT or D3DMetal, not WineD3D. |
| The engine row says **Not supported** | You have a revision of WS12WineSikarugir11.0 this version doesn't know yet. Supported: revisions 0 and 1. Open an issue with the engine's file name and its `version` file. |
| **Template not found** | Open Sikarugir Creator and create a wrapper once (step 1). |
| **This game needs its prefix rebuilt** | The game's Wine prefix was last run by a different tool (CrossOver or Sikarugir, or another build of either). On the **Prefixes** tab, select the game and choose **Rebuild Prefix**. Saves are kept. |
| macOS won't open **NotProton.app** | Right-click it and choose Open, or allow it under System Settings > Privacy & Security. |
| Games stopped launching after a **Steam update** | Your Steam client may now be newer than NotProton supports. Update this repository (see [Updating](#updating)) and keep Steam updates blocked. |
| The build script fails | It prints what is missing and how to fix it. Run it again once fixed. |

### Steam updates

NotProton patches the Steam client and recognises the client builds it was made for. Upstream
NotProton lists the client builds it supports in its own README below. A newer Steam may need a newer
NotProton, which is why blocking Steam updates is recommended.

## Updating

**Don't accept update offers from inside the NotProton app.** The built-in updater checks the
original project's releases. Accepting replaces this version with one that has no Sikarugir
support.

To update this version instead:

```sh
cd NotProton
git fetch origin
git reset --hard origin/sikarugir-runner
./build-sikarugir-app.sh
```

This branch is regularly rebased onto the original project, so `git pull` can refuse to update it.
`reset --hard` simply moves you to the latest version; it discards changes you made to files in the
repository yourself.

Then quit Steam, open the new `out/NotProton.app`, and click **Install** in the Steam section,
which then reads "Update available".

## Uninstalling

In NotProton's Status tab:

- **Repair** puts the Steam app back to its original state.
- **Remove** takes NotProton out of Steam completely.

Then delete NotProton.app and the cloned folder. Sikarugir can be removed with
`brew uninstall --cask sikarugir`.

## How this fork differs from upstream

- **A second runtime.** NotProton can set itself up from a Sikarugir engine instead of a
  CrossOver bundle. It unpacks the engine with copies of the Template's libraries, graphics layers
  and Vulkan drivers.
- **The ntdll patch** that lets games talk to Steam is pinned for Sikarugir's Wine 11.0 builds.
  `resolve.py` learned the shapes that build uses.
- **lsteamclient is built a second time** against Wine 11.0 (`make bridge-sikarugir`), since
  CrossOver's runtime is Wine 11.15.
- **The launch script** detects a Sikarugir runner, sets the environment its engine needs, maps
  the Graphics option to DXMT, D3DMetal or DXVK, and relies on upstream's record of which
  build last ran each game's prefix.
- **Sikarugir builds are compatibility tools of their own**, named after the engine
  ("Sikarugir 11.0 revision 1") beside any CrossOver builds, so a game can use either.
- **`build-sikarugir-app.sh`** builds the whole app in one step.

CrossOver users can use this version too: everything CrossOver-related behaves as upstream does.

## Credits and licenses

- **NotProton** by [NotProtonNot](https://github.com/NotProtonNot/NotProton). This fork only
  adds Sikarugir support.
- **Sikarugir** by the [Sikarugir team](https://github.com/Sikarugir-App/Sikarugir), with engines
  maintained by Gcenx. NotProton uses the engine and Template from your own Sikarugir install and
  redistributes neither.
- **D3DMetal** is Apple's and closed source. Its license doesn't allow redistribution, so it only
  ever comes from your local Sikarugir Template. **DXMT**, **DXVK** and **MoltenVK** are open
  source and also come from there.
- **lsteamclient** and the steam helper come from Valve's [Proton](https://github.com/ValveSoftware/Proton).

See [NOTICE](NOTICE) for license details. The original README follows.

---

# NotProton

NotProton enables the Steam Play experience from Linux Steam in the macOS Steam client.

This is done by forcibly enabling the Steam Play functionality in macOS Steam (which is
present and inert) as well as by porting some components of Valve's Proton to macOS.

This tool is intended to be used with Steam Client 1788652215 or 1790121765 and **CrossOver 26.3 or CrossOver Preview
20261006 or 2026082**. Both the FEX and the Rosetta versions are supported. I recommend using the FEX version of the 
Preview 20261006, as it includes both the FEX version as well as the Rosetta one. 

The macOS app itself is located in the ```app``` folder. The core logic is in ```dylib```.
```lsteamclient``` is a macOS port of Valve's lsteamclient. ```steam-shim```is a port of Valve's
steam-helper from Proton 9. ntdll-patch patches the copy of CrossOver that the app
makes/places in the ```~/Library/Application Support/notproton/runners/``` folder so that
lsteamclient is loaded.

This release is coming several days past when I wanted to release it, so the
documentation is quite sparse. Sorry about that, I'll improve it shortly. For real this time.

Please read NOTICE for license information.

Please open issue reports with any issues. PRs are welcome and encouraged. Contributions policy to come shortly.
