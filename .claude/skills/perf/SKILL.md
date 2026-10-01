---
name: perf
description: >
  Scan a Java codebase (or a specific file/path) for performance anti-patterns and
  produce a prioritised, actionable findings report.
  USE FOR: pre-release performance audits, reviewing a hot path before optimising it,
  systematic anti-pattern detection across a module or whole repo, secondary validation
  after manual profiling, or when TECH_DEBT.md has open Performance items to investigate.
  DO NOT USE FOR: runtime profiling (use Java Flight Recorder or async-profiler instead), fixing a single
  known performance issue you've already located, benchmarking (use /benchmark or JMH), or
  auditing code that has already been through a dedicated perf review this sprint.
---

# Performance Anti-Pattern Scan

Scans Java source for ~50 known anti-patterns across concurrency, persistence, transactions,
web/HTTP clients, memory, strings, collections/streams, regex, I/O, serialization, and caching.
Produces tiered severity findings with file locations and one-line fixes.

---

## Step 1 — Scope and signals

Identify the scan target (whole repo, a module, a directory, or specific files).

Grep for code signals to determine which categories apply:

```
@Async / CompletableFuture / ExecutorService / parallelStream → enables Concurrency category
@Entity / JpaRepository / EntityManager / JdbcTemplate        → enables Persistence category
@Transactional                                                → enables Transactions category
RestTemplate / RestClient / WebClient / HttpClient / Mono     → enables Web / HTTP category
new byte[] / ThreadLocal / boxed Integer / Long               → enables Memory category
String + / String.format / .replace / .toLowerCase            → enables Strings category
.stream() / Collectors / new ArrayList / new HashMap          → enables Collections category
Pattern / .matches( / .replaceAll(                            → enables Regex category
InputStream / Reader / Files.read*                            → enables I/O category
ObjectMapper / JAXBContext / XMLInputFactory                  → enables Serialization category
@Cacheable / spring-boot-starter-cache                        → enables Caching category
```

Default scan depth: **standard** (all matched categories).
If the user says "quick" or "critical only" — skip Info findings.
If the user says "thorough" or "comprehensive" — add cross-file consistency checks.

---

## Step 2 — Detection recipes

Run these grep patterns against the scan target. Record hit counts and file locations.

### Concurrency

| Pattern | Grep | Severity |
|---------|------|----------|
| `.block()` / `.blockFirst()` / `.blockLast()` inside a WebFlux/Reactor pipeline (blocks an event-loop thread) | `\.block()\|\.blockFirst()\|\.blockLast()` | 🔴 Critical |
| Fire-and-forget `CompletableFuture.runAsync` / `supplyAsync` (result dropped, exceptions swallowed) | `runAsync(\|supplyAsync(` with no `.join()` / `.get()` / `.handle(` / `.whenComplete(` on the result | 🔴 Critical |
| `CompletableFuture` async stage with no executor argument (blocking work on the common `ForkJoinPool`) | `supplyAsync(\|runAsync(\|thenApplyAsync(` without an executor argument | 🟡 Moderate |
| `parallelStream()` / `.parallel()` (shared common pool; blocking work starves the whole JVM) | `parallelStream()\|\.parallel()` | 🟡 Moderate |
| Unmanaged or unbounded threading (raw `new Thread`, cached thread pool, queue with no capacity) | `new Thread(\|newCachedThreadPool\|new LinkedBlockingQueue<[^>]*>()` | 🟡 Moderate |
| `@Async` without an evidenced bounded executor (self-invoked or `private` `@Async` methods run synchronously) | `@Async\b` | 🟡 Moderate |
| `synchronized` around blocking I/O (serialises callers; can pin a virtual thread where virtual threads are evidenced) | `synchronized` in a method or block that performs I/O | 🟡 Moderate |
| `InterruptedException` swallowed without restoring the interrupt flag | `catch (InterruptedException` with no `Thread.currentThread().interrupt()` | 🟡 Moderate |
| `Future.get()` / `CompletableFuture.join()` with no timeout on a request thread | `\.get()\|\.join()` on `Future` / `CompletableFuture` receivers | 🟡 Moderate |

### Persistence (JPA / Spring Data / JDBC)

| Pattern | Grep | Severity |
|---------|------|----------|
| N+1 queries: a repository, `EntityManager` or `JdbcTemplate` call, or a LAZY association access, inside a loop | repository / `jdbcTemplate` / `entityManager` call inside a `for` / `while` / `forEach` body | 🔴 Critical |
| `findAll()` (or an unbounded `List` query) then filtering, sorting or paging in memory instead of a `Pageable` query | `findAll()` followed by `\.stream()\.filter\|\.subList(` | 🔴 Critical |
| `FetchType.EAGER` on an association (loaded on every query whether needed or not) | `FetchType\.EAGER` | 🟡 Moderate |
| `count()` compared to zero where an `existsBy…` query suffices | `\.count()\s*\(>\|!=\|==\)\s*0` | 🟡 Moderate |
| Whole-entity load for a read view (use an interface or DTO projection) | repository result mapped to a DTO that uses a few of the entity's columns | 🟡 Moderate |
| Row-by-row `save()` / `saveAndFlush()` in a loop, or bulk writes with no `hibernate.jdbc.batch_size` (batching is also defeated by `GenerationType.IDENTITY`) | `\.save(\|\.saveAndFlush(` in a loop body; `jdbc\.batch_size` absent; `GenerationType\.IDENTITY` | 🟡 Moderate |
| Open-session-in-view enabled (the Spring Boot default `spring.jpa.open-in-view=true` holds a database connection for the whole request) | `open-in-view` in `application*.yml` / `application*.properties` (absent or `true`) | 🟡 Moderate |
| HikariCP pool left at the default or sized past what the database can serve | `maximum-pool-size\|maximumPoolSize` in `application*.yml` / `application*.properties` | ℹ️ Info |

### Transactions

| Pattern | Grep | Severity |
|---------|------|----------|
| `@Transactional` scope spanning remote calls or other slow I/O (holds a database connection while waiting) | `@Transactional` methods that also call `restTemplate\|webClient\|\.send(` | 🔴 Critical |
| Misplaced `@Transactional` (self-invocation, or a `private` / `final` method — the proxy cannot apply it) | `this\.` call to a `@Transactional` method of the same class; `@Transactional` above a `private\|final` method | 🟡 Moderate |
| Read-only service paths without `@Transactional(readOnly = true)` | `@Transactional` without `readOnly` on `get` / `find` / `list` methods | ℹ️ Info |

### Web / HTTP clients

| Pattern | Grep | Severity |
|---------|------|----------|
| HTTP client constructed per request (no connection reuse or pooling) | `new RestTemplate(\|HttpClient\.newHttpClient(\|new OkHttpClient(\|HttpClients\.createDefault(` inside a method body | 🔴 Critical |
| Outbound HTTP call with no connect or read timeout (a missing timeout can hang the calling thread indefinitely) | `new RestTemplate()\|openConnection()` with no `setConnectTimeout` / `setReadTimeout` | 🟡 Moderate |
| Blocking call (JDBC, `RestTemplate`, file I/O) inside a WebFlux handler or reactive chain | `restTemplate\.\|jdbcTemplate\.\|Thread\.sleep` inside `Mono` / `Flux` operators or reactive handlers | 🔴 Critical |

### Memory / Allocations

| Pattern | Grep | Severity |
|---------|------|----------|
| `new byte[]` inside loop | inside loop body | 🔴 Critical |
| Autoboxing in hot loops (boxed `Integer` / `Long` counters, accumulators or map keys) | `for (Integer\|for (Long\|Integer [a-z]* = 0\|Long [a-z]* = 0` | 🟡 Moderate |
| String concatenation (`+` / `+=`) in loop (O(n²) allocations) | `+= ` near loop | 🟡 Moderate |
| Large arrays allocated per call instead of reused | `new.*\[\d{4,}\]` | 🟡 Moderate |
| `ThreadLocal` never `remove()`d, or a `static` collection that only grows (memory leak) | `ThreadLocal<\|static .*\(List\|Map\|Set\)<` | 🟡 Moderate |
| Exceptions as control flow (a stack trace captured per branch) | `catch (NumberFormatException\|catch (NoSuchElementException` in a loop or hot path | 🟡 Moderate |

### Strings

| Pattern | Grep | Severity |
|---------|------|----------|
| String concatenation or `String.format` in a log call (cost paid even when the level is disabled) | `log\.\(trace\|debug\|info\|warn\|error\)(.*\(+ \|String\.format\)` | 🟡 Moderate |
| Multiple `.replace()` chained (compound allocation) | `\.replace(.*\.replace(` | 🟡 Moderate |
| `toUpperCase()` / `toLowerCase()` for comparison (use `equalsIgnoreCase`, or pass an explicit `Locale`) | `\.toUpperCase()\|\.toLowerCase()` | 🟡 Moderate |
| `String.format` outside logging (prefer concatenation or `StringBuilder` on a hot path) | `String\.format(` | ℹ️ Info |
| Repeated `String.split` on hot path (regex-backed) | `\.split(` | ℹ️ Info |

### Collections / Streams

| Pattern | Grep | Severity |
|---------|------|----------|
| `.collect(Collectors.toList())` immediately before iterating (double allocation) | `\.collect(Collectors\.toList()).*for\|for.*\.collect(Collectors\.toList())` | 🟡 Moderate |
| `.stream().count()` on a `Collection` (use `.size()`) | `\.stream()\.count()` | 🟡 Moderate |
| `.findFirst().get()` / unchecked `Optional.get()` (throws on a miss; prefer `orElseThrow`) | `\.findFirst()\.get()\|\.findAny()\.get()` | 🟡 Moderate |
| Stream pipeline inside a tight loop (re-scanned each iteration, O(n·m)) | `.stream()` call inside `for` / `while` / `forEach` body | 🔴 Critical |
| `List.contains` / `indexOf` inside a loop (O(n²); use a `Set` or `Map`) | `\.contains(\|\.indexOf(` on a `List` inside a loop body | 🟡 Moderate |
| `new ArrayList<>()` / `new HashMap<>()` without a capacity hint in a loop | `new ArrayList<>()\|new HashMap<>()` without `(capacity` | ℹ️ Info |
| `containsKey` then `get` (two lookups; use `getOrDefault`, `computeIfAbsent` or `merge`) | `containsKey.*\.get(` | ℹ️ Info |
| Legacy synchronized or poor-locality collections (`Vector`, `Hashtable`, `StringBuffer`, `LinkedList`) | `new Vector<\|new Hashtable<\|new StringBuffer(\|new LinkedList<` | ℹ️ Info |

### Regex

| Pattern | Grep | Severity |
|---------|------|----------|
| `Pattern.compile(...)` inside a method on a hot path (recompiled per call; hoist to a `static final Pattern`) | `Pattern\.compile(` | 🟡 Moderate |
| `String.matches` / `replaceAll` / `replaceFirst` with a regex literal on a hot path (compiles a `Pattern` per call) | `\.matches(\|\.replaceAll(\|\.replaceFirst(` | 🟡 Moderate |
| `Pattern.matches` static (re-compiled each call) | `Pattern\.matches(` | 🟡 Moderate |

### I/O

| Pattern | Grep | Severity |
|---------|------|----------|
| Whole file read into memory (`Files.readAllBytes` / `readAllLines` / `readString`) on large or unbounded input | `Files\.readAllBytes\|Files\.readAllLines\|Files\.readString\|\.readAllBytes()` | 🟡 Moderate |
| Unbuffered byte-by-byte reads or writes (`FileInputStream` / `FileReader` with no `Buffered` wrapper) | `new FileInputStream(\|new FileReader(\|new FileOutputStream(` without a `Buffered` wrapper | 🟡 Moderate |
| Stream, reader or `Connection` opened without try-with-resources (leaked handles exhaust pools) | `new FileInputStream(\|getConnection()` outside a `try (` resource clause | 🟡 Moderate |

### Serialization

| Pattern | Grep | Severity |
|---------|------|----------|
| `new ObjectMapper()` per call or request (reuse the shared, thread-safe instance) | `new ObjectMapper(` | 🟡 Moderate |
| `JAXBContext.newInstance(...)` / `new XmlMapper(...)` per call (reflection + schema cost) | `JAXBContext\.newInstance(\|new XmlMapper(` | 🔴 Critical |
| XML parser or transformer factory created per call (`DocumentBuilderFactory`, `XMLInputFactory`, `TransformerFactory`) | `DocumentBuilderFactory\.newInstance\|XMLInputFactory\.newInstance\|TransformerFactory\.newInstance` | 🟡 Moderate |

### Caching (only where Spring Cache is evidenced)

| Pattern | Grep | Severity |
|---------|------|----------|
| `@Cacheable` on a self-invoked or `private` method (the proxy cannot apply it, so the cache is never used) | `@Cacheable` | 🟡 Moderate |
| Cache with no size or TTL bound (default `ConcurrentMapCacheManager`, or a hand-rolled `ConcurrentHashMap`) | `ConcurrentMapCacheManager\|new ConcurrentHashMap` used as a cache | 🟡 Moderate |

---

## Step 3 — Classify and scale

After collecting counts:

- Any single pattern with **50+ instances** → escalate one severity level and flag as **systematic**.
- If user identifies code as a **hot path or latency-sensitive** → escalate all 🟡 findings in that scope to 🔴.
- **Verify the inverse** for read-only transactions: report `X readOnly / Y @Transactional` so a systematic missing `readOnly = true` is visible.
- **Do not flag** `static final Pattern` constants — they're already compiled once.
- **Do not flag** stream pipelines on cold paths (startup, one-time config loading).

---

## Step 4 — Output format

Group by severity. For each finding:

```
🔴 PERF-01: fire-and-forget CompletableFuture.runAsync calls (3 instances)
Impact: swallows exceptions silently, runs unbounded on the common pool
Files: OrderService.java:42, PaymentHandler.java:17, NotificationJob.java:88
Fix: run on a managed executor and handle failures (`handle` / `whenComplete`); wire exceptions to the caller or the logger
```

End with a summary table:

| Severity | Count | Systematic? |
|----------|-------|-------------|
| 🔴 Critical | N | list any |
| 🟡 Moderate | N | list any |
| ℹ️ Info | N | — |

Close with: _"Results are non-deterministic grep-based heuristics. Confirm Critical findings by reading the affected code before fixing. Benchmark before and after any Critical change on hot paths."_

---

## Step 5 — TECH_DEBT.md integration

For each 🔴 Critical and any 🟡 Moderate flagged as systematic, offer to append a row to TECH_DEBT.md:

```
| PERFxx | Performance | Critical | <files> | <issue> | <fix> | M |
```

Only append — never overwrite existing rows.
