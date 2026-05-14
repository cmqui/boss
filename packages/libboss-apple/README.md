# libboss-apple

`libboss-apple` provides the Apple/CoreBluetooth transport layer for [`libboss`](../libboss/README.md).

Current scope:

- `CoreBluetooth` central connection flow for Bose BLE peripherals
- Bose BMAP service and characteristic discovery
- ATT-MTU-aware BLE writes
- notification ingestion into `libboss` transport frames
- executable bootstrap runner for live hardware validation

Observed Bose QC Ultra 2 HP behavior on macOS:

- service UUID: `0000FEBE-0000-1000-8000-00805F9B34FB`
- unsecure characteristic: `D417C028-9818-4354-99D1-2AC09D074591`
- secure characteristic: `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8`
- bootstrap writes should target the unsecure characteristic
- bootstrap notifications arrive on the secure characteristic
- `writeWithoutResponse` is the working write mode on real hardware

## Running

```bash
cd packages/libboss-apple
swift run boss-bootstrap --name Bose --timeout 20
```

Useful options:

- `--identifier <uuid>` to target a specific peripheral
- `--characteristic automatic|unsecure|secure` to override write-characteristic preference
- `--timeout <seconds>` to adjust scan timeout

## CLI

The user-facing CLI now lives in [`../bossctl`](../bossctl/README.md). Keep Apple transport and typed protocol helpers in this package; keep command parsing and UX in `bossctl`.

Debug logging:

- `LIBBOSS_APPLE_DEBUG=1` enables lifecycle and discovery logs
- `LIBBOSS_APPLE_DEBUG_PACKETS=1` additionally logs raw BLE write/notification frames

Example:

```bash
LIBBOSS_APPLE_DEBUG=1 LIBBOSS_APPLE_DEBUG_PACKETS=1 \
  swift run boss-bootstrap --name Bose --timeout 20
```
