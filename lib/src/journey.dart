import 'migration.dart';
import 'migration_report.dart';
import 'storage.dart';

/// Create a [Journey] that will run a series of one time executed migrations.
/// All migrations that occur over the lifetime of your app can be provided,
/// only migrations that have not been run will be executed.
class Journey {
  /// Create a new [Journey] instance.
  ///
  /// Provide a list of all [Migration]s that have occurred over the lifetime of your app.
  /// When calling [migrate], only the [Migration]s that have not been ran will be executed.
  ///
  /// By default, a [Journey] uses [FileStorage] to keep track of what [Migration]s have been executed.
  /// You can provide an alternative [Storage] if that better fits your needs or app.
  Journey({
    required List<Migration> migrations,
    Storage? storage,
  })  : _migrations = migrations,
        _storage = storage ?? FileStorage();

  final List<Migration> _migrations;
  final Storage _storage;

  /// Run all [Migration]s that have not been executed for this user
  /// Returns a list of [MigrationReport]s which can be used for analytical purposes.
  /// The list of [MigrationReport]s only contains the reports of the executed migrations.
  Future<List<MigrationReport>> migrate() async {
    final previousMigrations = await _storage.getAll();
    final previousMigrationIds = previousMigrations
        .map((report) => report.migrationId)
        .toList(growable: false);

    final reports = <MigrationReport>[];

    final migrations = _migrations
        .where((migration) => !previousMigrationIds.contains(migration.id))
        .toList();

    for (var migration in migrations) {
      try {
        final result = await migration.migrate();

        reports.add(MigrationReport.withResult(
            migrationId: migration.id, result: result));
      } on Exception catch (exception) {
        reports.add(MigrationReport.failed(
            migrationId: migration.id, errorMessage: exception.toString()));
      }
    }

    await _storage.store([...previousMigrations, ...reports]);

    return reports;
  }

  /// Rollback the provided migrations. This also means they will be executed again next time [migrate] is called
  Future<void> rollback() async {
    final rolledBackMigrationIds = <String>[];

    for (var migration in _migrations) {
      await migration.rollback();
      rolledBackMigrationIds.add(migration.id);
    }

    final reports = (await _storage.getAll())
        .where((report) =>
            !rolledBackMigrationIds.any((id) => id == report.migrationId))
        .toList();

    await _storage.store(reports);
  }

  /// Revoke all reports, meaning they will be executed again next time [migrate] is called
  Future<void> reset() async => await _storage.clear();
}
