---
name: dependency-audit
description: >
  Use when the user wants to find vulnerable, deprecated, or outdated Maven or Gradle dependencies and/or
  set up automated dependency scanning. Covers the Maven/Gradle vulnerability scan, triage into the right register,
  and wiring up Dependabot (GitHub) or Renovate (host-agnostic, works with Bitbucket Data Center).
  USE FOR: pre-release dependency audits, responding to a CVE advisory, or establishing ongoing
  automated dependency updates.
  DO NOT USE FOR: adding a new dependency for a feature (just add it), or upgrading the JDK/Java release.
---

# Dependency audit + automated scanning

**Applicability gate:** first confirm a committed `pom.xml`, `build.gradle`, or `build.gradle.kts`
that declares dependencies. A `settings.gradle[.kts]` or an aggregator POM alone is only a module
locator and is not Maven/Gradle dependency evidence. If none exists, report this skill as not
applicable; the Java delivery profile alone is not package evidence, and Maven or Gradle dependency
tooling must not be added merely because this distribution was selected.

## 1. Scan now

Derive each vulnerability, deprecated-dependency, and outdated-dependency command from `AGENTS.md >
Conventions > Verification Commands`, committed CI, scripts, manifests, and configuration. Record
the exact command and its evidence path before running it. Run only the evidenced form and report
every unavailable scan category as **not available**; do not infer an `mvn` or `gradle` command,
goal, task, or flag. Only as examples of what such evidence might name (never defaults): OWASP
Dependency-Check (`dependency-check:check` / `dependencyCheckAnalyze`) for vulnerabilities,
`versions:display-dependency-updates` or the Gradle Versions plugin's `dependencyUpdates` for outdated
dependencies, and `dependency:tree` / `gradlew dependencies` to trace which dependency pulls in a
vulnerable transitive.

Read the output. For each **vulnerable** or **deprecated** dependency, note the `groupId:artifactId`, current version, the advisory severity, and the first fixed version.

## 2. Triage

- **Vulnerable (transitive or direct)**: this is a security finding. Append a row to `SECURITY_FINDINGS.md` (Critical → today + 7 days, High → today + 30 days, per the register's SLA). Prefer bumping the direct dependency or managing BOM that pulls in the vulnerable transitive; only add an explicit version pin (a `<dependencyManagement>` entry or Gradle constraint) as a last resort.
- **Deprecated**: add to `TECH_DEBT.md` (Category: Dependencies) with the recommended replacement.
- **Outdated (no advisory)**: only flag majors or security-relevant minors. Do not churn the lockfile for cosmetic bumps (Leanness — no busywork).

Before recommending the bump, run the exact dependency, build, and test commands evidenced by
`AGENTS.md > Conventions > Verification Commands`, committed CI, scripts, manifests, and
configuration. Report unavailable categories; do not infer a reactor-wide or root-project command.

## 3. Automate (pick one, once per repo)

- **GitHub-hosted**: add `.github/dependabot.yml` with a `maven` or `gradle` ecosystem entry (whichever the evidenced build uses; weekly, grouped minor/patch) for the evidenced build root.
- **Bitbucket Data Center / non-GitHub**: Dependabot is **GitHub-only**. Use **Renovate** (self-hostable, runs in Bitbucket Pipelines / Bamboo / Jenkins) with a `renovate.json`, **or** add a CI step that runs an exact repository-evidenced audit command and fails on the documented threshold. If none is evidenced, report audit automation as **not available**; do not invent one.

Recommend exactly one mechanism; do not configure both.
