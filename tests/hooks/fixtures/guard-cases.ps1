# Shared guard fixture library. Each case is content-only; the harness's New-ClaudeEvent /
# New-CopilotEvent wrap it into each surface's field names, so both supported surfaces receive
# identical logical input.
$azureKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8' + 'gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+Pw' + '=='
$GuardCases = @(
    @{ n='java // NOSONAR suppression';      f='src/main/java/com/acme/Foo.java';     c='int x = compute(); // NOSONAR';                     block=$true; policy='test-defeat/suppression' }
    @{ n='java // NOPMD suppression';         f='src/main/java/com/acme/Foo.java';     c='String s = raw; // NOPMD';                          block=$true }
    @{ n='java CHECKSTYLE:OFF';               f='src/main/java/com/acme/Foo.java';     c='// CHECKSTYLE:OFF';                                 block=$true }
    @{ n='java @SuppressFBWarnings';          f='src/main/java/com/acme/Foo.java';     c='@SuppressFBWarnings("NP_NULL_ON_SOME_PATH") void f() {}'; block=$true }
    @{ n='java @SuppressWarnings("all")';     f='src/main/java/com/acme/Foo.java';     c='@SuppressWarnings("all") public class Foo {}';      block=$true }
    # A rule name hidden in an array next to an allowed javac key still blocks.
    @{ n='java @SuppressWarnings PMD in array'; f='src/main/java/com/acme/Foo.java';   c='@SuppressWarnings({"unchecked", "PMD.UnusedPrivateField"}) class Foo {}'; block=$true }
    @{ n='java JUnit 5 @Disabled';            f='src/test/java/com/acme/FooTest.java'; c='@Disabled("flaky") @Test void t() {}';             block=$true }
    @{ n='java qualified @Disabled';          f='src/test/java/com/acme/FooTest.java'; c='@org.junit.jupiter.api.Disabled';                  block=$true }
    @{ n='java JUnit 4 @Ignore';              f='src/test/java/com/acme/FooTest.java'; c='@Ignore @Test public void t() {}';                  block=$true }
    @{ n='java TestNG @Test(enabled = false)'; f='src/test/java/com/acme/FooTest.java'; c='@Test(enabled = false) public void t() {}';        block=$true }
    # MULTI-LINE ANNOTATION ARGUMENTS. [^)]* spans a newline, so a split annotation still blocks,
    # while a legitimate split argument list must still pass: a false positive on correct work is
    # what teaches people to bypass the guard entirely.
    @{ n='java TestNG @Test(<nl>enabled=false) split'; f='src/test/java/com/acme/FooTest.java'; c="@Test(groups = `"slow`",`n      enabled = false)`npublic void t() {}"; block=$true }
    @{ n='java legit split @Test arguments';  f='src/test/java/com/acme/FooTest.java'; c="@Test(groups = `"slow`",`n      timeOut = 1000)`npublic void t() {}"; block=$false }
    @{ n='java assertTrue(true) tautology';    f='src/test/java/com/acme/FooTest.java'; c='assertTrue(true);';                                block=$true }
    @{ n='java Assertions.assertFalse(false)'; f='src/test/java/com/acme/FooTest.java'; c='Assertions.assertFalse(false, "never");';         block=$true }
    @{ n='java assertThat(true).isTrue()';     f='src/test/java/com/acme/FooTest.java'; c='assertThat(true).isTrue();';                       block=$true }
    @{ n='ts eslint-disable';                  f='src/app.ts';                c='// eslint-disable-next-line';                          block=$true }
    @{ n='ts @ts-ignore';                      f='src/app.ts';                c='// @ts-ignore';                                        block=$true }
    @{ n='spec fit() focused';                 f='src/app.spec.ts';           c="fit('x', () => { expect(1).toBe(1); });";              block=$true }
    @{ n='spec xit() skipped';                 f='src/app.spec.ts';           c="xit('x', () => {});";                                  block=$true }
    @{ n='spec expect(true).toBe(true)';       f='src/app.spec.ts';           c='expect(true).toBe(true);';                             block=$true }
    @{ n='mixed-case .JAVA filename routes';   f='src/main/java/Foo.JAVA';    c='int x = compute(); // NOSONAR';                        block=$true }
    @{ n='uppercase .TS filename routes';      f='src/app.TS';                c='// eslint-disable-next-line';                          block=$true }
    @{ n='uppercase .SPEC.TS filename routes'; f='src/app.SPEC.TS';           c="fit('x', () => {});";                                  block=$true }
    @{ n='multiline Java test class';          f='src/test/java/com/acme/WholeFileTest.java'; c="import org.junit.jupiter.api.*;`n`nclass WholeFileTest {`n    @Disabled`n    @Test`n    void t() { }`n}"; block=$true }
    @{ n='multiline TS spec';                  f='src/whole.spec.ts';         c="describe('whole', () => {`n  xit('skipped', () => {});`n});"; block=$true }
    @{ n='offending construct mid-file';       f='src/middle.ts';             c="const before = 1;`n// eslint-disable-next-line`nconst after = 2;"; block=$true }
    @{ n='secret AWS access key id';           f='src/main/java/Deploy.java'; c='String k = "AKIAIOSFODNN7EXAMPLE";';                   block=$true }
    @{ n='classic GitHub ghp token';           f='src/main/java/Deploy.java'; c='String t = "ghp_0123456789abcdefghijklmnopqrstuvwxyz";'; block=$true }
    @{ n='classic GitHub gho token';           f='src/main/java/Deploy.java'; c='String t = "gho_0123456789abcdefghijklmnopqrstuvwxyz";'; block=$true }
    @{ n='classic GitHub ghu token';           f='src/main/java/Deploy.java'; c='String t = "ghu_0123456789abcdefghijklmnopqrstuvwxyz";'; block=$true }
    @{ n='classic GitHub ghs token';           f='src/main/java/Deploy.java'; c='String t = "ghs_0123456789abcdefghijklmnopqrstuvwxyz";'; block=$true }
    @{ n='classic GitHub ghr token';           f='src/main/java/Deploy.java'; c='String t = "ghr_0123456789abcdefghijklmnopqrstuvwxyz";'; block=$true }
    @{ n='fine-grained GitHub token';          f='src/main/java/Deploy.java'; c='String t = "github_pat_1234567890123456789012_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567";'; block=$true }
    @{ n='secret private key block';           f='src/main/java/Deploy.java'; c='-----BEGIN RSA PRIVATE KEY-----';                      block=$true; policy='secret' }
    @{ n='hardcoded credential literal';       f='src/main/java/com/acme/AuthService.java'; c='String password = "hunter2hunter2";';                     block=$true }
    @{ n='connection string Password';         f='src/main/java/com/acme/AuthService.java'; c='String connectionString = "Server=db;User Id=sa;Password=hunter2;Database=app";'; block=$true }
    @{ n='connection string URI userinfo';     f='src/main/java/com/acme/AuthService.java'; c='String connectionString = "postgres://user:hunter2@host/db";'; block=$true }
    # The test/sample exemption is anchored to whole path tokens: "test" inside Latest and "spec"
    # inside Specification no longer exempt production code from the credential check.
    # $azureKey is assembled from two halves at load time: a literal 88-character key in the
    # committed bytes is rejected by GitHub push protection as an Azure Storage account key
    # (observed 2026-09-20), the same reason the OutgoingCommits fixture builds its token at runtime.
    @{ n='credential in LatestRatesClient.java'; f='src/main/java/com/acme/LatestRatesClient.java'; c='String password = "hunter2hunter2";'; block=$true }
    @{ n='credential in Specification.java';     f='src/main/java/com/acme/Specification.java';     c='String password = "hunter2hunter2";'; block=$true }
    @{ n='Azure storage AccountKey';           f='src/main/java/Storage.java'; c="String cs = `"DefaultEndpointsProtocol=https;AccountName=acct;AccountKey=$azureKey;EndpointSuffix=core.windows.net`";"; block=$true }
    @{ n='Azure AccountKey in a test path';    f='src/test/java/StorageTest.java'; c="String cs = `"AccountName=acct;AccountKey=$azureKey`";"; block=$true }
    @{ n='Azure SAS token sig=';               f='src/main/java/Storage.java'; c='String url = "https://acct.blob.core.windows.net/c/b?sv=2022-11-02&ss=b&srt=o&sp=r&se=2026-01-01T00:00:00Z&sig=AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8%3D";'; block=$true }

    @{ n='clean .java (allow)';                f='src/main/java/com/acme/Foo.java'; c='public int add(int a, int b) { return a + b; }';   block=$false }
    @{ n='clean .spec.ts real assertion';      f='src/app.spec.ts';           c="it('adds', () => { expect(add(1,2)).toBe(3); });";     block=$false }
    @{ n='RxJS skip() not a test-skip';        f='src/stream.spec.ts';        c='source$.pipe(skip(1)).subscribe();';                   block=$false }
    @{ n='java @JsonIgnore near-miss (allow)'; f='src/main/java/com/acme/Dto.java';  c='@JsonIgnore private String internalId;';         block=$false }
    @{ n='java enum Ignore member (allow)';    f='src/main/java/com/acme/Mode.java'; c='public enum Mode { NONE, Ignore, ALL }';           block=$false }
    @{ n='java Disabled import only (allow)';  f='src/test/java/com/acme/FooTest.java'; c='import org.junit.jupiter.api.Disabled;';       block=$false }
    @{ n='java @DisabledOnOs conditional (allow by design)'; f='src/test/java/com/acme/FooTest.java'; c='@DisabledOnOs(OS.WINDOWS) @Test void t() {}'; block=$false }
    @{ n='java narrow @SuppressWarnings("unchecked") (allow)'; f='src/main/java/com/acme/Box.java'; c='@SuppressWarnings("unchecked") // safe: only T is ever stored'; block=$false }
    @{ n='java TestNG @Test(enabled = true) (allow)'; f='src/test/java/com/acme/FooTest.java'; c='@Test(enabled = true) public void t() {}'; block=$false }
    @{ n='java real assertTrue (allow)';       f='src/test/java/com/acme/FooTest.java'; c='assertTrue(validator.isValid(order));';            block=$false }
    @{ n='credential in *Test file (allow)';   f='src/main/java/com/acme/AuthServiceTest.java'; c='String password = "hunter2hunter2";'; block=$false }
    @{ n='credential in src/test tree (allow)'; f='src/test/java/com/acme/AuthClient.java'; c='String password = "hunter2hunter2";';    block=$false }
    @{ n='credential in __mocks__ (allow)';    f='src/__mocks__/auth.ts';     c="const password = 'hunter2hunter2';";                   block=$false }
    @{ n='Spring properties password';         f='src/main/resources/application.properties'; c="server.port=8080`nspring.datasource.password=hunter2hunter2"; block=$true }
    @{ n='Spring YAML client-secret';          f='src/main/resources/application-prod.yml'; c="spring:`n  security:`n    oauth2:`n      client:`n        registration:`n          app:`n            client-secret: hunter2hunter2"; block=$true }
    @{ n='Spring placeholder password (allow)'; f='src/main/resources/application.yml'; c="spring:`n  datasource:`n    password: `${DB_PASSWORD}"; block=$false }
    @{ n='Spring keystore changeit default (allow)'; f='src/main/resources/application.properties'; c='server.ssl.key-store-password=changeit'; block=$false }
    @{ n='Spring test resources password (allow)'; f='src/test/resources/application.yml'; c="spring:`n  datasource:`n    password: hunter2hunter2"; block=$false }
    @{ n='credential in application-development.yml (allow)'; f='src/main/resources/application-development.yml'; c='password: hunter2hunter2'; block=$false }
    @{ n='Azurite well-known dev key (allow)'; f='src/main/java/Storage.java'; c='String cs = "AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==";'; block=$false }
    @{ n='SAS sig= without a token (allow)';   f='src/main/java/Storage.java'; c='String q = "?sv=2022-11-02&sig=";';                        block=$false }
    @{ n='passwordless connection string';     f='src/main/java/com/acme/AuthService.java'; c='String connectionString = "Server=localhost;Trusted_Connection=True";'; block=$false }
    @{ n='near-miss fine-grained PAT';         f='src/main/java/Deploy.java'; c='String t = "github_pat_too_short";';                   block=$false }
    # Tagged `secret` so the invalid-regex red test observes both fail-closed directions: the
    # private-key case must still block, while this near-miss must turn red if every secret probe
    # is conservatively blocked. A policy filter containing only blocking cases is an inert oracle.
    @{ n='public key block near-miss';          f='src/main/java/Deploy.java'; c='-----BEGIN PUBLIC KEY-----';                           block=$false; policy='secret' }
    @{ n='case-sensitive assertTrue near-miss'; f='src/test/java/com/acme/FooTest.java'; c='ASSERTTRUE(true);';                     block=$false }
    @{ n='case-sensitive ESLINT near-miss';    f='src/app.ts';                c='// ESLINT-DISABLE-next-line';                          block=$false }
)
