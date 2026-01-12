import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Mahasiswa',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FB),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          margin: EdgeInsets.zero,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _nimController = TextEditingController();
  final _nameController = TextEditingController();
  MobileScannerController? _scannerController;

  List<Student> _students = [];
  bool _isLoading = true;
  bool _handlingBarcode = false;
  Student? _lastScannedStudent;
  String? _lastScanMessage;

  @override
  void initState() {
    super.initState();
    if (_isScannerSupported) {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
    _loadStudents();
  }

  @override
  void dispose() {
    _nimController.dispose();
    _nameController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  bool get _isScannerSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  Future<void> _loadStudents() async {
    setState(() => _isLoading = true);
    final students = await StudentDatabase.instance.getStudents();
    if (!mounted) return;
    setState(() {
      _students = students;
      _isLoading = false;
    });
  }

  Future<void> _saveStudent() async {
    final nim = _nimController.text.trim();
    final name = _nameController.text.trim();

    if (nim.isEmpty || name.isEmpty) {
      _showSnack('Isi NIM dan Nama terlebih dahulu.');
      return;
    }

    try {
      await StudentDatabase.instance.insertStudent(
        Student(nim: nim, name: name),
      );
      if (!mounted) return;
      _nimController.clear();
      _nameController.clear();
      _showSnack('Data mahasiswa tersimpan.');
      await _loadStudents();
    } catch (e) {
      _showSnack('Gagal menyimpan data: $e');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showQr(Student student) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'QR Code NIM',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Hero(
                  tag: 'qr-${student.nim}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4,
                        child: QrImageView(data: student.nim, size: 280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'NIM: ${student.nim}\nNama: ${student.name}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_handlingBarcode ||
        !_isScannerSupported ||
        _scannerController == null) {
      return;
    }

    Barcode? barcode;
    for (final item in capture.barcodes) {
      final value = item.rawValue;
      if (value != null && value.isNotEmpty) {
        barcode = item;
        break;
      }
    }

    final nim = barcode?.rawValue;
    if (nim == null || nim.isEmpty) return;

    setState(() => _handlingBarcode = true);
    await _scannerController?.stop();

    final student = await StudentDatabase.instance.getStudentByNim(nim);
    if (!mounted) return;

    final message = student != null
        ? 'NIM: ${student.nim}\nNama: ${student.name}'
        : 'NIM: $nim\nNama tidak ditemukan di database';

    setState(() {
      _lastScannedStudent = student;
      _lastScanMessage = message;
    });

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hasil Scan', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('Tutup'),
                ),
              ),
            ],
          ),
        );
      },
    );

    await _scannerController?.start();
    if (mounted) {
      setState(() => _handlingBarcode = false);
    }
  }

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.person_add_alt, size: 18),
                      SizedBox(width: 6),
                      Text('Tambah Mahasiswa'),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    _nimController.clear();
                    _nameController.clear();
                  },
                  tooltip: 'Reset',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nimController,
              decoration: const InputDecoration(labelText: 'NIM'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saveStudent,
                    icon: const Icon(Icons.save),
                    label: const Text('Simpan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentList() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_students.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: const [
            Icon(Icons.info_outline),
            SizedBox(height: 8),
            Text('Belum ada data mahasiswa.'),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _students.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final student = _students[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
              ),
            ),
            title: Text(student.name),
            subtitle: Text('NIM: ${student.nim}'),
            trailing: GestureDetector(
              onTap: () => _showQr(student),
              child: Hero(
                tag: 'qr-${student.nim}',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                  ),
                  child: QrImageView(data: student.nim, size: 56),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWebBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFormCard(),
          const SizedBox(height: 12),
          Text(
            'Daftar Mahasiswa',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_students.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: const [
                  Icon(Icons.info_outline),
                  SizedBox(height: 8),
                  Text('Belum ada data mahasiswa.'),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _students.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final student = _students[index];
                return Card(
                  child: ListTile(
                    title: Text(student.name),
                    subtitle: Text('NIM: ${student.nim}'),
                    trailing: QrImageView(data: student.nim, size: 72),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDataTab() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE4F2F1), Color(0xFFF4F6FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kelola Data Mahasiswa',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Simpan data, buat QR, dan scan di tab berikutnya.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              _buildFormCard(),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Daftar Mahasiswa',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.groups, size: 18),
                        const SizedBox(width: 6),
                        Text('${_students.length} data'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildStudentList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScannerTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Arahkan kamera ke QR Code untuk membaca NIM. Data akan dicocokkan dengan database lokal.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _isScannerSupported && _scannerController != null
                  ? Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0F766E), Color(0xFF115E59)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MobileScanner(
                            controller: _scannerController!,
                            onDetect: _handleBarcode,
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white70,
                                    width: 3,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                          if (_handlingBarcode)
                            Container(
                              color: Colors.black45,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Container(
                      color: Colors.grey.shade200,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Pemindaian kamera tidak didukung pada platform ini.\nGunakan perangkat mobile atau macOS.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hasil terakhir:',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  _lastScanMessage ?? 'Belum ada scan.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  _scannerController?.start();
                  setState(() {
                    _lastScannedStudent = null;
                  });
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Scan ulang'),
              ),
              const SizedBox(width: 12),
              if (_lastScannedStudent != null)
                OutlinedButton.icon(
                  onPressed: () => _showQr(_lastScannedStudent!),
                  icon: const Icon(Icons.qr_code_2),
                  label: const Text('Lihat QR'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR Mahasiswa (Web)')),
        body: _buildWebBody(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('QR Mahasiswa'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.storage), text: 'Data'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR'),
            ],
          ),
        ),
        body: TabBarView(children: [_buildDataTab(), _buildScannerTab()]),
      ),
    );
  }
}

class Student {
  Student({this.id, required this.nim, required this.name});

  final int? id;
  final String nim;
  final String name;

  Map<String, dynamic> toMap() {
    return {'id': id, 'nim': nim, 'name': name};
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as int?,
      nim: map['nim'] as String,
      name: map['name'] as String,
    );
  }
}

class StudentDatabase {
  StudentDatabase._();

  static final StudentDatabase instance = StudentDatabase._();
  Database? _database;
  bool _webInitialized = false;
  List<Student> _webStudents = [];
  SharedPreferences? _prefs;
  static const _webStorageKey = 'students_web';

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnimplementedError(
        'Database is not used on web; using SharedPreferences.',
      );
    }
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    _ensureDbFactoryInitialized();

    final documentsDir = await getApplicationDocumentsDirectory();
    final path = p.join(documentsDir.path, 'students.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE students(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nim TEXT UNIQUE,
            name TEXT
          )
        ''');
      },
    );
  }

  void _ensureDbFactoryInitialized() {
    if (kIsWeb) {
      return;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<List<Student>> getStudents() async {
    if (kIsWeb) {
      await _initWebStorage();
      return List.unmodifiable(_webStudents);
    }
    final db = await database;
    final rows = await db.query('students', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Student.fromMap).toList();
  }

  Future<Student?> getStudentByNim(String nim) async {
    if (kIsWeb) {
      await _initWebStorage();
      try {
        return _webStudents.firstWhere((s) => s.nim == nim);
      } catch (_) {
        return null;
      }
    }
    final db = await database;
    final rows = await db.query(
      'students',
      where: 'nim = ?',
      whereArgs: [nim],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return Student.fromMap(rows.first);
  }

  Future<int> insertStudent(Student student) async {
    if (kIsWeb) {
      await _initWebStorage();
      _webStudents.removeWhere((s) => s.nim == student.nim);
      final withId = Student(
        id: student.id ?? DateTime.now().microsecondsSinceEpoch,
        nim: student.nim,
        name: student.name,
      );
      _webStudents.add(withId);
      await _persistWebStudents();
      return withId.id ?? 0;
    }
    final db = await database;
    return db.insert(
      'students',
      student.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _initWebStorage() async {
    if (_webInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    final rawList = _prefs?.getStringList(_webStorageKey) ?? [];
    _webStudents = rawList
        .map((e) => Student.fromMap(json.decode(e) as Map<String, dynamic>))
        .toList();
    _webInitialized = true;
  }

  Future<void> _persistWebStudents() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final encoded = _webStudents.map((s) => json.encode(s.toMap())).toList();
    await prefs.setStringList(_webStorageKey, encoded);
  }
}
