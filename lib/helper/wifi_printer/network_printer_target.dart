import 'dart:io';

import 'package:get/get.dart';
import 'package:mygenie_restaurant/controller/auth_controller.dart';
import 'package:mygenie_restaurant/data/model/response/profile_model.dart';

/// A thermal printer reachable over Wi-Fi / Ethernet (raw TCP, ESC/POS).
///
/// The printer address comes from the existing profile field
/// `wifi_printer_ip`. A custom port can be given as `ip:port`
/// (for example `192.168.1.50:9101`). Without a port, 9100 is used.
class NetworkPrinterTarget {
  static const int defaultPort = 9100;

  final String host;
  final int port;
  final String label;
  final int paperSize;

  const NetworkPrinterTarget({
    required this.host,
    this.port = defaultPort,
    this.label = '',
    this.paperSize = 80,
  });

  /// Unique key per physical printer, used for per-printer job locks.
  String get key => '$host:$port';

  @override
  String toString() => 'NetworkPrinterTarget($label $host:$port ${paperSize}mm)';

  /// Parses `host`, `host:port` or `[ipv6]:port`. Returns null if invalid.
  static NetworkPrinterTarget? parse(
    String? raw, {
    String label = '',
    int paperSize = 80,
  }) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;

    String host = value;
    int port = defaultPort;

    if (value.startsWith('[')) {
      // [IPv6]:port
      final end = value.indexOf(']');
      if (end <= 1) return null;
      host = value.substring(1, end);
      final rest = value.substring(end + 1);
      if (rest.startsWith(':')) {
        final p = int.tryParse(rest.substring(1));
        if (p == null) return null;
        port = p;
      } else if (rest.isNotEmpty) {
        return null;
      }
    } else if (':'.allMatches(value).length == 1) {
      // IPv4/hostname with port
      final parts = value.split(':');
      host = parts[0].trim();
      final p = int.tryParse(parts[1].trim());
      if (p == null) return null;
      port = p;
    }

    if (!isValidHost(host) || !isValidPort(port)) return null;
    return NetworkPrinterTarget(
      host: host,
      port: port,
      label: label,
      paperSize: paperSize == 58 ? 58 : 80,
    );
  }

  static bool isValidPort(int port) => port > 0 && port <= 65535;

  static final RegExp _ipv4 = RegExp(
      r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$');
  static final RegExp _hostname = RegExp(
      r'^(?=.{1,253}$)([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$');

  /// Accepts IPv4, IPv6 and local host names (e.g. `printer.local`).
  /// Rejects anything that looks like a broken IPv4 address (e.g. `192.168.1`).
  static bool isValidHost(String host) {
    if (host.isEmpty) return false;
    if (_ipv4.hasMatch(host)) return true;
    if (RegExp(r'^[\d.]+$').hasMatch(host)) return false;
    if (host.contains(':')) {
      return InternetAddress.tryParse(host)?.type == InternetAddressType.IPv6;
    }
    return _hostname.hasMatch(host);
  }
}

/// Decides, from the existing printer profile, whether an iOS / iPadOS print
/// job should go to a Wi-Fi/LAN printer instead of Bluetooth.
///
/// To keep existing installations exactly as they are, Wi-Fi is used only when:
///   * the app runs on iOS / iPadOS,
///   * the printer is configured with type `wifi` (profile `printer_name`),
///   * a valid `wifi_printer_ip` is set, and
///   * no Bluetooth MAC (`mac_printer_ip`) is configured for that printer.
/// A printer that already has a Bluetooth MAC keeps printing over Bluetooth.
class NetworkPrinterResolver {
  NetworkPrinterResolver._();

  static bool get _isIOS {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  static ProfileModel? get _profile {
    try {
      return Get.isRegistered<AuthController>()
          ? Get.find<AuthController>().profileModel
          : null;
    } catch (_) {
      return null;
    }
  }

  static NetworkPrinterTarget? _resolve({
    required String? type,
    required String? wifiIp,
    required String? mac,
    required String label,
    required int? paperSize,
  }) {
    if (!_isIOS) return null;
    if ((type ?? '').trim().toLowerCase() != 'wifi') return null;
    if ((mac ?? '').trim().isNotEmpty) return null;
    return NetworkPrinterTarget.parse(
      wifiIp,
      label: label,
      paperSize: paperSize == 58 ? 58 : 80,
    );
  }

  /// Wi-Fi target for the BILL printer, or null to keep Bluetooth.
  static NetworkPrinterTarget? billPrinter() {
    final p = _profile;
    if (p == null) return null;
    return _resolve(
      type: p.billPrinterType,
      wifiIp: p.billWifiIp,
      mac: p.macBillPrinterIp,
      label: 'BILL',
      paperSize: p.billPrinterPaperRoll,
    );
  }

  /// Wi-Fi target for a KOT/station printer, or null to keep Bluetooth.
  static NetworkPrinterTarget? kotPrinter(RestaurantPrinterNew? printer) {
    if (printer == null) return null;
    return _resolve(
      type: printer.printerName,
      wifiIp: printer.wifiPrinterIp,
      mac: printer.macPrinterIp,
      label: printer.areaName ?? 'KOT',
      paperSize: printer.printerPaperRoll,
    );
  }

  /// Wi-Fi target for `profileModel.restaurantPrinterNew[index]`.
  static NetworkPrinterTarget? kotPrinterAt(int index) {
    final list = _profile?.restaurantPrinterNew;
    if (list == null || index < 0 || index >= list.length) return null;
    return kotPrinter(list[index]);
  }
}
