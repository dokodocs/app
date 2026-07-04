import 'package:dokodocs/core/database/database.dart';
import 'package:dokodocs/core/database/database_provider.dart';
import 'package:dokodocs/main.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // drift's stream-close notifications and Home's real DB-backed
  // StreamProviders use real Timers that don't play well with the default
  // fake-async test binding (a stream-close Timer ends up "pending" at
  // teardown even though nothing is actually leaking). LiveTestWidgets-
  // FlutterBinding runs the test in real time instead, matching how the
  // app actually behaves and sidestepping that class of false positive.
  LiveTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots to an empty, localized home screen', (tester) async {
    final testDb = AppDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(testDb.close);
    // Onboarding now gates Home behind UserSettings.onboardingComplete —
    // seed it so this test still exercises Home directly, as its name
    // says. The onboarding flow itself gets its own test (Stage D).
    await testDb
        .into(testDb.userSettings)
        .insert(
          const UserSettingsCompanion(
            id: Value(0),
            onboardingComplete: Value(true),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(testDb)],
        child: const DokoDocsApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Search now lives in the app bar (its hint confirms Home rendered),
    // and the empty state still owns the fresh-install case.
    expect(find.text('Search documents'), findsOneWidget);
    expect(find.text('Scan your first document'), findsOneWidget);
  });
}
