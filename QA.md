# QA — point-guard-ios

Full suite: `./scripts/test.sh`. Export `BARRY_SECRET` first — see README. The
script says whether the service is reachable and whether the secret is set
*before* it runs, because the live tests `XCTSkip` on either, and a skip reads
identically to a pass in the summary line.

Recorded run: **44 tests, 0 failures, 0 skips.**

## Coverage

| Layer | File | Talks to | What it proves |
|---|---|---|---|
| Decoding | `Tests/ModelsTests.swift` (`ModelsTests`) | fixtures from live responses | the wire shapes decode, including the hostile bits |
| Debrief | `Tests/DebriefModelsTests.swift` | nothing — pure logic | the debrief shapes and their empty states |
| Integration | `Tests/ModelsTests.swift` (`LiveAPITests`) | the real service on :3868 | book, message history, and that a valid token gets 404 (not 403) on an unknown route |
| Probe | `Tests/ConnectionProbeTests.swift` | `URLError` values, a stub, plus the real :3868 | "Test connection" tells its failure modes apart |

## Verified negative controls

Both were run and confirmed red, then reverted.

| # | Check | Break it by | Confirmed result |
|---|---|---|---|
| 1 | a 403 reads as "reachable, fix the secret" | collapse the 403 branch into `.serverError` in `classify(apiError:)` | 4 red, including `testForbiddenIsReachableAndSaysTheSecretIsTheProblem`: `("serverError(status: 403, detail: "Forbidden")") is not equal to ("reachableButUnauthorized")` and "must name the secret as the thing to fix" |
| 2 | the live probe really reaches the service | same as #1 | `testRealServiceWithNoSecretReportsUnauthorized` red with the REAL body: `("serverError(status: 403, detail: "{\"error\":\"forbidden\"}")")` — proof the assertion ran against point-guard rather than skipping |

Control #2 is the one worth keeping. It is the difference between a live test
that exercises the service and one that quietly skips: the failure message
carries point-guard's own error body, which no stub produced.

## The always-skipping live suite

`LiveAPITests` reads `BARRY_SECRET` from the test process's environment and
skips when it is absent. **The scheme never set it**, and `xcodebuild` does not
pass the invoking shell's environment through — so those tests had skipped on
every run since they were written, reporting green while never touching the
service.

`project.yml` now declares `environmentVariables: BARRY_SECRET: $(BARRY_SECRET)`
on the test action, which forwards it from the launching environment. With the
secret exported, the skip count went 4 → 0 and three previously-dormant live
tests began actually running.

This is the AGENTS.md failure mode exactly: a check whose broken state was
indistinguishable from its healthy one. The skip count was the only signal.

## Manual checks (only a device can prove these)

- [ ] Install on a phone, trust the app under Settings → General → VPN & Device
      Management. There is no TLS certificate to trust — the tailnet host serves
      a real Let's Encrypt cert.
- [ ] **Set the secret in Settings.** Every route but `/health` 403s without it.
- [ ] **Turn Wi-Fi off.** Over cellular the app must still reach the Mac via
      Tailscale. This is the check that matters most here: the old device
      default was a raw service port that could never have worked, and only a
      real off-network run distinguishes "works" from "the simulator's localhost
      works".
- [ ] "Test connection" with a deliberately wrong host must say it cannot
      RESOLVE the host, not merely "failed".
- [ ] Dark mode, and a Dynamic Type size or two.

## Known gaps

- **No UI test target.** The views are exercised manually.
- **The message path is not driven end to end by a test.** `POST /message`
  spawns a real fresh-context reply on this machine; that is a side effect worth
  a human deciding to cause.
