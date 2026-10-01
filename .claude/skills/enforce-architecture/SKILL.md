---
name: enforce-architecture
description: >
  Use to wire the DETERMINISTIC backstop for SOLID's Dependency Inversion and layering — fail the
  build on dependency-direction violations using ArchUnit tests.
  USE FOR: "enforce architecture/layering in CI", "add ArchUnit", making DIP / Clean-Architecture
  rules build-breaking rather than review-only.
  DO NOT USE FOR: the semantic SOLID review of a diff — that is the `solid-check` agent / `/review`.
---

# Enforce architecture deterministically (Java — ArchUnit)

`solid-check` covers SOLID semantically per diff; this makes the *structural* part (DIP / dependency direction) a **build-breaking** CI gate. Pairs with the framework rules (`.github/instructions/framework-rules.instructions.md` › SOLID).

**Applicability gate:** confirm committed Java modules (`pom.xml` or `build.gradle[.kts]` with Java
sources) and real dependency boundaries first. If none exist, report this skill as not applicable;
the Java delivery profile alone does not justify creating an ArchUnit test.

1. **Test dependency**: add ArchUnit (`com.tngtech.archunit:archunit-junit5`, or `archunit-junit4` on a JUnit 4 suite) to an existing test source set if one exists (Leanness — don't create a parallel module); otherwise add a `src/test/java` source set with that dependency to the module holding the packages to govern.
2. **Rules**: copy `scripts/ci/ArchitectureTest.java.sample` into the test source set as `ArchitectureTest.java`, translate it to the repo's existing
   test framework if that is not JUnit 5, and adjust the packages to this repository's module/package graph (its no-`@Disabled`
   rules belong to `enforce-standards` step 2; keep them only when that skill is also in scope). Cover at least:
   - Domain has **no** dependency on Application / Infrastructure / Web (inward-only).
   - Application does not depend on Infrastructure / Web.
   - (Optional, where detectable) controllers/handlers preserve the project's evidenced service seam — supports DIP.
3. **CI**: derive the exact scoped command that runs the new architecture test in this repo
   (for example a targeted `mvnw.cmd -B -pl <module> test` or `gradlew.bat :<module>:test --tests ArchitectureTest` when that is the established runner), record it under
   `AGENTS.md > Conventions > Verification Commands`, and put that exact command in the required
   build. Do not assume a reactor-wide or root-project invocation or register a module in an aggregator build that does not exist.
4. **Don't weaken rules to go green** — record current violations in `TECH_DEBT.md` (Category: Architecture) and burn them down via the Trojan Horse.
