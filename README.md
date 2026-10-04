# HotMac

A tiny macOS menu bar app that shows the hottest temperature sensor on your Mac,
and lets you watch the individual component temperatures over time.

- **Menu bar** shows the current highest real-sensor reading, e.g. `58°C`, in
  plain text while the machine is cool and on a colored capsule once it passes
  60 °C (yellow), 80 °C (orange) and 95 °C (red).
- **Menu** lists the four screens — `Temperatures`, `Processes`, `Fans` and
  `Settings` — each
  opening the window straight to it, then `About HotMac` (a window with the app
  icon at 512×512 px, the name, and the version) and `Quit`.
- **UI**, a single window with four screens:
  - **Settings** — how often the sensors are sampled (default 2 s), how many
    samples the graph keeps (default 900), and a
    status section (chip, highest,
    last update, whether the OS is throttling the CPU for heat, and how busy the
    GPU is).
  - **Processes** — a live top-like table of the processes loading the machine
    (name, pid, CPU share, GPU share, memory), busiest first. CPU is a share of
    one core, so a process spread over several cores can read above 100%; the GPU
    share is a percentage of the whole device. A row is placed by whichever of its
    two shares is larger. The GPU share is never a dash: a process that has never
    reached the GPU is using none of the device and reads 0. The kernel will not
    describe another user's process, so `WindowServer` and friends have no CPU or
    memory of their own; while this screen is up those two are read from `ps`, and
    a dash there means even `ps` had no answer.
  - **Fans** — a live chart of each cooling fan's speed in RPM, with the current
    speed and reported range for each fan.
  - **Temperatures** — a live chart of the component temperatures (CPU, GPU,
    memory, SSD, battery, ...), one color per series, with a checkbox per series
    and a Clear button. The checkboxes are split into **Physical** series — the
    sensors measuring the hardware — and **Virtual** ones, the readings Apple
    computes from them (the virtual die, the voltage probes and their mirror
    bank, the memory, system, ambient and voltage rails). A derived number
    therefore cannot be read as a measurement.
    Hovering a series explains what that sensor measures,
    and the checked series are remembered between launches.

## Install

Two free ways. The app is ad-hoc signed but **not notarized** — there is no paid
Apple Developer certificate behind it — so a downloaded copy needs a one-time
Gatekeeper step.

**Build from source (no warnings).** A locally built app is never quarantined:

```bash
./build.py
open HotMac.app
```

**Download a release.** Grab `HotMac-<version>.dmg` (drag the app onto the
Applications shortcut) or `HotMac-<version>.zip` (unzip it and move
`HotMac.app` into Applications) from Releases. On first launch macOS refuses to
open it, because it cannot check the developer. Clear the quarantine flag once,
either in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/HotMac.app
```

or in the GUI: try to open it, then **System Settings → Privacy & Security →
Open Anyway**. The old right-click → Open shortcut no longer bypasses this for
unnotarized apps on macOS 15 and later.

It is not in Homebrew; build from source or use a release.

## Requirements

- macOS 14 or later on Apple silicon.
- To build: a Swift toolchain. Xcode Command Line Tools is enough; full Xcode
  is not required.

## Build and run

```bash
./build.py          # compile and assemble HotMac.app
open HotMac.app     # launch
pkill -x HotMac     # stop
```

The app is a menu bar extra (`LSUIElement`), so it has no Dock icon. Look for
the temperature in your menu bar. The Finder and Launchpad icon is rendered
from `AppIcon.png` at build time; drop in a replacement square PNG of the same
name and rebuild to change it.

## Layout

`Sources/` is split into a data layer and a presentation layer:

- `Sources/Sensors/` — `SMC.swift` (the protocol client, over an injected
  transport), `SMCSession.swift` (one connection plus the key metadata read with
  it), `Sensors.swift` (the key mapping and decoding), `FanReading.swift` (the
  fan speed keys and their decoding), `TemperatureLevel.swift`
  (the heat bands the menu bar flags), `ThrottleState.swift` (how far the OS is
  throttling for heat), `SeriesColor.swift` (the chart palette, as numbers
  rather than colors so it can be tested), `ProcessCounters.swift` (two CPU and
  memory counter snapshots turned into ranked process readings),
  `ProcessReading.swift` (one process's row), `GPUUtilization.swift` (the
  whole-GPU utilization the accelerator publishes), `GPUClientCounters.swift`
  (the per-process GPU totals the driver keeps, and the shares two samples make),
  `GPUShare.swift` (every GPU client's share for one tick, with the name the
  driver recorded), `SampleError.swift` (a
  tick failure tagged with the stage that broke), `TemperatureModel.swift`
  (gathering a reading, publishing it, history), plus the DEBUG-only
  `PreviewData.swift` and `TemperatureModel+Preview.swift`.
- `Sources/Sensors/System/` — the host boundary and the only code that touches
  the machine: `IOKitTransport.swift` (the kernel), `Sysctl.swift`,
  `Throttle.swift` (the OS throttling level), `ProcessReader.swift` (the running
  processes, through libproc), `GPUReader.swift` (the accelerator's utilization,
  through IOKit), `GPUClientReader.swift` (the per-process GPU totals, from the
  driver's clients in the IORegistry), and
  `HostWiring.swift` (the composition root, `TemperatureModel.live()`). Excluded
  from the coverage report, because it cannot run off real hardware.
- `Sources/UI/` — `HotMacApp.swift` (the `@main` scene), `MenuBarBadge.swift`
  (the menu bar label), `AboutView.swift` (the About window), `ContentView.swift`
  (the `TabView` shell), `SettingsView.swift`, `ProcessesView.swift`,
  `FansView.swift`, `GraphsView.swift`,
  `ChartPalette.swift`, `UI.swift`.
- `Tests/SensorsTests/` — the suite, one file per unit under test.
- `build.py`, `test.py`,
  `Info.plist`, `AppIcon.png`, `Package.swift`.

`Package.swift` defines the targets and compiles them, so a new file in
any source directory is built with no extra wiring; `build.py` only
assembles the bundle around the executable and renders `AppIcon.png` into
`Contents/Resources/AppIcon.icns`. Both scripts are Python, which ships in the
same Command Line Tools package as `swiftc`.

## Tests

```bash
./test.py             # the Swift Testing suite
./test.py --coverage  # same, plus an LLVM coverage report
```

The suite uses [Swift Testing](https://developer.apple.com/xcode/swift-testing/)
and needs no hardware and no host state: the SMC client is driven through a fake
transport, and the temperature model takes its SMC factory, its process, GPU and
GPU-client reads,
and its delivery
queue as parameters. `Tests/SensorsTests/` holds one suite per unit under test,
with the shared fakes in `Support/`.

It is built as an executable rather than a `.testTarget`, because `swift test`
cannot run swift-testing with only the Command Line Tools installed: SwiftPM
builds the test bundle but has no `xctest` host to load it, so the run reports
zero tests and exits 0. `Package.swift` explains the details.

Coverage is measured over `Sources/Sensors/` minus the `System/` directory, and
that set is held at 100%. `Sources/Sensors/System/` is the host boundary (IOKit
and `sysctl`); its behaviour depends on the machine, so it is excluded by path.

## How it works

HotMac reads the SMC (System Management Controller) directly. It opens the
`AppleSMC` (`AppleSMCKeysEndpoint`) IOKit user client and reads the sensor
table itself, the same way other macOS monitoring tools do.

- Sensor values live in a key-value table inside the SoC. The kernel exposes it
  through one operation selector whose sub-operation is chosen by a byte inside
  the request struct. There is no bulk read, so this is one kernel call per
  sensor.
- Every temperature sensor is a key beginning with `T`. On first launch the app
  walks the table once to learn each key's size, format, and endianness, then
  reads only the value on each tick. A tick is about 10 ms of CPU, so the
  default 2 s refresh costs well under 1% of one core.
- Keys are mapped to named components in `Sources/Sensors/Sensors.swift`. The GPU,
  memory, uncore, and package are recognised by prefix (`Tg*`, `Tm*`, `TUD*`,
  `TN*`); the CPU cores need a per-chip list because Apple reuses the `Tp`/`Te`/
  `Tf` prefixes for different blocks across generations.
- The GPU fabric `Tf?5`/`Tf?6` slots are each block's minimum and maximum rather
  than a point reading, and they update only rarely (on an M5 Max a 284 s
  full-load run moved `Tf06` once), so a stale value could sit at the top of the
  hottest list and hide the live hotspot; they are excluded by name. The
  `TVMX`/`TVmS`/`TVms` "Virtual Memory Summary" keys are also excluded: they are
  derived summaries floored at exactly 61 °C, so at idle they always outrank the
  real sensors and would pin the menu bar at a constant 61 °C. Apple's whole
  `TV*` block is skipped by the ranking for the same reason (computed summaries
  and power-delivery rails, not diodes), though it still appears as a graph
  series. Any reading outside 5–120 °C is dropped too, which removes unpopulated
  slots that read exactly 0.
- The menu bar emphasizes the reading by band, using the thresholds in
  `Sources/Sensors/TemperatureLevel.swift`: plain text below 60 °C, then a
  yellow, orange and red capsule. The label is drawn by `MenuBarBadge` and given
  to the system as an image, because a menu bar extra renders its label as a
  monochrome template image, which discards any tint applied to the text.
- Throttling comes from `ProcessInfo.thermalState`, which the OS raises from
  `nominal` to `fair`, `serious` and `critical` as it holds the CPU back for
  heat. It is read next to the sensors on each tick and shown in the Settings
  status section, colored from `serious` up.
- GPU utilization comes from the accelerator's `PerformanceStatistics` in the
  IORegistry, read through IOKit on each tick. It is one figure for the whole
  device, shown above the process table and in the Settings status section. It is
  the number Activity Monitor's GPU graph and tools like `asitop` read.
- The per-process GPU share comes from the driver's own accounting, also in the
  IORegistry: every process that has reached the GPU owns an `AGXDeviceUserClient`
  that carries its accumulated GPU time and the pid that opened it. Two samples
  give the time used over the interval, which as a fraction of that interval is
  the process's share of the **whole** device. Those totals partition the GPU, so
  the shares add up to the device figure above them and a single process's share
  is directly comparable with it. Reading them needs no privileges, so the app
  has no privileged path at all, and it costs about 15 ms per tick on an M5 Max.
  A process's GPU work is credited to the process
  that submitted it, which for a helper process means the helper: hardware video
  decoding, for instance, is attributed to `VTDecoderXPCServ` rather than to the
  app showing the video.
- Fan speeds come from the SMC as well. Each fan is a family of keys numbered
  from zero, of which the app reads three: `F0Ac` (current), `F0Mn` (minimum)
  and `F0Mx` (maximum). They are read beside the temperatures on each tick and
  charted in the Fans screen, on the same rolling history as the temperatures.
  A fan that reads 0 RPM is reported as stopped, not hidden, which is normal on
  Apple silicon at idle.
- The process table comes from libproc, not the SMC. Each tick reads every
  process's cumulative CPU time and resident memory, and the share of a core is
  the CPU time gained since the previous tick divided by the wall time between
  them. A process seen for the first time has no baseline and reads 0% for one
  tick. The list is the busiest dozen; a process the kernel will not describe to
  an unprivileged caller — every process owned by another user — has no CPU or
  memory figure of its own, so those two are read from `ps` while the Processes
  screen is up. `ps` needs no privileges either, so the app still has no
  privileged path.
- The GPU column is joined onto the table by pid, and a process the driver's
  clients do not mention reads 0 rather than a dash: it has not reached the GPU,
  which is using none of it. Rows also
  come the other way round: a process the kernel hides from us but the driver
  names, `WindowServer` above all, gets a row of its own, because otherwise its
  GPU time would be missing from the column
  entirely (measured: the column read 19.5% of a 37% device until that row was
  added, `WindowServer` alone holding 17.2%). Its CPU and memory, which the kernel
  will not give us, are read from `ps` while the screen is up. The GPU work of a
  helper process is
  credited to the helper rather than to the app that spawned it.
- A row is ranked by whichever of its CPU and GPU shares is larger, because the
  two are shares of different things — one core, and the whole device — and
  neither key alone behaves: ranking by CPU buries a GPU hog under a dozen idle
  rows, and ranking by GPU puts a process drawing a fraction of a percent above a
  process using several cores. On a machine whose GPU is idle no row has a GPU
  share, so the table is exactly the CPU ranking it has always been.

## Limitations

- It uses an undocumented IOKit interface, which could change in a future macOS
  release. Verified on macOS 26 on an M5 Max.
- The per-process GPU totals are a driver-internal property rather than a
  documented API, so a macOS release that renames or drops them would leave the
  GPU column and list blank; the rest of the app is unaffected.
- The name a GPU client carries comes from the kernel and is truncated to fifteen
  characters, so a fully-qualified helper name reads short (`com.apple.WebKi`).
  Rows in the table show the process's own full name; entries in the GPU list,
  which may be for a process outside those rows, show the truncated one.
- The shares are as accurate as the driver's clock: measured against the
  accelerator's own `Device Utilization %`, the sum of the GPU column over every
  GPU client read 36.8% against 37–40% and, under load, 100.7% against 99–100%.
  That figure is a different counter over a different window rather than one
  derived from the column, so a point or two between them is expected, not a
  missing process. The table is also capped at twelve rows, so a process using a
  fraction of a percent of the GPU can fall outside it.
- It shows nothing about **energy**. Per-process energy impact exists only in
  `powermetrics`' privileged output, and reading it would mean running a helper
  as root; the GPU share replaced that column instead.
- The named HID sensors that some tools show (for example "NAND CH0 temp")
  return -1 to unprivileged processes, so they are not used.

## Releasing

The version lives in `Info.plist` (`CFBundleShortVersionString`). To cut a
release, bump it, commit, and push a matching tag:

```bash
./build.py --dist   # writes dist/HotMac-<version>.zip and .dmg
git tag v0.1.0
git push origin v0.1.0
```

The `Release` GitHub Actions workflow (`.github/workflows/release.yml`) runs
`./build.py --dist` on the tag and attaches both archives to a new release.
Nothing is signed or notarized, so it needs no secrets.

## License

MIT. See [LICENSE](LICENSE).
