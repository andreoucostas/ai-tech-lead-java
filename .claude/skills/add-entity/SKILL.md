---
name: add-entity
description: >
  Use when the user wants to add a persisted JPA domain entity backed by a new project-evidenced
  table or equivalent store.
  Covers entity placement, persistence mapping/registration only where evidenced, migration or
  schema-change review, and the repository's verification path.
  USE FOR: introducing a completely new domain concept that the project evidences as requiring
  its own persisted representation.
  DO NOT USE FOR: adding columns or relationships to an existing entity, modifying an existing
  migration, writing queries against an existing entity, creating value objects with no table.
---

# Add a new persisted entity

Match AGENTS.md > Conventions > Data Access and > Architecture. The project, rather than this
skill, selects the persistence mechanism and entity placement.

## Project-derived pattern authority

Derive this operation's shape from first-party implementation, configuration, tests, and owner documentation. If this skill's consumer-owned `references/project-pattern.md` exists, read it on demand as scoped evidence. Generated recipes are leads only. Exclude irrelevant scope, investigate conflicting applicable evidence, and ask or retain only correctness-material uncertainty. The generic steps below are conditional fallbacks: they never authorize a container, library, layer, interface, or token the project does not evidence.

0. **Find the project’s persistence pattern before choosing a mechanism.** Confirm a repository-evidenced Java project, then inspect first-party entity/model, access, mapping, schema, and test examples. If the evidenced data access is not JPA (Spring Data JPA or Hibernate), report this skill as **not applicable**. Search the requested concept and business key; if it exists, extend it through ordinary `/feature` work instead of creating a competing store. If no persistence pattern is readable, retain that correctness-material uncertainty and ask; do not introduce JPA or another library from this skill.
1. Place the entity/model and its invariants where the evidenced persistence pattern does.
2. Add mapping/configuration only when that mechanism and separation are evidenced (for example, JPA `@Entity`/`@Table`/`@Column` annotations on the class, or a separate `orm.xml` mapping); otherwise follow the project’s actual mapping shape.
3. Add the entity to an access surface only when the project’s mechanism evidences one (for example, a Spring Data `JpaRepository<T, ID>`).
4. Derive the exact schema-change or migration command from `AGENTS.md > Conventions > Verification Commands`, committed CI, scripts, manifests, or configuration. The schema change goes through the project’s evidenced migration vehicle (for example a Flyway `V<version>__<description>.sql` script or a Liquibase changeSet), never through Hibernate `ddl-auto=update` outside tests. Run it only when the command and mechanism are evidenced; otherwise report schema generation as **not available** and do not infer `flyway:migrate`, `liquibase:update`, or any substitute command.
5. **Review the written or generated schema change before applying.** Confirm types, indexes, and data-affecting changes (locking, backfill, rollback) through the project’s evidenced review path.

If the project evidences a read-mostly query pattern, plan the typical query path and preserve its query semantics (for example, `@Transactional(readOnly = true)` only where Spring Data JPA evidence selects it).

Derive build, test, format, lint, migration/deploy, and data-validation commands from `AGENTS.md >
Conventions > Verification Commands`, committed CI, scripts, manifests, and configuration. Run only
applicable evidenced commands and report every unavailable category as **not available**.
