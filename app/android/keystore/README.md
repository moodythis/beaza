# Test signing key (NOT for release)

`beaza-test.jks` signs the APKs built by CI so a new build installs over the
previous one without uninstalling (and losing data). Its password is in
`app/build.gradle.kts` on purpose: it is a test key in a private repository.

Never publish an app signed with this key. A store release needs a new key
kept outside the repository (for example in GitHub Actions secrets).
