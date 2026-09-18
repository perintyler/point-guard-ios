# point-guard-ios

Point Guard on a phone — read the book, message the supervisor, adjust
settings. A client of the `point-guard` service; it ships no backend of its own.

## Reaching the Mac

point-guard binds `127.0.0.1:3868`. There is **no route to that port** from
anywhere but the Mac itself.

| | Base URL | Secret |
|---|---|---|
| Simulator | `http://127.0.0.1:3868` | **required** |
| Device | `https://barry-mac.tail5cb2f2.ts.net:8447` | **required** |

The device path goes over the user's PERSONAL tailnet to a userspace
`tailscaled` sidecar (separate from the Mac's work Tailscale client), which
terminates TLS and proxies straight to point-guard on `127.0.0.1:3868`. Because
it proxies directly, there is no `Host` header and no site block to select.

**The certificate is a real Let's Encrypt one**, issued for the tailnet name, so
there is no certificate warning on the phone and nothing to pin or trust
manually.

**The secret is required on both paths.** Unlike the main Barry API — which sits
behind a proxy that injects the secret for loopback callers — nothing fills it
in here. Every route except `/health` answers an unauthenticated caller with
403, even from loopback.

> **This app previously had no working device path at all.** The device default
> was `http://100.101.38.91:3868` plus a `Host: barry.lan` header. That named a
> **raw service port**: point-guard binds loopback only, so nothing listens on
> `:3868` across any tailnet, and `100.101.38.91` is on the WORK tailnet that
> the phone is not a member of. It was not a stale address that used to work —
> it could never have worked. The `:8447` serve endpoint is what creates a
> device path for the first time.

### App Transport Security

The app sets **`NSAllowsLocalNetworking`**, not `NSAllowsArbitraryLoads`.

The device path is genuine HTTPS and needs no exception at all. The one
remaining cleartext caller is the *simulator*, which talks to point-guard on
`http://127.0.0.1:3868` — and ATS blocks that unless permitted.
`NSAllowsLocalNetworking` permits exactly loopback and link-local, and nothing
routable, so a misconfigured `http://` tailnet URL still fails loudly instead of
silently downgrading.

### Test connection

Settings probes rather than accepting a string. The user switches tailnets, so
the failures that need different fixes must not collapse into one message:

| What you see | What is actually wrong |
|---|---|
| cannot resolve the host | this phone is on a different tailnet, or the sidecar is down |
| resolved, cannot connect | the Mac is on the tailnet but not serving `:8447` |
| reached, 403 | the network path **works** — the secret is missing or wrong |
| connected, N sessions | everything works |

It calls `/health` *and* `/book`: the first is the only unauthenticated route, so
it separates "server down" from "bad secret"; the second proves the credential
actually works. A probe calling only one of them could not tell those apart.

## Build and test

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
export BARRY_SECRET="$(/usr/libexec/PlistBuddy -c \
  'Print :EnvironmentVariables:BARRY_SECRET' ~/Library/LaunchAgents/com.barry.api.plist)"
./scripts/test.sh
```

**Export `BARRY_SECRET` first.** xcodebuild does not pass the invoking shell's
environment to the test process, so the scheme forwards it explicitly (see
`project.yml`). Without it the authenticated live tests `XCTSkip` — and a skip
reads identically to a pass. `scripts/test.sh` says which suite you are getting
before it runs, and prints the skip count after.

Always build with `-derivedDataPath .build-barry-ios` (as `scripts/test.sh`
does). A bare `xcodebuild` writes to Xcode's shared DerivedData, and installing
from the other path silently installs a stale binary.

## Layout

| Path | What it is |
|---|---|
| `App/Models.swift` / `DebriefModels.swift` | the wire shapes |
| `App/PointGuardClient.swift` | `URLSession` client over point-guard's routes |
| `App/ServerConfig.swift` | base URL + keychain secret |
| `App/ConnectionProbe.swift` | what "Test connection" actually proved |
| `App/AppStore.swift` | app state |
| `App/Views/` | book, message, debrief, settings |
| `Tests/` | decoding vs real payloads; live API integration; probe classification |
