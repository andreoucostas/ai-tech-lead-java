---
name: enforce-standards
description: >
  Use to wire the DETERMINISTIC backstop for code standards — make compiler warnings, skipped tests, and
  static-analysis findings build-breaking via -Xlint:all -Werror (failOnWarning) + a test-integrity
  check + Checkstyle/PMD/SpotBugs failOnViolation, so the build enforces what AI instructions can only request.
  USE FOR: "make warnings errors", "fail the build on skipped tests", "enforce standards in CI",
  hardening a repo whose only standards enforcement is instructions and review.
  DO NOT USE FOR: dependency-direction rules (that is `enforce-architecture`), or the semantic
  review of a diff (that is `/review`).
---

# Enforce standards deterministically (Java — compiler + static analysis)

The write-time guard hook blocks analyzer/linter silencing (`// NOSONAR`, `// NOPMD`, `CHECKSTYLE:OFF`,
`@SuppressFBWarnings`, and `@SuppressWarnings` of `"all"` or a PMD/Checkstyle/Sonar rule; a narrow
`@SuppressWarnings("unchecked")` or another javac lint key is not blocked), skipped tests across JUnit 5
`@Disabled`, JUnit 4 `@Ignore`, and TestNG `@Test(enabled = false)`, and tautological asserts — but only on surfaces where hooks run. This skill wires the same floor into the
**build**, where it binds every developer, every agent, and CI. Pairs with `docs/ci-integration.md`
(leg 2) and `docs/enforcement-surfaces.md`.

**Applicability gate:** confirm committed Java modules (`pom.xml` or `build.gradle[.kts]`) and their
compiler/test configuration. If none exist, report this skill as not applicable; do not add Java build
or static-analysis infrastructure because the Java delivery profile was selected.

1. **Warnings as errors**: merge the compiler section of `scripts/ci/quality-gates.pom.xml.sample`
   (Maven) or `scripts/ci/quality-gates.gradle.kts.sample` (Gradle; translate to the Groovy DSL if the
   build uses `build.gradle`) into the repository's evidenced build — the governing `pom.xml` or Gradle
   build script (Leanness: don't duplicate an existing configuration). It sets `-Xlint:all` with
   `failOnWarning` (Maven `maven-compiler-plugin`) or `-Werror` (Gradle `options.compilerArgs`). The
   sample's remaining plugins and blocks are independent and optional (only where evidenced or
   agreed); static analysis is step 3.
2. **Test-integrity**: detect the test framework from the build's test dependencies and apply only
   its branch. JUnit has no compiler-level "skipped test" error — neither `@Disabled` nor `@Ignore`
   produces a javac diagnostic — so the floor is a test or a CI step, not a compiler severity. Verify
   the versions this repo pins include the stated library before claiming coverage.
   - **If JUnit 5:** wire the ArchUnit rules from `scripts/ci/ArchitectureTest.java.sample` that fail
     the build when a test method or class is annotated `@Disabled`. They need
     `com.tngtech.archunit:archunit-junit5`.
   - **If JUnit 4:** wire the same rules for `@Ignore`, using `com.tngtech.archunit:archunit-junit4`.
   - **If TestNG, or where ArchUnit is not adopted:** there is no equivalent compiler diagnostic. Wire a
     build-failing CI step that rejects the skip marker, pointed at this repo's test roots:
     ```powershell
     $skipped = Get-ChildItem src/test/java -Recurse -File -Filter *.java |
       Select-String -Pattern '^\s*@(Disabled|Ignore)\b|@Test\s*\(.*\benabled\s*=\s*false'
     if ($skipped) { $skipped; throw 'Skipped tests (@Disabled, @Ignore, enabled = false) are forbidden' }
     ```
3. **Static analysis** — only where the build already evidences Checkstyle, PMD, SpotBugs, or Error
   Prone, or the developer agrees to adopt one: make its findings build-breaking (`failOnViolation` for
   Checkstyle/PMD and `failOnError` for SpotBugs in Maven; `ignoreFailures = false` in Gradle; Error
   Prone warnings fail under step 1's `-Werror`/`failOnWarning`), starting from the matching section of
   the step 1 sample. If none is evidenced or agreed, report static analysis as **not available**;
   never infer a tool, ruleset, or plugin version.
4. **CI**: update `AGENTS.md > Conventions > Verification Commands` with the exact evidenced build
   and test invocations that exercise these settings (Maven's Checkstyle/PMD/SpotBugs checks bind to
   the `verify` phase and Gradle's to `check`, so the recorded command must reach that phase or task),
   and put those commands in the required build (`docs/ci-integration.md`). Do not infer a
   reactor-wide `mvn verify` / root-project `gradle build`. Run the recorded command locally and show
   the result.
5. **Don't weaken to go green** — a pre-existing warning wall is normal in brownfield: keep
   `-Werror`/`failOnWarning` scoped (e.g. per-module opt-in, or specific `-Xlint:<key>` categories
   first), record the remainder in `TECH_DEBT.md` (Category: Standards), and ratchet up.
   Never fix a violation by adding a suppression — that is the exact move this gate exists to stop
   (a narrow, commented `@SuppressWarnings("unchecked")` on a proven-safe cast is the one exception).
