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
./build.sh          # compile Sources/ into HotMac.app
open HotMac.app     # launch
pkill -x HotMac     # stop
```

The app is a menu bar extra (`LSUIElement`), so it has no Dock icon. Look for
the temperature in your menu bar.

## Tests

```bash
./test.sh           # 58 checks over the decoding and mapping logic
```

The tests need no framework or package manager: they compile `Tests/main.swift`
together with the sources and assert directly. They cover value decoding, the
key-to-component mapping, the static-register exclusion, the plausibility
filter, group averaging, and the menu bar label. Reading the real SMC is not
unit-tested, because it only works against the hardware.

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
- Keys are mapped to named components in `Sources/Sensors.swift`. The GPU,
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
