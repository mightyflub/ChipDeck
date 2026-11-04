// The app version, set by CI with --dart-define=CHIPDECK_VERSION=...
// (see tools/ci-version.sh). Local builds show "dev".
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
const appVersion = String.fromEnvironment(
  'CHIPDECK_VERSION',
  defaultValue: 'dev',
);
