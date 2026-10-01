# AI Tech Lead (Java) — Changelog

> Release notes for the Java distribution, written for the teams who install it: what changed in
> **your** repo, and what (if anything) you need to do.
> Architecture decisions you record live in `docs/architecture-decisions.md`.

## 0.91.0 — 2026-10-01

- **First Java edition.** The AI Tech Lead rails — `AGENTS.md` and its `CLAUDE.md` import stub, the
  framework rules, commands, subagents, skills and PowerShell hooks — for Spring Boot repositories
  built with Maven or Gradle. It carries the behaviour of AI Tech Lead v0.91.0, re-targeted at Java.
- **`/bootstrap` selects the Java profile from build evidence only**: a `pom.xml`, `build.gradle` or
  `build.gradle.kts` within two project-container levels of the Git root. `settings.gradle[.kts]` and
  an aggregator POM only locate modules. Verification Commands are recorded from your CI, wrapper and
  build files; nothing is invented from the distribution's name.
- **Post-write build check.** After an agent writes a `.java` file, a `pom.xml`, a Gradle build script
  or `gradle/libs.versions.toml`, the hook compiles main and test sources offline, at most once a
  minute, inside a 45-second budget: Maven through the reactor root (`mvnw.cmd` when committed,
  `-pl <module> -am` for a nested module), Gradle through the build root (`gradlew.bat` when
  committed). Dependencies missing from the local cache are reported as not verified, never as a
  broken build.
- **Write-time guard for Java.** Blocks `@Disabled`, `@Ignore` and `@Test(enabled = false)`,
  tautological assertions, and analyzer silencing (`// NOSONAR`, `// NOPMD`, `CHECKSTYLE:OFF`,
  `@SuppressFBWarnings`, `@SuppressWarnings("all")` or a named rule). A narrow
  `@SuppressWarnings("unchecked")` stays allowed. Hardcoded credentials are also caught in unquoted
  Spring `application*.properties`/`.yml` values; `${...}` placeholders pass.
- **Skills:** `add-endpoint`, `add-entity`, `register-service`, `add-tests`, `perf`,
  `dependency-audit`, `enforce-architecture` (ArchUnit) and `enforce-standards`
  (`-Xlint:all -Werror` plus Checkstyle/PMD/SpotBugs), with `scripts/ci/ArchitectureTest.java.sample`,
  `quality-gates.pom.xml.sample` and `quality-gates.gradle.kts.sample`.
- **Not in this edition:** the warehouse-SQL profile and its skills, and a mixed Java + Angular
  distribution. For a front end in the same repository, add path-scoped rules in
  `.github/instructions/<stack>.instructions.md`.
