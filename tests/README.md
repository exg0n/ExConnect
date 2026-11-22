# ExConnect QA

Run the source tests from the repository root with Node.js 20 or newer.

```sh
node --test tests/source.test.cjs
```

GitHub Actions builds both APKs and runs installation checks against clean OpenWrt filesystems for x86/64 and the NanoPi R3S (rockchip/armv8). The install test substitutes fixture responses for GitHub and uses the real `apk`. It checks installed files and dependencies, then starts the installed Xray launcher and sends HTTP and SOCKS requests through a controlled upstream in an isolated network namespace. Both platform jobs must pass before the workflow run is considered successful by the installer.

Use an isolated OpenWrt 25.12.5 VM or spare router for the functional smoke test. An [official generic x86/64 image](https://downloads.openwrt.org/releases/25.12.5/targets/x86/64/) can serve as a VM target. Use packages built for the test device and record the firmware, package, and Xray versions with each run.

With the service package installed, copy `tests/runtime.sh` to the target and run `sh /tmp/runtime.sh`. This tests configuration generation, RoutingA rule order, the temporary SOCKS configuration for diagnostics, and both flavors of `.dat` data. Temporary files and a separate UCI directory keep the checks independent of active router settings. The same check can run in an x86_64 OpenWrt chroot with the runtime dependencies installed. The package smoke test performs diagnostic calls before and during service operation. It substitutes transfer metrics for the remote HTTPS endpoint and verifies that the temporary Xray listener closes after each call.

| Area | Acceptance check |
| --- | --- |
| Installation | Install both `.apk` files and open **Services → ExConnect**. The service starts disabled and the default firewall and DNS still work. Reinstall or upgrade and confirm existing profiles, rules, and asset settings remain. |
| LuCI permissions and languages | Test every page with an administrator and a LuCI user who has only the app's read ACL. Status is readable. Service controls, changes to UCI, and list downloads require the write role. Switch LuCI between English and Russian. Verify labels, errors, file controls, and action notifications, then refresh and confirm saved state. |
| Hysteria2 | Import both `hysteria2://` and `hy2://` in the forms listed by [Podkop](https://github.com/itdoginfo/podkop/blob/main/String-example.md#hysteria2). Use a known-good server with a trusted TLS certificate and verify outbound TCP and UDP via the selected profile. Repeat with Salamander enabled and a valid SNI. Verify connection failure with the wrong password or SNI. |
| Subscriptions | Import a plain-text source and a Base64 source. Verify that duplicates and unsupported links are skipped. Refresh a source after renaming a profile and removing another, checking that selection and unmanaged profiles are preserved. Try an unreachable source, then confirm earlier entries still work. |
| Diagnostics and logs | Select a saved profile while the main service is stopped. Run the HTTPS latency check and the download test against a reachable profile, then repeat while the main service is routing traffic. Verify that neither test changes the service state or selected profile. Repeat with an invalid upstream. Refresh the journal and check that it contains ExConnect events. |
| RoutingA | Switch from the rule table to RoutingA. Paste rules with `default`, `domain`, `geoip`, `ip` and `protocol`; verify the fallback and first match in top-to-bottom order. Try an invalid line and verify that the error includes its line number. Switch back to the table and verify that previous rules are restored. |
| Explicit proxy | Verify that HTTP and SOCKS are available at the configured ports, bind to loopback by default, and do not become accessible on WAN after LAN sharing is enabled. |
| Transparent LAN proxy | From a separate LAN host verify TCP and UDP forwarding, routing by domain and IP, and access to router administration, DHCP, and local DNS. Test IPv4 and IPv6 separately. Repeat after firewall reload and router reboot. Stop ExConnect and verify traffic returns to the expected baseline with no stale rules. |
| Custom DAT files | Add separately named GeoSite and GeoIP `.dat` files from [RunetFreedom](https://github.com/runetfreedom/russia-v2ray-rules-dat) through LuCI. Select known tags and prove domain and IP matching using a controlled destination. Verify the update path rejects empty or corrupt data and preserves the last known-good versions. |
| Failure recovery | Start with a valid profile, then attempt to apply a malformed URI, invalid port, unknown DAT category, and conflicting local listener. Verify that each failure has an actionable message and leaves the previous service and rules operating. |

## Upstream parity inventory

The [v2raya-openwrt feed](https://github.com/v2rayA/v2raya-openwrt) provides packaging, a LuCI entry point, and selectable engines. Use the [v2rayA manual](https://v2raya.org/docs/manual/) and the current [v2rayA README](https://github.com/v2rayA/v2rayA) to assess the application itself. Confirm each of the following against the final release before claiming full parity.

- Profile creation and editing, share links, QR and batch import, subscriptions and automatic refresh, latency probes, grouped selection, and balancing.
- Protocols and transport options advertised by the reference engine, including VMess, VLESS, Shadowsocks, Trojan, Hysteria2, TUIC, Juicity, AnyTLS, WireGuard, SOCKS, and HTTP.
- SOCKS, HTTP, policy-aware and authenticated inbounds, LAN sharing, transparent modes, and split rules including RoutingA, rule order, source selectors, and per-outbound routing.
- DNS strategies, standard and external `.dat` rule lists, automatic rule refresh, lifecycle hooks, multiplexing, and alternate cores.
