import 'dart:developer' as dev;

import 'package:mygenie_restaurant/helper/wifi_printer/network_printer_target.dart';
import 'package:mygenie_restaurant/helper/wifi_printer/wifi_printer_service.dart';
import 'package:mygenie_restaurant/view/base/custom_snackbar.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

/// Drop-in replacement for the `PrintBluetoothThermal` calls used by the
/// iOS / iPadOS print functions.
///
/// * `wifiPrinter == null` → every call goes to `PrintBluetoothThermal`
///   exactly as before (Bluetooth behaviour is unchanged).
/// * `wifiPrinter != null` → the job goes over TCP to that printer.
///
/// Like `PrintBluetoothThermal`, it has one current connection. Code that
/// prints to several printers at once should use
/// [WifiPrinterService.printBytes] instead.
class IosPrintTransport {
  IosPrintTransport._();

  static WifiPrinterSession? _session;
  static WifiPrintException? lastError;
  static DateTime? _lastHintShown;

  /// True while the current connection is a Wi-Fi/LAN printer.
  static bool get isWifiActive => _session != null;

  static Future<bool> connect({
    required String macPrinterAddress,
    NetworkPrinterTarget? wifiPrinter,
  }) async {
    lastError = null;
    await _closeWifiSession();
    if (wifiPrinter == null) {
      return PrintBluetoothThermal.connect(
          macPrinterAddress: macPrinterAddress);
    }
    try {
      _session = await WifiPrinterService.instance.openSession(wifiPrinter);
      return true;
    } on WifiPrintException catch (e) {
      _report(e);
      return false;
    } catch (e) {
      _report(WifiPrintException(
          WifiPrintErrorCode.unreachableOrPermissionDenied,
          'Could not connect to ${wifiPrinter.label} (${wifiPrinter.key})',
          cause: e));
      return false;
    }
  }

  static Future<bool> writeBytes(List<int> bytes) async {
    final session = _session;
    if (session == null) {
      return PrintBluetoothThermal.writeBytes(bytes);
    }
    try {
      await session.write(bytes);
      return true;
    } on WifiPrintException catch (e) {
      _report(e);
      return false;
    } catch (e) {
      _report(WifiPrintException(WifiPrintErrorCode.sendFailed,
          'Send failed to ${session.target.key}',
          mayHavePrinted: true, cause: e));
      return false;
    }
  }

  /// Same shape as `PrintBluetoothThermal.disconnect` (a getter).
  static Future<bool> get disconnect async {
    if (_session != null) {
      await _closeWifiSession();
      return true;
    }
    return PrintBluetoothThermal.disconnect;
  }

  /// Same shape as `PrintBluetoothThermal.connectionStatus` (a getter).
  static Future<bool> get connectionStatus async {
    final session = _session;
    if (session != null) return session.isOpen;
    return PrintBluetoothThermal.connectionStatus;
  }

  static Future<void> _closeWifiSession() async {
    final s = _session;
    _session = null;
    if (s != null) await s.close();
  }

  static void _report(WifiPrintException e) {
    lastError = e;
    dev.log('[IosPrintTransport] $e');
    // The calling screen already shows its own "print failed" message.
    // Add the reason, at most once every 30 seconds so a batch of KOTs does
    // not flood the screen.
    final now = DateTime.now();
    if (_lastHintShown == null ||
        now.difference(_lastHintShown!) > const Duration(seconds: 30)) {
      _lastHintShown = now;
      try {
        showErrorToast(e.message);
      } catch (_) {}
    }
  }
}
