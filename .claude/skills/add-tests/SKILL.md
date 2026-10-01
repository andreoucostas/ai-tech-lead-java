---
name: add-tests
description: >
  Use when the user wants to add or improve test coverage for existing Java code — a service,
  handler, controller, or endpoint that already exists. Covers unit and integration tests in
  whatever test framework the repo already uses, behavior-first assertions, and fixture reuse.
  USE FOR: backfilling tests on untested code, adding edge/error-path cases, writing a regression
  test for a bug, raising coverage on a module you're about to change, or pinning the current
  behavior of untested legacy code before a refactor (characterization mode).
  DO NOT USE FOR: scaffolding a brand-new endpoint (use add-endpoint, which assesses tests only
  against an evidenced harness), or runtime profiling/benchmarking.
---

# Add tests following project patterns

Match `AGENTS.md > Conventions > Testing` and the Test leanness rules in the framework rules (`.github/instructions/framework-rules.instructions.md` › Leanness). If conventions are unbootstrapped, follow `docs/defaults.md`.

**Applicability gate:** confirm the code under test belongs to a repository-evidenced Java project (a `pom.xml`/`build.gradle[.kts]` module). If no such project exists, report this skill as **not applicable**; do not create a test suite for a stale delivery-profile label. Suite bootstrap remains available only through the explicit developer-agreement checkpoint below.

1. **Evidence gate — derive, don't assume.** Apply Verification Rule #10 before writing a test:
   read every module's `pom.xml` / `build.gradle[.kts]` test dependencies (and the
   `<dependencyManagement>` or `gradle/libs.versions.toml` that pins them), then `Grep` a sibling
   test class. Detect the runner (JUnit 5, JUnit 4, or TestNG), mocking library (Mockito or
   EasyMock), assertion library (AssertJ, Hamcrest, or built-in assertions), naming convention
   (`*Test.java`, `*IT.java`), and base fixtures, builders, Spring Boot test slices (`@WebMvcTest`,
   `@DataJpaTest`) or `@SpringBootTest` base classes, and Testcontainers/WireMock support classes.
   Mirror everything found; never introduce a second test framework or parallel infrastructure
   (Verification Rule #6, Test leanness #13). If nothing is found anywhere in the repository/module
   graph, switch to **Suite bootstrap mode** below.
   On a JUnit 5 suite, a `@Tag` that the build selects explicitly (an evidenced Surefire/Failsafe
   `groups` filter or Gradle `integrationTest` task) is a legitimate opt-in marker for long-running
   or manual tests, but `@Disabled` is a skip and stays subject to the project's no-skipping rule —
   as does JUnit 4's `@Ignore` and TestNG's `@Test(enabled = false)`.
2. **Decide the level.** Pure logic / branching → unit test against the concrete class. For a full HTTP path, mirror the repository's established integration boundary (for example `@WebMvcTest` + `MockMvc` or `@SpringBootTest` + `TestRestTemplate`/`WebTestClient` where already evidenced; `*IT.java` naming only where Failsafe or an `integrationTest` source set is evidenced); do not introduce one just because this is the Java distribution.
3. **Cover behavior, not implementation.** Choose the smallest risk-relevant set: the principal behavior plus only consequential error, edge, or boundary cases. Do not create one test per category or public member. Do **not** test getters/setters, DI resolution, or that JPA/Hibernate or request binding works (Test leanness #11, #12). Mock only true external boundaries — never the type under test or owned collaborators you can construct cheaply (Test leanness #14). Every test needs a real oracle: assert a return value, state change, or thrown exception — not merely that a mock was called or that `assertTrue(true)` (Test leanness #15–16).
4. **Financial domain**: when code touches money/balances/ledgers, derive the applicable invariant, tolerance, and preconditions from policy, implementation, tests, or executable evidence. Add only risk-relevant cases that exercise demonstrated negative-amount, duplicate-effect, precision/rounding, or temporal controls; a type/name or `RoundingMode` alone is neither test selection nor a verdict.
5. **Arrange-Act-Assert**, one logical assertion focus per test. Descriptive names per the project convention (e.g. `methodName_scenario_expectedResult`).
6. **Run** the exact scoped test command supported by `AGENTS.md > Conventions > Verification Commands`, committed CI, scripts, manifests, and runner configuration; do not infer a reactor-wide `mvn test` or root-project `gradle test`. Confirm green, then confirm each new test can **fail**. A test you have not watched go red may be over-mocked or tautological (Verification Rule #9): for a regression test, confirm it fails against the unfixed code first; for any other new test, briefly break the code under test (or assert a deliberately wrong value) to see it fail for the right reason, then restore. If no executable command is evidenced, report tests as **not available** rather than claiming a pass.
7. **Report** what was covered and what remains uncovered — do not claim coverage you didn't add.

---

## Characterization mode — pinning legacy behavior before a refactor

When the goal is to make untested legacy code *safe to change* (e.g. before `/refactor`), you are pinning **what the code currently does**, not asserting what it *should* do. This is different from normal test-writing:

- **Label every test as characterization.** Put this header on the test class/file: `// CHARACTERIZATION — pins OBSERVED behavior, not VERIFIED-correct behavior. A failure may mean the refactor changed behavior, OR that this test pinned a pre-existing bug. Do not "fix" the assertion without human review.`
- **You cannot pin behavior you have not run.** Without an oracle you would be guessing. Generate the test *skeleton* (wire the real dependencies, call the method, capture the result), run it once to obtain the actual values, and assert those. Never invent expected values.
- **Flag every nondeterministic input you had to pin** — `Instant.now()`/`LocalDateTime.now()`, `UUID.randomUUID()`, random, file/network/DB I/O — with `// TODO: stub for a stable snapshot` so the developer seals it before relying on the test.
- **HALT on money / safety-critical code.** If it touches `BigDecimal` money, balances, ledgers, idempotency keys, or regulatory figures, STOP before treating any characterization test as a contract: present the captured behavior and ask the developer to confirm it is *correct*, not merely *current*. Pinning a wrong rounding mode or an off-by-one balance as "approved" is a financial-domain hazard — if confirmed wrong-but-load-bearing, record it in `FRAMEWORK-CONTEXT.md > Known Hazard Areas`.
- These tests are scaffolding for a safe refactor, not a substitute for behavior-first tests. Once the intended behavior is understood, prefer real behavioral assertions.

---

## Suite bootstrap mode — when no test sources exist

1. **Confirm before scaffolding.** First inspect the whole repository/module graph and confirm no test sources
   exist anywhere, not merely beside the code under test. In one message, ask the developer to
   confirm the test framework and test-source location. Prefer
   `AGENTS.md > Conventions > Testing`; if it is unbootstrapped and the repository is genuinely
   test-free, propose JUnit 5 + Mockito + AssertJ (for Spring Boot, `spring-boot-starter-test`, which
   bundles all three). This is a real checkpoint — do not create files until
   they answer.
2. **Scaffold the minimum.** Add one unit-test source set (`src/test/java`, mirroring the main package,
   `*Test.java`) to the primary domain/application module, with only the configuration and test
   dependencies the developer-confirmed framework needs to execute. Only when an aggregator build is
   evidenced (a parent POM with `<modules>`, or `settings.gradle[.kts]`), register any new module
   through its exact evidenced mechanism; a single-module repository remains valid and uses
   module-level CI/command wiring.
   Only when the repo exposes an HTTP surface, add one integration test using an evidenced Spring
   test boundary (`@WebMvcTest` + `MockMvc`, or `@SpringBootTest` + `TestRestTemplate`/`WebTestClient`);
   a `@SpringBootTest` must be able to locate the `@SpringBootApplication` class (a test package
   under it, or `classes = …`). Add no E2E module, coverage tooling, or extra test layers on day one.
3. **Wire it so it cannot rot.** Record the new exact test command in `AGENTS.md > Conventions > Verification Commands` and ensure the repo's existing CI/build runs the new tests, following `docs/ci-integration.md`. If no CI exists, flag that and route CI setup to the `enforce-standards` skill; do not build CI in this task.
4. **Start risk-first, not coverage-first.** Test in this order: `FRAMEWORK-CONTEXT.md > Known Hazard Areas`; financial-domain invariants from step 4 above when present; critical journeys from `AGENTS.md > Codebase Context`; then pure domain logic with branching. Write only a handful that prove the harness end to end, and apply step 6's red-check to every test.
5. **Record the remainder honestly.** Add one `TECH_DEBT.md` entry: `Test suite bootstrapped <date>; backfill areas: …`. Do not imply broader coverage. Update `AGENTS.md > Conventions > Testing` with the real framework, naming, and fixture location, and flag that documentation drift under Agentic Workflow §6.
