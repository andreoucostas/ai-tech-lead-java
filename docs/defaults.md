# Greenfield Conventions — Evidence-Matched Defaults

> Reference defaults for the technologies this repository actually evidences, including a Java application. These apply only when AGENTS.md > Conventions has not been populated by `/bootstrap`.
> Once `/bootstrap` runs, AGENTS.md > Conventions is the authoritative source — these defaults are for cold-start scaffolding only.

The distribution name is not technology evidence. Apply the Java application headings only when
one or more `pom.xml`, `build.gradle`, or `build.gradle.kts` files exist; `settings.gradle[.kts]`
and an aggregator POM are only locators after that evidence.

### Verification Commands

For each durable category — **build**, **test**, **format**, **lint**, **migration/deploy**, and
**data-validation** — use an exact command only when committed repository evidence names it:
AGENTS.md conventions, CI definitions, scripts/task runners, manifests, or tool configuration.
Record that exact evidence path with the command. If a category has no applicable profile or
evidenced command, report `not available (no evidenced command)`; never invent `mvn verify`,
`gradle build`, or another command from this distribution's name.

## Java application defaults (only when Java application markers exist)

### Static Analysis & Formatting
<!-- Check for .editorconfig, the compiler options in pom.xml / build.gradle[.kts] (-Xlint, -Werror), and Checkstyle, PMD, SpotBugs, Error Prone, or Spotless configuration. Reference them here so AI tools respect toolchain-enforced conventions. -->

### Architecture
- Dependency direction: inward only. Web/API → Application/Service → Domain. Never the reverse.
- Domain layer has no dependency on Spring web or persistence types where the project evidences a clean/hexagonal split.
- Package-by-feature vs package-by-layer: mirror what exists; this default does not choose one.

### Naming
- Types: PascalCase. Methods, fields, and locals: camelCase. Constants: UPPER_SNAKE_CASE. Packages: lowercase. No `I` prefix on interfaces; an `Impl` suffix only where the project already evidences it.
- Files match type names exactly. One top-level public type per file.

### Dependency Injection
- **DIP (see the framework rules (`.github/instructions/framework-rules.instructions.md` › SOLID))**: derive a service seam, registration, and scope from first-party project evidence and correctness needs. Do not introduce an interface or DI container solely from this default; preserve an evidenced dependency boundary. Data carriers (DTOs, entities, value objects, configuration properties) are not services and get no interface.
- Where the project already evidences DI, follow its established scope and composition-root conventions; this default does not choose singleton, prototype, request, or session scope.
- Follow the project’s evidenced composition-root location and registration mechanism; do not select component scanning, `@Bean` methods, or the `@SpringBootApplication` class from this default.
- Follow the project’s evidenced injection style. Where none is evidenced, prefer constructor injection to `@Autowired` field injection in new code.
- Use a configuration mechanism only where the project evidences it; do not select `@ConfigurationProperties` or `@Value` solely from this default.

## Evidence-matched data-access defaults

### Data Access
Data-access defaults are conditional on what the repo evidences in pom.xml/Gradle dependencies or repo artifacts such as SQL source or migration trees. Apply only the matching block; if none match, ask.

**If Spring Data JPA / Hibernate (`spring-boot-starter-data-jpa`, `jakarta.persistence`, `org.hibernate`):**
- Spring Data JPA with a custom repository layer only where it adds value (not wrapping a `JpaRepository` for the sake of it).
- Queries belong in the application/service layer, not in controllers.
- Use `@Transactional(readOnly = true)` on read-only service methods.
- Keep associations `FetchType.LAZY` and prevent N+1 with `JOIN FETCH` or `@EntityGraph`; use projections for read views and `Pageable` for lists.
- Schema changes only through migrations — never `ddl-auto=update` outside tests. Set `spring.jpa.open-in-view=false` only where the project evidences it.

**If JdbcTemplate / JdbcClient / jOOQ / MyBatis:**
- Use parameterized queries only; keep SQL in the application layer; never concatenate dynamic SQL.

**If Spring Data MongoDB (`spring-boot-starter-data-mongodb`, `MongoRepository`, `MongoTemplate`):**
- Use typed `@Document` classes through `MongoRepository` or `MongoTemplate`; no magic strings for collection names.
- Review indexes when adding a new query shape, and use projections for read-heavy queries.
- Use multi-document transactions only where the deployment supports them (replica set); otherwise design idempotent single-document writes.

**If raw SQL / stored procedures (`.sql` source tree, Flyway/Liquibase migration folders, JDBC calls to procedures):**
- Parameterized statements only; never concatenate input into SQL.
- Prefer set-based statements over row-by-row loops (cursors/WHILE) unless the surrounding code deliberately does otherwise.
- Schema-qualify object names; follow the repo's existing naming for tables and procedures.
- Every schema change goes through the repo's one deployment vehicle (Flyway or Liquibase migrations, whichever the repo evidences) — never ad-hoc.

**If none detected:**
- For greenfield work, ask the developer before introducing a data-access stack.

## Java application defaults (continued)

### API Design
- Controllers are thin — delegate at an evidenced project boundary. Functional `RouterFunction` endpoints are acceptable for simple endpoints if the project uses them.
- Request/response DTOs (records on Java 16+) are separate from domain and JPA entities. Never expose entities in API contracts.
- Use Jakarta Bean Validation (`@Valid`, `@NotNull`, and similar) for request validation where the project evidences it. No validation logic in controllers.
- Background work uses `@Scheduled`, Spring Batch, a message listener (`@KafkaListener`, `@RabbitListener`, `@JmsListener`), or a managed `TaskExecutor`, as the project evidences. No raw `new Thread` or unhandled `CompletableFuture.runAsync` fire-and-forget in request handlers.

### Concurrency
- Preserve extension compatibility; add timeouts or cancellation to outbound calls only when outcome or compatibility requires it.
- No fire-and-forget (`CompletableFuture.runAsync` without handling or an executor, raw `new Thread`) without explicit justification. `@Async` only with an evidenced executor.
- Never block inside reactive (WebFlux/Reactor) pipelines. Restore the interrupt flag when catching `InterruptedException`.
- Virtual threads only where the project evidences them (Java 21+).

### Null Handling
- `Optional` as a return type only — not for fields, parameters, or collections. No unchecked `Optional.get()`; prefer `orElseThrow`.
- Nullness annotations (JSpecify `@Nullable`/`@NullMarked`, or Spring/Jakarta `@Nullable`) only where the project evidences them.
- Guard clauses (`Objects.requireNonNull`) at public API boundaries. Trust internal code.

### Logging
- SLF4J (`LoggerFactory.getLogger`; Lombok `@Slf4j` only where the project evidences Lombok) with `{}` placeholders — no string concatenation or `String.format` in log calls.
- MDC for correlation ids only where the project evidences it. Never log secrets or PII.

### Testing
Test-framework defaults are conditional on what the repo already evidences. Detect first, then apply
the matching block.

**Detect** — read the test modules' dependencies in `pom.xml` / `build.gradle[.kts]` (or
`gradle/libs.versions.toml`):
`junit-jupiter*` → JUnit 5 · `junit:junit` → JUnit 4 · `org.testng` → TestNG. `spring-boot-starter-test`
brings JUnit 5, Mockito, and AssertJ transitively; confirm against the existing tests' imports.
Mocking: `mockito-core` · `mockito-junit-jupiter` · `easymock`. Assertions: `assertj-core` · `hamcrest` · built-in.
Integration boundaries, each only where already evidenced: Spring Boot test slices (`@WebMvcTest`,
`@DataJpaTest`, `@JsonTest`, `@WebFluxTest`) · `@SpringBootTest` · Testcontainers (`org.testcontainers`) · WireMock.

**If a test suite already exists (any framework):**
- Mirror it — the runner, mocking library, assertion library, naming convention (for example `*Test.java`
  unit tests under `src/test/java` mirroring the main package; `*IT.java` integration tests only where
  Failsafe or an `integrationTest` source set is evidenced), and base fixtures/builders already in use.
- Do not introduce a second test framework alongside it. If the existing one is genuinely wrong for
  the job, raise it in `TECH_DEBT.md` and get a human decision rather than migrating as a side effect
  of adding tests.

**If no test suite exists anywhere in the repository (greenfield only):**
- Do not create a harness as an incidental side effect of feature, fix, refactor, or debt work.
- When establishing tests is explicitly in scope, use the `add-tests` skill to propose the smallest
  harness (for Spring Boot, `spring-boot-starter-test`) and first risk-first tests; get agreement
  before adding a framework.
- Prefer a few tests for consequential branching, boundaries, and regressions over one test per
  public member. Test observable behavior, not implementation details.

### Test shape
Choose the level by what the test actually exercises — *push each test to the lowest level that still runs real behavior; test at the boundary, not the mock.* A heuristic, not a fixed ratio; `/bootstrap` replaces it with the shape your codebase warrants.
- Domain / application logic (rules, calculations, branching, validation) → unit-dense.
- Cross-cutting paths (routing, request binding, data access, auth, serialization) → use the
  repository's established integration boundary (for example a Spring Boot test slice such as
  `@WebMvcTest` with `MockMvc` or `@DataJpaTest`, `@SpringBootTest`, or Testcontainers where already
  evidenced); exercise the real pipeline, don't invent or over-mock it.
- Critical journeys → a sparse top layer of full-stack behavioral checks. Few, high-value.
- Boundary-heavy / gateway services → weight toward integration (honeycomb / risk-based), not unit.
- Anti-shape: the inverted suite (mostly slow end-to-end tests over a thin unit base). Slow + flaky = wrong shape.

### Test determinism
- Tests must be deterministic and hermetic: no real network, clock, randomness, filesystem, or inter-test order dependence. An intermittently-failing test is worse than none — it trains the team to ignore red.
- Pin time behind an abstraction (an injected `java.time.Clock`); seed or stub randomness; isolate state between tests.
