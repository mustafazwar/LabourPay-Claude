# Labour Pay (Flutter)

## Set up (5 minutes)
1. `flutter create labour_pay` then open the folder (or use your existing project).
2. Replace `pubspec.yaml` with the one in this zip. Delete the default `test/widget_test.dart`.
3. Delete everything inside `lib/` and copy ALL 19 files from this zip's `lib/` folder into it (flat, no sub-folders).
4. Run `flutter pub get` then `flutter run`.

## Files (all in lib/)
main.dart, format.dart, db.dart, utils.dart, today_screen.dart, start_day_screen.dart,
day_ledger_screen.dart, add_work_screen.dart, add_advance_screen.dart, add_tip_screen.dart,
close_day_screen.dart, slip_screen.dart, labour_list_screen.dart, labour_ledger_screen.dart,
rates_screen.dart, days_screen.dart, reports_screen.dart, backup_screen.dart, settings_screen.dart

## If the build complains
- "minSdkVersion": in android/app/build.gradle set minSdk to 21 or higher (24 is safe).
- Plugin/compileSdk errors: run `flutter upgrade`, then `flutter clean && flutter pub get`.
- Dart 3 is required (records are used in days_screen.dart). Any Flutter released since 2023 has it.
