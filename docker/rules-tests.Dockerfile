# Runs the Firestore rules suite without installing Node or a JVM on the host.
#
# These tests are the only verification of the entire cloud security model, and
# they need the Firestore emulator — a Java process — rather than the Flutter
# toolchain. On a workstation with neither Node nor a JDK that meant the suite
# could only ever run in CI, so a rules change could not be checked before
# pushing it. This image is the same pairing CI uses (Node 22, Temurin 21), so
# a pass here means the same thing a pass there does.
#
# Build and run from the repository root via docker/rules-tests.compose.yml.

FROM node:22-bookworm-slim

# Temurin 21, not Debian's default 17: firebase-tools 15 refuses to start the
# emulator on anything below 21. Taken from Adoptium's apt repository rather
# than bookworm-backports, which is the same source CI's setup-java action
# uses and is not subject to a backport being withdrawn.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public \
        | gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" \
        > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends temurin-21-jre \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencies first, so editing firestore.rules does not reinstall them.
COPY package.json package-lock.json ./
RUN npm ci

# The emulator jar is ~60MB and is otherwise fetched on every run. Baking it
# into the image keeps a rules edit to a few seconds and lets the suite run
# with no network at all.
RUN npx firebase setup:emulators:firestore

# The rules, their tests, and the emulator's own configuration. Everything
# else in the repository is the Flutter app and has no bearing on these tests.
COPY firebase.json firestore.rules firestore.indexes.json ./
COPY test/firestore-rules ./test/firestore-rules

CMD ["npm", "run", "test:rules"]
