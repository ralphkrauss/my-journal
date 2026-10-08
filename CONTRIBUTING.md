# Contributing

My Journal is a private, local-first journal with native clients and a portable self-hosted backend. Keep contributions focused, lightweight and understandable.

## How to contribute

- **Open an issue first** for anything larger than a small fix, so we can agree on the approach before you spend time on it. Use the issue forms, and never paste journal text, setup or recovery codes, recovery keys, connection files or tokens into an issue.
- **Report security problems privately** through the repository's Security tab, not in a public issue. See [SECURITY.md](SECURITY.md).
- **Sign off your commits** with `git commit -s`. The sign-off certifies the [Developer Certificate of Origin](https://developercertificate.org): that you wrote the change or otherwise have the right to submit it under the project's license.
- **License.** Contributions are accepted under the [Apache License 2.0](LICENSE), the same license as the project (Section 5, "inbound = outbound"). Don't add license headers to source files; `LICENSE` and `NOTICE` cover the whole repository.

To build and test, follow [docs/development.md](docs/development.md). [docs/architecture.md](docs/architecture.md) explains how the code fits together.

## Design before implementation

Every interface change, by anyone, starts with a concrete design: layout, behavior, exact interface copy, accessibility, and the relevant empty, loading, offline, error and recovery states. Before implementation, someone other than the author reviews it independently: the maintainer, another human reviewer, or a separate design-review agent. Share the requirements and the proposal without coaching the reviewer toward approval. Resolve material findings and keep the design and review in `docs/design/`, and add them to the [index](docs/design/README.md).

Each client follows its own platform's interface conventions: familiar Apple conventions on the Apple clients, Windows conventions on Windows, and so on. Favor native controls, readable adaptive colors, standard editing behavior and concise action labels. The writing surface should stay quiet; complexity should appear only when it is needed. After implementation, inspect the real interface against the reviewed design.

Every client keeps document fidelity and protocol compatibility. A feature or change is specified in [spec/](spec/README.md) in the same change as its code, on whichever platform it starts, so that every other platform can port it; changes to anything in [protocol/](protocol/README.md) also bump its version and update the conformance fixtures.

## Tests must earn their cost

Add a test when it protects meaningful behavior or a plausible failure mode, not to reach a coverage percentage or match every source file. Explain the failure it protects against when that is not obvious.

Prioritize data preservation, sync retries and conflicts, offline recovery, device authorization, encryption interoperability, database migrations and backup restoration. Prefer small, fast tests. Use an isolated real database when persistence semantics matter.

Avoid tests for trivial properties, framework behavior, routine UI layout snapshots, or mock method-call sequences that do not demonstrate user-visible correctness. Keep end-to-end checks few and focused. Fix, replace or remove flaky or unnecessarily slow checks.

Run the checks that match your change and report their results and any unverified behavior honestly.

## Privacy and portability

Never commit credentials, signing keys, real journals or personal server configuration. Use synthetic data in examples and checks. Keep protocol definitions language-independent and hosting dependencies optional. Do not silently drop unsupported document content or overwrite concurrent edits.

## Required code hygiene

Read [the code-hygiene policy](docs/engineering/code-hygiene.md). Use the committed mise toolchain, `mise exec -- scripts/format.sh`, and the `mise exec -- scripts/check.sh` lanes for your change. CI runs the same checks and separate focused end-to-end checks. Compiler warnings, strict lint, format drift, known dependency vulnerabilities, workflow errors, shell errors and accidental secrets fail the build. Fix findings rather than hiding them behind baselines or broad suppressions.

A passing tool does not prove a good design. Review responsibilities, cancellation, lifetime, persistence and authorization carefully. Keep APIs clear, operations focused, and one statement per line. Changes to analyzer rules or exceptions require a concrete rationale. Tests must still earn their cost; there is no coverage target.
