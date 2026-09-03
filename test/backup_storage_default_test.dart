import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart'
    show PathProviderPlatform;

import 'package:pinoy_pos/services/backup_storage_service.dart';

class FakePathProvider extends PathProviderPlatform {
  final Directory appDocs;

  FakePathProvider(this.appDocs);

  @override
  Future<String?> getApplicationDocumentsPath() async => appDocs.path;

  @override
  Future<String?> getTemporaryPath() async => appDocs.path;

  @override
  Future<String?> getApplicationSupportPath() async => appDocs.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDir;
  late PathProviderPlatform originalProvider;

  setUpAll(() async {
    originalProvider = PathProviderPlatform.instance;
    appDir = await Directory.systemTemp.createTemp('pinoy_pos_storage_test_');
    PathProviderPlatform.instance = FakePathProvider(appDir);
  });

  tearDownAll(() async {
    if (await appDir.exists()) await appDir.delete(recursive: true);
    PathProviderPlatform.instance = originalProvider;
  });

  test('getDefaultDesktopLocation returns a writable location', () async {
    final storage = BackupStorageService();
    final location = await storage.getDefaultDesktopLocation();
    expect(location, isNotNull);
    expect(location!.isNone, isFalse);
    expect(await storage.isLocationValid(location), isTrue);
  });
}
