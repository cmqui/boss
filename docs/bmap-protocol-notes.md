# BMAP Protocol Notes

This document captures protocol and transport behavior used by this repository's BMAP implementation, with emphasis on the Bose QC Ultra 2 HP family and adjacent devices observed during development.

## Scope

- BMAP packet layout and operator model
- function-block discovery and bootstrap flow
- BLE service and characteristic behavior used by this codebase
- live hardware observations that affect implementation choices

## Packet Format

Raw BMAP packets use a 4-byte header followed by a payload:

- byte 0: function block ID
- byte 1: function ID within the block
- byte 2: packed `deviceId`, `portNum`, and `operator`
- byte 3: payload length
- byte 4..: payload bytes

Packed byte 2 layout:

- bits 7..6: `deviceId`
- bits 5..4: `portNum`
- bits 3..0: `operator`

Practical constraints:

- up to 4 logical device IDs
- up to 4 logical ports
- up to 255 payload bytes per raw BMAP packet

## Operators

Observed operator IDs:

- `0`: `Set`
- `1`: `Get`
- `2`: `SetGet`
- `3`: `Status`
- `4`: `Error`
- `5`: `Start`
- `6`: `Result`
- `7`: `Processing`

Typical behavior:

- `Get` requests a value and `Status` returns it
- `SetGet` writes and expects a returned value or status
- `Start` begins a longer operation
- `Processing` is an intermediate response
- `Result` completes a `Start`

## Function Blocks

Important blocks used by headphones:

- `0`: `ProductInfo`
- `1`: `Settings`
- `2`: `Status`
- `3`: `FirmwareUpdate`
- `4`: `DeviceManagement`
- `5`: `AudioManagement`
- `7`: `Control`
- `9`: `Notification`
- `16`: `Vpa`
- `17`: `Wifi`
- `18`: `Authentication`
- `20`: `Cloud`
- `21`: `AugmentedReality`
- `31`: `AudioModes`

Implementations should treat block support as runtime capability data rather than a fixed compile-time list.

## Capability Discovery And Bootstrap

The device advertises supported function blocks as a bitset. The bootstrap flow used in this repo is:

1. open the transport/session
2. query BMAP version
3. query product ID and variant
4. query supported function blocks
5. register or enable feature handling based on discovered capabilities

This matters because not every device exposes every block or function.

## Product ID And Variant

Observed payload format for product ID and variant:

- bytes `0..1`: big-endian product ID
- byte `2`: product variant

For QC Ultra 2 HP hardware tested in this repo:

- product ID: `0x4082` / `16514`
- one observed variant: `0x04`

## BLE Transport

The codebase uses the Bose BMAP GATT service:

- service: `0000FEBE-0000-1000-8000-00805F9B34FB`
- secure characteristic: `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8`
- unsecure characteristic: `D417C028-9818-4354-99D1-2AC09D074591`

### Live Hardware Behavior

Observed on macOS against a QC Ultra 2 HP:

- service discovery succeeds against the `FEBE` service
- both Bose characteristics are present
- bootstrap writes succeed on the unsecure characteristic
- notifications carrying BMAP responses arrive on the secure characteristic
- `writeWithoutResponse` is the working write mode

Observed routing:

- write characteristic: `D417C028-9818-4354-99D1-2AC09D074591`
- notify characteristic: `C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8`

Implementation consequence:

- do not assume request and response use the same characteristic
- characteristic selection may differ by operation and security requirement

### Observed Bootstrap Exchange

- write `0000010100` -> `ProductInfoBmapVersion Get`
- response `00010305312E322E30` -> `Status`, payload `"1.2.0"`
- write `0000030100` -> `ProductInfoProductIdVariants Get`
- response `00030303408204` -> product `0x4082`, variant `0x04`
- write `0000020100` -> `ProductInfoAllFblocks Get`
- response `0002030487CC23FF` -> supported function-block bitset

### Security-Dependent Requests

Observed follow-up behavior on the same hardware:

- some `Settings` requests do not behave like bootstrap traffic
- `SettingsGetAll Start` can return BMAP error payload `0x14`
- `0x14` maps to `BmapPacketError.InsecureTransport`

Practical implication:

- bootstrap can succeed over the unsecure write characteristic
- some settings traffic may still require secure-path retry behavior

## BLE Framing And Segmentation

For non-segmented BLE writes, one framing byte is prefixed ahead of the raw BMAP packet:

- byte `0`: segment header
- bytes `1..`: raw BMAP packet

Single-frame writes use header `0x00`.

For segmented writes, the segment byte layout is:

- high nibble: max segment index
- low nibble: current segment index

Examples:

- single segment: `0x00`
- two segments: `0x10`, `0x11`
- three segments: `0x20`, `0x21`, `0x22`

Final-segment detection:

- `0x00` is treated as final
- otherwise a segment is final when the high nibble equals the low nibble

Reassembly behavior:

- chunk size is inferred from the first segment length minus one framing byte
- payload bytes are copied into `segmentIndex * chunkSize`

## MTU Rules

Observed segmentation thresholds:

- segment when raw BMAP length exceeds `mtu - 4`
- use chunk payload size `mtu - 3`

That yields:

- 1 byte for the BLE segment header
- up to `mtu - 4` bytes of raw BMAP data per chunk

Constants seen during development:

- requested MTU: `55`
- large MTU constant: `104`
- Android default constant also appears in prior notes: `23`

Implementation guidance:

- do not hardcode 20-byte ATT payload assumptions
- use the negotiated MTU and the framing rules above
