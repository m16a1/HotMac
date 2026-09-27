# HotMac

A tiny macOS menu bar app that shows the hottest temperature sensor on your Mac,
and lets you watch the individual component temperatures over time.

- **Menu bar** shows the current highest reading, e.g. `58°`.
- **Menu** has exactly two items: `Show UI` and `Quit`.
- **UI**, a single window with two screens:
  - **Settings** — how often the sensors are sampled (default 2 s).
  - **Graphs** — a live chart of the component temperatures (CPU, GPU, memory,
    SSD, battery, ...), with a checkbox per series and a Clear button.

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
  transport), `Sensors.swift` (the key mapping and decoding),
  `TemperatureModel.swift` (sampling, history).
- `Sources/Sensors/System/` — the host boundary and the only code that touches
  the machine: `IOKitTransport.swift` (the kernel), `Sysctl.swift`, and
  `HostWiring.swift` (the composition root, `TemperatureModel.live()`). Excluded
  from the coverage report, because it cannot run off real hardware.
- `Sources/UI/` — `HotMacApp.swift` (the `@main` scene), `ContentView.swift`
  (the `TabView` shell), `SettingsView.swift`, `GraphsView.swift`, `UI.swift`.
- `Tests/SensorsTests/` — the suite, one file per unit under test.
- `build.py`, `test.py`, `Info.plist`, `AppIcon.png`, `Package.swift`.

`Package.swift` defines the two targets and compiles them, so a new file in
either source directory is built with no extra wiring; `build.py` only
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
transport, and the temperature model takes its SMC factory and its delivery
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
  real sensors and would pin the menu bar at a constant 61 °C. Any reading
  outside 5–120 °C is dropped too, which removes unpopulated slots that read
  exactly 0.

## Limitations

- It uses an undocumented IOKit interface, which could change in a future macOS
  release. Verified on macOS 26 on an M5 Max.
- The named HID sensors that some tools show (for example "NAND CH0 temp")
  return -1 to unprivileged processes, so they are not used.

## License

MIT. See [LICENSE](LICENSE).
