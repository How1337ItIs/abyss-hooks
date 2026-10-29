# Bounded LaunchDirectory regression harness

The deliberate `[profile.activation]` in root `foundry.toml` discovers these tests.
The default profile is unchanged. Run from the repository root (Git Bash):

```bash
FOUNDRY_PROFILE=activation forge test --match-path 'activation-test/*.t.sol' -vv
FOUNDRY_PROFILE=activation forge test --match-test testRecordGasBudget -vvvv
git diff --check
```

On the reviewed Windows machine, the executable is
`C:/Users/natha/.foundry/bin/forge.exe` (not on the inherited PATH).
This profile uses an empty source/script root and imports only the directory
and its dependencies through the tests: seven Solidity files including both
test files, not a full protocol build. Compiler settings inherit the default
Solc 0.8.28, Cancun, optimizer runs 1, no IR settings.

## Verified review results

- Candidate: **17 passed, 0 failed**, two suites; both fuzz tests run 256 cases.
- New behavior suite: **13 tests**, including one signed-int24/uint128/independent-manager fuzz test.
- Existing suite: **4 tests**, including one tokenId/salt/liquidity fuzz test and the gas budget.
- A separate copied harness outside the candidate worktree was run with
  `LaunchDirectoryV1.sol` replaced by exactly `git show HEAD:contracts/protocol/src/launch/lifecycle/v1/LaunchDirectoryV1.sol`.
  All **16 functional tests passed** there; **only the gas budget failed** with
  `directory redundant storage exceeds budget`. No candidate production source
  was edited or temporarily replaced during this check.
- Gas-budget test transaction accounting: original 241,943 versus candidate
  175,394 gas, a 66,549 gas differential. The candidate trace reports 167,929
  gas inside `recordPositions`; the test's measured call must be below 175,000.
  Whole-test gas is not the same quantity as the measured call budget.
- `git diff --check` passed.

The new suite checks exact custom-error returndata, a duplicate in the second
position of a single batch with rollback and successful retry, invalid second
positions with rollback of the first position and reverse indexes, two-position
readback and partial pages, identity preservation after a chain-ID change,
unauthorized writes, unknown/wrong markets, mismatched custody, non-contract
manager, count mismatch, equal/reversed ticks, and zero liquidity. The prepared
manager remains zero while actual position managers are nonzero contracts;
manager equality with prepared-market metadata is deliberately not assumed.

## Scope and compatibility limits

These are generic local EVM directory tests, **not** native-chain activation or
full-lifecycle integration tests. They do not establish that native 16-position
activation fits a 32-million gas limit, and do not close issue 21.

The candidate retains the public directory ABI but changes each stored position
from eight slots to five. It is **not storage-layout compatible with an already
populated old directory**. Deployment requires the official team's new canonical
graph, not an in-place storage migration inferred from these tests.

No production logic was changed by this review-test integration. No Docker,
full protocol compile, signing, commit, push, or publication was performed.
Generated `activation-out/`, `activation-cache/`, and the abandoned local
`activation-foundry.toml` are local-only and excluded through the repository's
Git info/exclude; do not stage them. The root profile is authoritative.
