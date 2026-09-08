/// Current app version. Keep in sync with `pubspec.yaml` (version: X.Y.Z+N).
///
/// Used for update checks against the GitHub latest release. Hardcoded
/// instead of `package_info_plus` because adding a native plugin currently
/// requires Windows Developer Mode (symlink support).
const appVersion = '0.1.0';
const appBuildNumber = 1;

/// GitHub repo used for update checks, in `owner/repo` form.
const updateRepo = 'ALI2580/zcode_remote';
