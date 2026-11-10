# Test signing key (NOT for release)

CI signs the APKs with a test key so a new build installs over the previous
one without uninstalling (and losing data). The key is not in the repository:
CI writes it here from the `BEAZA_KEYSTORE_B64` secret (the .jks file in
base64) and reads its password from `BEAZA_KEYSTORE_PASSWORD`. Without these
secrets the build is signed with the debug key, which will not install over a
build signed with the test key.

Never publish an app signed with this key. A store release needs its own key,
also kept outside the repository.
