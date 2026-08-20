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

# Trixie rather than bookworm, purely for the JRE below.
FROM node:22-trixie-slim

# JDK 21 is what firebase-tools 15 needs — it refuses to start the emulator on
# anything below it, which is why CI pins Temurin 21 too.
#
# Debian 13 (trixie) carries openjdk-21 in main, so this is a plain install
# from the mirror the base image already uses. Two other routes were tried and
# rejected: Adoptium's apt repository failed TLS from inside the container
# (`SSL_ERROR_SYSCALL`), and bookworm-backports has no openjdk-21 candidate at
# all. Neither is worth an extra host or a pinned backport when the stable
# release has the package.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openjdk-21-jre-headless \
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
