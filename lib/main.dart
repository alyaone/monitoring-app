import 'dart:convert';
import 'dart:async';                            // <-- TAMBAHAN
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:http/http.dart' as http;       // <-- TAMBAHAN
import 'serial_config_page.dart';

void main() => runApp(const KontainerMonitorApp());

class KontainerMonitorApp extends StatelessWidget {
  const KontainerMonitorApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
  title: 'Monitoring Posisi Kontainer',
  debugShowCheckedModeBanner: false,
  theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepOrange),
  home: const DashboardPage(),
  routes: {
    '/serialConfig': (_) => const SerialConfigPage(),
  },
);

  }
}

/* ===================== Data model ===================== */
class Telemetry {
  String? timeUTC;
  int? packetCounter;
  double? lat, lon, alt, speed, snr;
  int? rssi, sats;
  bool? door;
  Telemetry();

  void mergeFromJson(Map<String, dynamic> j) {
    double? _d(k) {
      final v = j[k];
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    int? _i(k) {
      final v = j[k];
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    packetCounter ??= _i('packetCounter');
    lat  = _d('latitude')  ?? _d('lat')  ?? lat;
    lon  = _d('longitude') ?? _d('lon')  ?? lon;
    alt  = _d('altitude')  ?? alt;
    speed= _d('speed')     ?? speed;
    snr  = _d('snr')       ?? snr;
    rssi = _i('rssi')      ?? rssi;
    sats = _i('satellites')?? sats;
    timeUTC = (j['timeUTC']?.toString()) ?? timeUTC;

    final doorRaw = j['door'] ?? j['doorValue'] ?? j['doorStatus'];
    if (doorRaw != null) {
      if (doorRaw is bool) {
        door = doorRaw;
      } else if (doorRaw is num) {
        door = doorRaw != 0;
      } else {
        final s = doorRaw.toString().toLowerCase();
        if (['open','opened','true','1'].contains(s)) door = true;
        if (['close','closed','false','0'].contains(s)) door = false;
      }
    }
  }
}

class Kontainer {
  final String series;
  String tujuan;
  String isi;                      // <-- tetap
  String PT;
  Telemetry t = Telemetry();
  Kontainer({
    required this.series,
    required this.tujuan,
    this.isi = '-',
    required this.PT,
  });
}

/* ===================== Page ===================== */
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  // ---- MQTT config (tetap) ----
  final String brokerHost = '172.20.10.5';
  final int brokerPort = 1883;
  final String baseTopic = 'supplychain/containers'; // subscribe "baseTopic/#"

  MqttServerClient? _client;
  bool _connected = false;

  // daftar kontainer (key = series)
  final Map<String, Kontainer> _items = {};

  // query pencarian
  String _searchQuery = '';

  // ---- InfluxDB config (TAMBAHAN) ----
  final String influxBaseUrl = 'http://127.20.10.5:8086';
  final String influxOrg     = 'my-org';
  final String influxBucket  = 'smart-ecoport';
  final String influxToken   = 'my-super-token';
  final Duration influxPollEvery = const Duration(seconds: 5);
  final String influxRange = '-24h'; // ambil 10 menit terakhir
  Timer? _influxTimer;

  @override
  void initState() {
    super.initState();
    _connectMqtt();            // (tetap) MQTT
    _startInfluxPolling();     // (TAMBAHAN) polling Influx
  }

  @override
  void dispose() {
    _influxTimer?.cancel();    // (TAMBAHAN)
    super.dispose();
  }

  Future<void> _connectMqtt() async {
    try {
  final testResp = await http.get(Uri.parse('http://172.20.10.5:8086/health'));
  debugPrint('Influx health check: ${testResp.statusCode} → ${testResp.body}');
} catch (e) {
  debugPrint('Influx health check error: $e');
}

    final id = 'kontainer_monitor_${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient(brokerHost, id)
      ..port = brokerPort
      ..keepAlivePeriod = 30
      ..logging(on: false)
      ..onDisconnected = () => setState(() => _connected = false);

    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(id)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    try {
      await c.connect();
      c.subscribe('$baseTopic/#', MqttQos.atLeastOnce); // wildcard
      c.updates?.listen((events) {
        final msg = events.first;
        final rec = msg.payload as MqttPublishMessage;
        final topic = msg.topic;
        final payload =
            MqttPublishPayload.bytesToStringAsString(rec.payload.message);
        _handleMessage(topic, payload);
      });
      setState(() {
        _client = c;
        _connected = true;
      });
    } catch (e) {
      c.disconnect();
      if (mounted) {
        setState(() => _connected = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('MQTT error: $e')));
      }
    }
  }

  // Ambil SERIES dari topic .../<series> ATAU dari JSON: series/containerId
  String? _extractSeries(String topic, Map<String, dynamic> j) {
    final fromJson = (j['series'] ?? j['containerId'])?.toString();
    if (fromJson != null && fromJson.isNotEmpty) return fromJson;
    if (topic.startsWith(baseTopic)) {
      final parts = topic.split('/');
      if (parts.length >= 3) return parts.last; // baseTopic/<series>
    }
    return null;
  }

  void _handleMessage(String topic, String payload) {
    try {
      final j = jsonDecode(payload) as Map<String, dynamic>;
      final series = _extractSeries(topic, j);
      if (series == null) return;

      setState(() {
        final item = _items.putIfAbsent(
          series,
          () => Kontainer(series: series, tujuan: '-', isi: '-', PT: '-'),
        );
        item.t.mergeFromJson(j);
      });
    } catch (_) {
      // ignore invalid JSON
    }
  }

  void _addContainerDialog() {
    final seriesCtrl = TextEditingController();
    final tujuanCtrl = TextEditingController();
    final isiCtrl = TextEditingController();
    final PTCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: seriesCtrl,
              decoration: const InputDecoration(
                labelText: 'Series (XX4028)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tujuanCtrl,
              decoration: const InputDecoration(
                labelText: 'Tujuan (Semarang-Makassar)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: isiCtrl,
              decoration: const InputDecoration(
                labelText: 'Isi (Pakaian, Elektronik, dll.)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: PTCtrl,
              decoration: const InputDecoration(
                labelText: 'Perusahaan',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final s = seriesCtrl.text.trim();
              final t = tujuanCtrl.text.trim();
              final i = isiCtrl.text.trim();
              final p = PTCtrl.text.trim();
              if (s.isNotEmpty) {
                setState(() {
                  _items.putIfAbsent(
                    s,
                    () => Kontainer(
                      series: s,
                      tujuan: t.isEmpty ? '-' : t,
                      isi: i.isEmpty ? '-' : i,
                      PT: p.isEmpty ? '-' : i,  // (biarkan sesuai kode asalmu)
                    ),
                  )
                  ..tujuan = t.isEmpty ? '-' : t
                  ..isi    = i.isEmpty ? '-' : i
                  ..PT    = p.isEmpty ? '-' : p;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String series) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Kontainer'),
        content: Text('Yakin hapus "$series"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _items.remove(series));
    }
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6A2A);

    // filter berdasar pencarian
    final filteredItems = _items.values
        .where((k) => k.series.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
  appBar: PreferredSize(
    preferredSize: const Size.fromHeight(120),
    child: Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16),
      child: Stack(
        children: [
          // Tombol menu di pojok kiri atas
Positioned(
  top: 6,
  left: 0,
  child: Builder(
    builder: (ctx) => IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu, size: 28),
      onPressed: () => Scaffold.of(ctx).openDrawer(),
    ),
  ),
),

          // Logo + judul di tengah
          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: const [
                Image(image: AssetImage('assets/LogoBRIN.png'), height: 42),
                SizedBox(height: 6),
                Text(
                  'Monitoring Posisi Kontainer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: .3,
                  ),
                ),
              ],
            ),
          ),
          // 🔍 Search bar kecil di pojok kanan atas
          Positioned(
            top: 10,
            right: 0,
            child: SizedBox(
              width: 150,
              height: 36,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Cari series...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),

  // ✅ Tambahkan Drawer di sini
  drawer: Drawer(
    child: SafeArea(
      child: ListView(
        children: [
          const DrawerHeader(
            child: Text(
              'Selamat Datang!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pop(context), // tutup drawer
          ),
          ListTile(
            leading: const Icon(Icons.usb),
            title: const Text('GUI Transmitter'),
            subtitle: const Text('Kirim JSON ke ESP32'),
            onTap: () {
              Navigator.pop(context); // tutup drawer
              Navigator.pushNamed(context, '/serialConfig'); // buka halaman baru
            },
          ),
        ],
      ),
    ),
  ),

  // ====== sisanya tetap ======
  body: SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: filteredItems.isEmpty
          ? const Center(
              child: Text('Belum ada kontainer. Tekan tombol + untuk menambah.'),
            )
          : ListView.separated(
              itemCount: filteredItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final k = filteredItems[i];
                return _ContainerCard(
                  data: k,
                  borderColor: orange,
                  onDelete: () => _confirmDelete(k.series),
                  compact: true, // ringkas (2 baris)
                );
              },
            ),
    ),
  ),

  floatingActionButton: FloatingActionButton(
    onPressed: _addContainerDialog,
    child: const Icon(Icons.add),
  ),

  bottomNavigationBar: Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    child: FilledButton.icon(
      onPressed: _connected ? null : _connectMqtt,
      icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
      label: const Text('Reconnect MQTT'),
    ),
  ),
);

  }

  /* ===================== Tambahan: Polling InfluxDB ===================== */

  void _startInfluxPolling() {
    _pullFromInflux(); // jalankan sekali
    _influxTimer?.cancel();
    _influxTimer = Timer.periodic(influxPollEvery, (_) => _pullFromInflux());
  }

  Future<void> _pullFromInflux() async {
  final uri = Uri.parse('$influxBaseUrl/api/v2/query?org=$influxOrg');

  // Ambil record terakhir per device, pivot jadi lebar
  final flux = '''
base = from(bucket: "$influxBucket")
  |> range(start: $influxRange)
  |> filter(fn: (r) => r._measurement == "telemetry")
  |> filter(fn: (r) => r._field =~ /^(lat|lon|alt|speed|rssi|snr|sats|door|packetCounter)\$/)

// Ambil NILAI TERAKHIR per device & per field (ini memisahkan tiap tipe dulu)
lasts = base
  |> group(columns: ["device", "_field"])
  |> last()

// Normalisasi tipe:
// - door: bool -> 0.0 / 1.0
// - selain door: paksa ke float (termasuk integer)
norm = lasts
  |> map(fn: (r) => ({
      r with _value:
        if r._field == "door"
          then (if bool(v: r._value) then 1.0 else 0.0)
          else float(v: r._value)
    }))

// Setelah semua jadi float, baru pivot
norm
  |> group(columns: ["device"])
  |> pivot(rowKey:["_time"], columnKey: ["_field"], valueColumn: "_value")
  |> keep(columns: ["device","_time","lat","lon","alt","speed","rssi","snr","sats","door","packetCounter"])
''';



  try {
    final resp = await http.post(
      uri,
      headers: {
        'Authorization': 'Token $influxToken',
        'Accept': 'application/csv',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'type': 'flux',
        'query': flux,
        'dialect': {
          'header': true,
          'annotations': ['datatype', 'group', 'default'],
          'delimiter': ',',
        },
      }),
    );

    // 👇 Tambahkan tiga baris debug di sini:
    debugPrint('INFLUX URL = $influxBaseUrl');
    debugPrint('HTTP ${resp.statusCode}');
    debugPrint(resp.body.split('\n').take(6).join('\n'));
    // 👆 Baris ini akan tampil di Output/Console untuk memeriksa koneksi dan hasil query.

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      _applyInfluxCsv(resp.body);
    } else {
      // diamkan agar tidak spam UI
      // debugPrint('Influx query error ${resp.statusCode}: ${resp.body}');
    }
  } catch (e) {
    // jaringan putus, dll. biarkan polling berikutnya coba lagi
    debugPrint('Influx query exception: $e'); // 👈 boleh aktifkan juga baris ini
  }
}

  void _applyInfluxCsv(String csv) {
    final lines = const LineSplitter().convert(csv);
    if (lines.isEmpty) return;

    // cari header kolom terakhir
    int headerIdx = -1;
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.isEmpty || l.startsWith('#')) continue;
      if (l.contains('device') && l.contains('_time')) headerIdx = i;
    }
    if (headerIdx == -1 || headerIdx + 1 >= lines.length) return;

    final header = lines[headerIdx].split(',');
    int idxOf(String name) => header.indexOf(name);

    final iDevice = idxOf('device');
    final iTime   = idxOf('_time');
    final iLat    = idxOf('lat');
    final iLon    = idxOf('lon');
    final iAlt    = idxOf('alt');
    final iSpd    = idxOf('speed');
    final iRssi   = idxOf('rssi');
    final iSnr    = idxOf('snr');
    final iSats   = idxOf('sats');
    final iDoor   = idxOf('door');
    final iPkt    = idxOf('packetCounter');

    if ([iDevice, iTime].any((i) => i < 0)) return;

    final Map<String, Telemetry> latest = {};

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final l = lines[i];
      if (l.isEmpty || l.startsWith('#')) continue;
      final cols = _splitCsvLine(l, header.length);
      if (cols.length < header.length) continue;

      final dev = cols[iDevice];
      if (dev.isEmpty) continue;

      double? _toD(String s) => double.tryParse(s);
      int?    _toI(String s) => int.tryParse(s);
      bool?   _toB(String s) {
        final ls = s.toLowerCase();
        if (ls == 'true') return true;
        if (ls == 'false') return false;
        final n = int.tryParse(ls);
        if (n != null) return n != 0;
        return null;
      }

      final t = Telemetry();
      t.timeUTC       = iTime >= 0 ? cols[iTime] : null;
      t.lat           = iLat  >= 0 ? _toD(cols[iLat])   : null;
      t.lon           = iLon  >= 0 ? _toD(cols[iLon])   : null;
      t.alt           = iAlt  >= 0 ? _toD(cols[iAlt])   : null;
      t.speed         = iSpd  >= 0 ? _toD(cols[iSpd])   : null;
      t.rssi          = iRssi >= 0 ? _toI(cols[iRssi])  : null;
      t.snr           = iSnr  >= 0 ? _toD(cols[iSnr])   : null;
      t.sats          = iSats >= 0 ? _toI(cols[iSats])  : null;
      t.door          = iDoor >= 0 ? _toB(cols[iDoor])  : null;
      t.packetCounter = iPkt  >= 0 ? _toI(cols[iPkt])   : null;

      latest[dev] = t; // last() per device
    }

    if (latest.isEmpty) return;

    // merge ke state tanpa mengubah algoritma list/card
    setState(() {
      latest.forEach((series, tel) {
        final item = _items.putIfAbsent(
          series,
          () => Kontainer(series: series, tujuan: '-', isi: '-', PT: '-'),
        );
        final j = <String, dynamic>{
          'packetCounter': tel.packetCounter,
          'lat': tel.lat,
          'lon': tel.lon,
          'altitude': tel.alt,
          'speed': tel.speed,
          'rssi': tel.rssi,
          'snr': tel.snr,
          'satellites': tel.sats,
          'timeUTC': tel.timeUTC,
          'door': tel.door,
        }..removeWhere((k, v) => v == null);
        item.t.mergeFromJson(j);
      });
    });
  }

  // parser CSV sederhana yang handle quotes
  List<String> _splitCsvLine(String line, int expected) {
    final List<String> out = [];
    final sb = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"'); i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        out.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString());
    while (out.length < expected) out.add('');
    return out;
  }
}

/* ===================== One container card ===================== */
class _ContainerCard extends StatelessWidget {
  final Kontainer data;
  final Color borderColor;
  final VoidCallback? onDelete; // tombol hapus
  final bool compact; // tampilkan 2 baris saja
  const _ContainerCard({
    required this.data,
    required this.borderColor,
    this.onDelete,
    this.compact = false,
  });

  String _s(dynamic v, {int f = 6}) {
    if (v == null) return '-';
    if (v is num) return (v is int) ? '$v' : v.toStringAsFixed(f);
    return v.toString();
  }

  @override
  Widget build(BuildContext context) {
    final t = data.t;

    // Line 1: Series | Tujuan | Isi | Waktu
    final line1 =
        'Series: ${data.series}  |  Tujuan: ${data.tujuan}  |  Isi: ${data.isi}  |  Perusahaan: ${data.PT}';

    // Line 2: Paket & statistik
    final line2 =
        '${t.timeUTC ?? '-'} | Paket: ${t.packetCounter ?? '-'}  | Lat: ${_s(t.lat)} | Long: ${_s(t.lon)} | Alt: ${_s(t.alt)} | Spd: ${_s(t.speed)} | Door: ${t.door == null ? '-' : (t.door! ? 'OPEN' : 'CLOSED')} | RSSI: ${_s(t.rssi)} | SNR: ${_s(t.snr)} | SAT: ${_s(t.sats)}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 2.0),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            // garis pembatas atas
            Container(height: 2, color: borderColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Isi 2 baris ringkas
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey[800],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Tombol hapus (opsional)
                  if (onDelete != null)
                    IconButton(
                      tooltip: 'Hapus kontainer',
                      icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                      onPressed: onDelete,
                    ),
                ],
              ),
            ),
            // garis pembatas bawah
            Container(height: 2, color: borderColor),
          ],
        ),
      ),
    );
  }
}
