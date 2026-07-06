# Acknowledgments

Lindalë builds on the work of others. This file tracks upstream projects that
inspired the framework, or whose code was (or will be) vendored in — an
attribution trail, a link trail for learners, and a vendoring manifest of what
was lifted and from which commit.

## Vendored / integrated

### [moat](https://github.com/majorcontext/moat) (MIT)

Provides the TLS-intercepting gatekeeper proxy that injects credentials at the
network layer — the core mechanism behind Lindalë's container-as-boundary
security model (EPIC-004, see [Architecture Overview](../../wiki/Architecture-Overview)
and `memory/decisions.md`).

- **Today (M1/M2):** used as a pinned installed binary, not vendored source.
  Pinned to commit `616f1b3` (pseudo-version `v0.5.1-0.20260421175536-616f1b3464b2`),
  verified in the FEAT-008 spike on xo-brain — includes features not in the
  tagged `v0.5.0` release (`RUNTIME` column in `moat list`, multi-runtime
  metadata).
- **M3 (planned):** vendor a source subset (~17k LOC production + ~5k
  gatekeeper) into this repo, once k10s needs programmatic control rather than
  a manually-run `moat run`. MIT-to-MIT is license-compatible; no legal
  friction. See `memory/decisions.md` for the subset boundary
  (`internal/{run,container,daemon,config,credential,storage,routing,netrules}`
  + `providers/{claude,configprovider,github}` + gatekeeper proxy).

## Prototyped in / origin

### [aistrologer](https://github.com/grinnellian/aistrologer)

Lindalë was extracted from aistrologer, where the role-based agent structure
(architect, TPM, dev) and ticket-lifecycle workflow were first prototyped.
Aistrologer remains the reference for downstream adoption steps — see
[docs/adoption-guide.md](docs/adoption-guide.md).

## Harvested patterns (not vendored code)

Several operational patterns in `memory/patterns.md` were distilled from
downstream adopters' lived experience rather than copied code — catalyst-build
(autodev dispatch strategy, worktree footguns, git/GitHub operational lore)
and juno (settings split conventions, tombstone-override technique). These are
credited inline in `memory/patterns.md` at each pattern's "Origin" note rather
than repeated here.

## License

Lindalë is MIT licensed. Where upstream code is vendored, its original license
and attribution will be preserved in the vendored subtree per that project's
terms.
