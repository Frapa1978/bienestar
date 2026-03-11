import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'supabase_config.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const BienestarApp());
}

class BienestarApp extends StatelessWidget {
  const BienestarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bienestar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final authState = snapshot.data;
        final event = authState?.event;

        if (event == AuthChangeEvent.signedIn ||
            Supabase.instance.client.auth.currentUser != null) {
          return const HomePage();
        }

        if (event == AuthChangeEvent.signedOut || session == null) {
          return const AuthPage();
        }

        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = Supabase.instance.client.auth;

    try {
      if (_isLogin) {
        await auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      } else {
        await auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Error inesperado');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _isLogin ? 'Iniciar sesión' : 'Crear cuenta';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Bienestar',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa tu email';
                      }
                      if (!value.contains('@')) {
                        return 'Email no válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Contraseña',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Ingresa tu contraseña';
                      }
                      if (value.length < 6) {
                        return 'Mínimo 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(title),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _error = null;
                      });
                    },
                    child: Text(
                      _isLogin
                          ? 'Crear una nueva cuenta'
                          : 'Ya tengo cuenta, iniciar sesión',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();

  DateTime _dateTime = DateTime.now();
  final _systolicCtrl = TextEditingController();
  final _diastolicCtrl = TextEditingController();
  final _pulseCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  bool _saving = false;
  String? _error;

  DateTime? _filterFrom;
  DateTime? _filterTo;

  late Future<List<Map<String, dynamic>>> _futureMeasurements;

  @override
  void initState() {
    super.initState();
    _futureMeasurements = _fetchMeasurements();
  }

  @override
  void dispose() {
    _systolicCtrl.dispose();
    _diastolicCtrl.dispose();
    _pulseCtrl.dispose();
    _weightCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchMeasurements() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return [];

    final supabase = Supabase.instance.client;

    try {
      var query =
          supabase.from('measurements').select('*').eq('user_id', user.id);

      if (_filterFrom != null) {
        final fromIso = DateTime(
          _filterFrom!.year,
          _filterFrom!.month,
          _filterFrom!.day,
          0,
          0,
        ).toIso8601String();
        query = query.gte('timestamp', fromIso);
      }

      if (_filterTo != null) {
        final toIso = DateTime(
          _filterTo!.year,
          _filterTo!.month,
          _filterTo!.day,
          23,
          59,
          59,
        ).toIso8601String();
        query = query.lte('timestamp', toIso);
      }

      final data = await query.order('timestamp', ascending: false);
      return (data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _refreshList() async {
    final newFuture = _fetchMeasurements();
    setState(() {
      _futureMeasurements = newFuture;
    });
    await newFuture;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (time == null) return;

    setState(() {
      _dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  bool _hasAnyNumericValue() {
    return _systolicCtrl.text.trim().isNotEmpty ||
        _diastolicCtrl.text.trim().isNotEmpty ||
        _pulseCtrl.text.trim().isNotEmpty ||
        _weightCtrl.text.trim().isNotEmpty;
  }

  Future<void> _saveMeasurement() async {
    if (!_hasAnyNumericValue()) {
      setState(() {
        _error = 'Ingresa al menos un dato numérico (presión, pulso o peso).';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() {
        _saving = false;
        _error = 'Sesión no válida. Vuelve a iniciar sesión.';
      });
      return;
    }

    final supabase = Supabase.instance.client;

    int? parseInt(String text) =>
        text.trim().isEmpty ? null : int.tryParse(text.trim());
    double? parseDouble(String text) => text.trim().isEmpty
        ? null
        : double.tryParse(text.trim().replaceAll(',', '.'));

    try {
      await supabase.from('measurements').insert({
        'user_id': user.id,
        'timestamp': _dateTime.toIso8601String(),
        'systolic': parseInt(_systolicCtrl.text),
        'diastolic': parseInt(_diastolicCtrl.text),
        'pulse': parseInt(_pulseCtrl.text),
        'weight': parseDouble(_weightCtrl.text),
        'comment':
            _commentCtrl.text.trim().isEmpty ? null : _commentCtrl.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro guardado')),
      );

      setState(() {
        _systolicCtrl.clear();
        _diastolicCtrl.clear();
        _pulseCtrl.clear();
        _weightCtrl.clear();
        _commentCtrl.clear();
        _dateTime = DateTime.now();
      });

      await _refreshList();
    } catch (_) {
      setState(() {
        _error = 'Error al guardar el registro';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _pickFilterFrom() async {
    final initial = _filterFrom ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _filterFrom = picked;
    });
    await _refreshList();
  }

  Future<void> _pickFilterTo() async {
    final initial = _filterTo ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      _filterTo = picked;
    });
    await _refreshList();
  }

  void _clearFilters() {
    setState(() {
      _filterFrom = null;
      _filterTo = null;
    });
    _refreshList();
  }

  String _formatFilterDate(DateTime? date) {
    if (date == null) return 'Todas';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<FlSpot> _buildSystolicSpots(List<Map<String, dynamic>> data) {
    final reversed = data.reversed.toList();
    final spots = <FlSpot>[];
    for (var i = 0; i < reversed.length; i++) {
      final row = reversed[i];
      final value = row['systolic'];
      if (value == null) continue;
      spots.add(FlSpot(i.toDouble(), (value as num).toDouble()));
    }
    return spots;
  }

  List<FlSpot> _buildDiastolicSpots(List<Map<String, dynamic>> data) {
    final reversed = data.reversed.toList();
    final spots = <FlSpot>[];
    for (var i = 0; i < reversed.length; i++) {
      final row = reversed[i];
      final value = row['diastolic'];
      if (value == null) continue;
      spots.add(FlSpot(i.toDouble(), (value as num).toDouble()));
    }
    return spots;
  }

  List<FlSpot> _buildWeightSpots(List<Map<String, dynamic>> data) {
    final reversed = data.reversed.toList();
    final spots = <FlSpot>[];
    for (var i = 0; i < reversed.length; i++) {
      final row = reversed[i];
      final value = row['weight'];
      if (value == null) continue;
      spots.add(FlSpot(i.toDouble(), (value as num).toDouble()));
    }
    return spots;
  }

  Future<void> _exportAndShareCsv() async {
    try {
      final data = await _fetchMeasurements();
      if (data.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay registros en este rango.')),
        );
        return;
      }

      final rows = <List<dynamic>>[];
      rows.add([
        'FechaHora',
        'Sistólica',
        'Diastólica',
        'Pulso',
        'Peso',
        'Comentario',
      ]);

      for (final row in data) {
        final date = DateTime.tryParse(row['timestamp']?.toString() ?? '');
        final dateStr = date == null
            ? ''
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
              '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

        rows.add([
          dateStr,
          row['systolic'] ?? '',
          row['diastolic'] ?? '',
          row['pulse'] ?? '',
          row['weight'] ?? '',
          row['comment'] ?? '',
        ]);
      }

      final csvString = const ListToCsvConverter().convert(rows); 

      final dir = await getTemporaryDirectory(); 

      String _formatShort(DateTime? d) =>
          d == null ? '' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final fromStr = _formatShort(_filterFrom);
      final toStr = _formatShort(_filterTo);

      String rangePart;
      if (fromStr.isEmpty && toStr.isEmpty) {
        rangePart = 'completo';
      } else if (fromStr.isNotEmpty && toStr.isNotEmpty) {
        rangePart = '${fromStr}_$toStr';
      } else if (fromStr.isNotEmpty) {
        rangePart = 'desde_$fromStr';
      } else {
        rangePart = 'hasta_$toStr';
      }

      final safeRange = rangePart.replaceAll(' ', '_');
      final fileName = 'registros_presion_$safeRange.csv';

      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csvString);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Registros de presión arterial ($rangePart)',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al exportar CSV: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bienestar - Registros'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Row(
            children: [
              // Columna izquierda: formulario
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Hola ${user?.email}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nuevo registro',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _pickDateTime,
                          icon: const Icon(Icons.calendar_today),
                          label: Text(
                            'Fecha y hora: ${_dateTime.toString().substring(0, 16)}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _systolicCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Sistólica (alta)',
                                  hintText: 'Ej: 120',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _diastolicCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Diastólica (baja)',
                                  hintText: 'Ej: 80',
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pulseCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Pulso (lpm)',
                            hintText: 'Ej: 70',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _weightCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Peso (kg)',
                            hintText: 'Ej: 82.5',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _commentCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Comentario (opcional)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _saveMeasurement,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save),
                          label: Text(
                            _saving ? 'Guardando...' : 'Guardar registro',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const VerticalDivider(width: 1),

              // Columna derecha: filtros, gráficas, listado
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickFilterFrom,
                              child: Text(
                                'Desde: ${_formatFilterDate(_filterFrom)}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _pickFilterTo,
                              child: Text(
                                'Hasta: ${_formatFilterDate(_filterTo)}',
                              ),
                            ),
                          ),
                          IconButton(
  tooltip: kIsWeb ? 'Exportar solo desde el móvil' : 'Exportar CSV',
  icon: const Icon(Icons.download),
  onPressed: kIsWeb ? null : _exportAndShareCsv,
),
                          TextButton(
                            onPressed: _clearFilters,
                            child: const Text('Limpiar'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshList,
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: _futureMeasurements,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Error al cargar registros',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              );
                            }

                            final data = snapshot.data ?? [];

                            if (data.isEmpty) {
                              return const Center(
                                child: Text('Sin registros para este rango'),
                              );
                            }

                            final systolicSpots = _buildSystolicSpots(data);
                            final diastolicSpots = _buildDiastolicSpots(data);
                            final weightSpots = _buildWeightSpots(data);

                            return ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                // Gráfica presión
                                SizedBox(
                                  height: 220,
                                  child: Card(
                                    margin:
                                        const EdgeInsets.only(bottom: 16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Presión arterial',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Expanded(
                                            child: LineChart(
                                              LineChartData(
                                                minY: 60,
                                                maxY: 180,
                                                gridData:
                                                    FlGridData(show: true),
                                                titlesData: FlTitlesData(
                                                  leftTitles: AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: true,
                                                      reservedSize: 36,
                                                    ),
                                                  ),
                                                  bottomTitles:
                                                      const AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: false,
                                                    ),
                                                  ),
                                                  topTitles:
                                                      const AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: false,
                                                    ),
                                                  ),
                                                  rightTitles:
                                                      const AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: false,
                                                    ),
                                                  ),
                                                ),
                                                extraLinesData: ExtraLinesData(
                                                  horizontalLines: [
                                                    HorizontalLine(
                                                      y: 120,
                                                      color: Colors.green
                                                          .withValues(
                                                              alpha: 0.6),
                                                      strokeWidth: 1,
                                                      dashArray: [8, 4],
                                                    ),
                                                    HorizontalLine(
                                                      y: 80,
                                                      color: Colors.green
                                                          .withValues(
                                                              alpha: 0.6),
                                                      strokeWidth: 1,
                                                      dashArray: [8, 4],
                                                    ),
                                                  ],
                                                ),
                                                lineBarsData: [
                                                  LineChartBarData(
                                                    spots: systolicSpots,
                                                    isCurved: true,
                                                    color: Colors.redAccent,
                                                    barWidth: 2,
                                                    dotData: FlDotData(
                                                      show: false,
                                                    ),
                                                  ),
                                                  LineChartBarData(
                                                    spots: diastolicSpots,
                                                    isCurved: true,
                                                    color: Colors.blue,
                                                    barWidth: 2,
                                                    dotData: FlDotData(
                                                      show: false,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: const [
                                              Icon(
                                                Icons.show_chart,
                                                size: 12,
                                                color: Colors.redAccent,
                                              ),
                                              SizedBox(width: 4),
                                              Text('Sistólica'),
                                              SizedBox(width: 16),
                                              Icon(
                                                Icons.show_chart,
                                                size: 12,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(width: 4),
                                              Text('Diastólica'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                // Gráfica peso
                                SizedBox(
                                  height: 220,
                                  child: Card(
                                    margin:
                                        const EdgeInsets.only(bottom: 16),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Peso',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 8),
                                          Expanded(
                                            child: LineChart(
                                              LineChartData(
                                                minY: 90,
                                                maxY: 110,
                                                gridData:
                                                    FlGridData(show: true),
                                                titlesData: FlTitlesData(
                                                  leftTitles: AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: true,
                                                      reservedSize: 36,
                                                    ),
                                                  ),
                                                  bottomTitles:
                                                      const AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: false,
                                                    ),
                                                  ),
                                                  topTitles:
                                                      const AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: false,
                                                    ),
                                                  ),
                                                  rightTitles:
                                                      const AxisTitles(
                                                    sideTitles: SideTitles(
                                                      showTitles: false,
                                                    ),
                                                  ),
                                                ),
                                                lineBarsData: [
                                                  LineChartBarData(
                                                    spots: weightSpots,
                                                    isCurved: true,
                                                    color: Colors.green,
                                                    barWidth: 2,
                                                    dotData: FlDotData(
                                                      show: false,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ...data.map((row) {
                                  final date = DateTime.tryParse(
                                    row['timestamp']?.toString() ?? '',
                                  );
                                  final systolic = row['systolic'];
                                  final diastolic = row['diastolic'];
                                  final pulse = row['pulse'];
                                  final weight = row['weight'];
                                  final comment = row['comment'];

                                  final dateStr = date == null
                                      ? ''
                                      : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                                          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                                  final pressureStr =
                                      (systolic != null && diastolic != null)
                                          ? '$systolic/$diastolic mmHg'
                                          : (systolic ?? diastolic) != null
                                              ? '${systolic ?? diastolic} mmHg'
                                              : '-';

                                  final pulseStr =
                                      pulse != null ? '$pulse lpm' : '-';
                                  final weightStr =
                                      weight != null ? '$weight kg' : '-';

                                  return Card(
                                    child: ListTile(
                                      title: Text(dateStr),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Presión: $pressureStr'),
                                          Text('Pulso: $pulseStr'),
                                          Text('Peso: $weightStr'),
                                          if (comment != null &&
                                              comment.toString().isNotEmpty)
                                            Text('Nota: $comment'),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
