import 'package:esp_ble_prov_dart/esp_ble_prov_dart.dart';

class ProvisioningService {
  Future<void> provision({
    required String deviceName,
    required String proofOfPossession,
    required String ssid,
    required String password,
  }) async {
    final name = deviceName.trim();
    if (!name.startsWith('PROV_BW_')) {
      throw Exception('Device name must start with PROV_BW_.');
    }
    if (proofOfPossession.trim().isEmpty || ssid.trim().isEmpty) {
      throw Exception('Device code and Wi-Fi name are required.');
    }
    final provisioner = EspBleProvisioner(
      deviceNamePrefix: name,
      security: Security1(pop: proofOfPossession.trim()),
      requestAndroidFineLocation: true,
    );
    try {
      final devices = await provisioner.scanDevices();
      final exact = devices.where((device) => device.name == name);
      if (exact.isEmpty) {
        throw Exception('Camera $name was not found over Bluetooth.');
      }
      await provisioner.connect(device: exact.first);
      await provisioner.establishSession();
      await provisioner.sendCredentials(
        WiFiConfig(ssid: ssid.trim(), passphrase: password),
      );
    } finally {
      if (provisioner.isConnected) await provisioner.disconnect();
    }
  }
}
