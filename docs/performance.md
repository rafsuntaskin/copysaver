# Performance evidence

Measured October 26, 2026 on MacBookPro18,3 / Apple M1 Pro, macOS 26.6.2, Command Line Tools Swift 6.3.3, optimized Release configuration. All content, keys, and temporary vaults were synthetic. No real clipboard or Keychain was used.

| Scenario | Dataset/method | Result |
| --- | --- | --- |
| In-memory search and sorting | 5,000 history + 2,000 snippets, short Unicode text, 20% sensitive snippets; 80 queries across history/snippets including absent results | p50 9.68 ms; p95 14.90 ms |
| Encrypted batch commit | 490 near-256 KiB history bodies, about 122.5 MiB plaintext; production CryptoKit and SQLite | 991.88 ms |
| Decrypt/load same vault | Production GCM verification and record decoding | 196.34 ms |
| Repeat near-budget run | Same synthetic shape | Commit 985.09 ms; load 190.11 ms |
| Full Release-suite repeat | Benchmarks concurrent with the applicable functional suite | Search p50 9.84 ms / p95 15.25 ms; commit 1,057.52 ms / load 351.69 ms |
| Maximum resident size reported by `time -l` | Test process tree, includes original fixture plus decoded copies and test/runtime overhead | 437,059,584 bytes (about 416.8 MiB) |

Search timing covers `DesktopModel.items`, including filtering/sorting. It does not measure native window presentation, first unlock, rendering, or user-perceived capture latency. Memory is a test-process baseline, not the app’s measured peak or a forensic erasure guarantee. The live encrypted payload budget remains 128 MiB; SQLite/WAL physical size can temporarily exceed it.

Reproduce the optimized checks:

```sh
COPYSAVER_BENCHMARKS=1 ./scripts/swift.sh test -c release --disable-xctest --filter 'representativeSearchBenchmark|nearBudgetVaultBenchmark'
```

The two benchmarks are opt-in to avoid large fixture/CPU costs in ordinary unit runs. They verify result bounds and exact near-budget round trips, and print aggregate timings only. They do not assert a wall-clock threshold on arbitrary CI machines.

Still pending under M4-05: native warm-panel p95, capture visibility latency, idle CPU with capture enabled, native app near-limit memory, Intel and minimum-OS measurements. Signed integration and real clipboard permission are separate gates. Do not infer those results from the core timings above.

## November 4 search and navigation revision

Measured on the same local arm64 Mac, macOS 26.6.2, Command Line Tools Swift 6.3.3, optimized Release. The synthetic dataset remains 5,000 history records and 2,000 snippets with Unicode and concealed bodies. The baseline used the `6e01511` implementation plus the measurement-only navigation extension to `representativeSearchBenchmark`; the final run includes the record-observation fix.

| Model operation | Before p50 / p95 | After p50 / p95 |
| --- | --- | --- |
| Search, 80 alternating queries | 9.94 / 18.49 ms | 7.29 / 13.31 ms |
| Warm arrow selection and selected-record lookup, 80 batches of 10 steps | 20.994 / 33.309 ms | 0.006 / 0.008 ms |

The model keeps one sorted array and one query result per visited section. Repeated render/selection calls reuse those results; every record replacement, including locking, clears them. Cache hits still read the observable record property so SwiftUI can react to captures and edits. No key, query or result cache is persisted, and no background indexing crosses the session boundary.

Reproduce with `COPYSAVER_BENCHMARKS=1 ./scripts/swift.sh test -c release --disable-xctest --filter representativeSearchBenchmark`. Search measures filtering plus any required ordering. Navigation is measured after the query is established and includes model selection/lookup plus synthetic assertions. It does not include SwiftUI rendering, AppKit event delivery, clipboard I/O or native panel latency; no wall-clock threshold is asserted. Targeted invalidation, observation and dirty-draft navigation regressions pass; the observation regression first failed before the fix. M4-05 native measurements remain pending.
