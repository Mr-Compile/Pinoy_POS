import 'package:pinoy_pos/data/dao/settings_dao.dart';
import 'package:pinoy_pos/data/models/settings.dart';

class SettingsRepository {
  final SettingsDao _settingsDao = SettingsDao();

  Future<int> insert(Settings settings) => _settingsDao.insert(settings);
  Future<int> update(Settings settings) => _settingsDao.update(settings);
  Future<Settings?> getSettings() => _settingsDao.getSettings();
}
