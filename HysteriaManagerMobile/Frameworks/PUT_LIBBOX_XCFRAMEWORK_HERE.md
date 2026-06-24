# Drop `Libbox.xcframework` in this folder

The packet-tunnel extension links `Frameworks/Libbox.xcframework` (sing-box compiled
for Apple platforms). It is **not** included in the repo — you build it **on macOS**.

> ⚠️ This **must** be done on a Mac with Xcode. `Libbox.xcframework` is an iOS/Apple
> framework: gomobile cross-compiles to `arm64-apple-ios` and the `.xcframework` is
> assembled with Apple-only tooling (`xcodebuild -create-xcframework`). It cannot be
> built on Linux.

## Easiest: run the script (on your Mac)

```sh
cd HysteriaManagerMobile/Frameworks
brew install go            # if needed (Xcode must already be installed)
./build-libbox.sh          # builds iPhone (device + Simulator) and copies it here

# device-only = fastest build:
LIBBOX_PLATFORM=ios ./build-libbox.sh
```

The script pins **sing-box v1.13.13** by default — the version whose Libbox API matches
the Swift glue. Don't build from the `testing` branch; its API differs and won't compile.

### How long / how big?

- **Git clones:** sing-box ~40–80 MB (full clone), sing-box-for-apple shallow ~20 MB.
- **Go modules (one-time):** ~0.5–1 GB into `~/go/pkg/mod` (gvisor, quic-go,
  wireguard, tailscale, …). Reused on every later build.
- **The slow part is compiling**, not downloading. `make lib_apple` builds **5 Apple
  slices** (ios, iossimulator, tvos, tvossimulator, macos). The script builds only
  `ios,iossimulator` by default (~60% less), or set `LIBBOX_PLATFORM=ios` for device-only.
- First build: many minutes (cgo-compiling gvisor/quic/etc.). Rebuilds are much faster.

## Or do it by hand

sing-box uses its **own gomobile fork** and a build helper (not upstream `gomobile bind`):

```sh
git clone https://github.com/SagerNet/sing-box.git
git clone https://github.com/SagerNet/sing-box-for-apple.git   # build output lands here
cd sing-box
git checkout v1.13.13        # REQUIRED: matches the Swift glue (don't use `testing`)

make lib_install   # installs github.com/sagernet/gomobile (the fork) + gobind

# Build ALL Apple platforms (slow):
make lib_apple     # = go run ./cmd/internal/build_libbox -target apple

# …or build only iOS (much faster) by calling the helper directly:
go run ./cmd/internal/build_libbox -target apple -platform ios,iossimulator
                   # → ../sing-box-for-apple/Libbox.xcframework
```

Then copy the result here:

```
cp -R ../sing-box-for-apple/Libbox.xcframework \
      <path>/HysteriaManagerMobile/Frameworks/Libbox.xcframework
```

`make lib_apple` builds for `ios, iossimulator, tvos, tvossimulator, macos` with tags
`with_gvisor, with_quic, with_wireguard, … , with_dhcp, grpcnotrace` — `with_quic`
is what enables the hysteria2 outbound.

## After adding the framework

- Open `HysteriaManagerMobile.xcodeproj` and build (no XcodeGen needed).
- The `Libbox…Protocol` Swift signatures in `Tunnel/PlatformInterface.swift` and the
  `LibboxSetup` / `LibboxNewCommandServer` calls in `Tunnel/PacketTunnelProvider.swift`
  were adapted verbatim from `SagerNet/sing-box-for-apple`. If your built version's
  generated API differs, reconcile against that repo's
  `Library/Network/ExtensionProvider.swift` + `ExtensionPlatformInterface.swift`.
  Pinning `SINGBOX_REF` to the tag sing-box-for-apple currently uses avoids drift.
