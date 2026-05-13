# libboss

`libboss` is a Swift package for the ground layer of Bose's BMAP protocol, currently tailored to QC Ultra 2 HP bootstrap flows.

Current scope:

- raw BMAP packet encode/decode
- BLE framing and segmentation
- stream-safe packet extraction
- transport-agnostic bootstrap session
- typed ProductInfo bootstrap parsers

Out of scope in this milestone:

- live `CoreBluetooth` transport
- authentication
- notification subscriptions
- feature-specific higher-level APIs
- firmware transfer orchestration
