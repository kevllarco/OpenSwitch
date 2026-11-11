# Shared setup transport check

This standalone local check starts two in-memory paired transport endpoints on the same Mac, exchanges sample setup data over the actual Bonjour/TLS transport, and checks acknowledgement, rejection, and an unavailable receiver. It does not open Logitech devices, alter app settings, or switch the monitor. The test key is fixed sample data.

Build the local development app first with `python3 ../scripts/build-local.py --build-number 46.0` from the repository root. Then compile and run:

```sh
swiftc -target arm64-apple-macos14.0 -parse-as-library -swift-version 5 \
  -I "$HOME/Library/Caches/OpenSwitch/build/modules" \
  -L "$HOME/Library/Caches/OpenSwitch/build/OpenSwitch.app/Contents/Frameworks" \
  -Xlinker -rpath -Xlinker "$HOME/Library/Caches/OpenSwitch/build/OpenSwitch.app/Contents/Frameworks" \
  -lTopologyCore -lDisplayDomain Apps/OpenDisplay/Sources/SharedSetupTransport.swift \
  Tools/SharedSetupChecks/TransferCheck.swift -o /tmp/openswitch-transfer-check
/tmp/openswitch-transfer-check
```

The expected output is `acknowledged=true`, `rejected=true`, and `unavailable=true`. A successful local check does not establish that two physical Macs can discover each other, persist settings, or switch hardware.
