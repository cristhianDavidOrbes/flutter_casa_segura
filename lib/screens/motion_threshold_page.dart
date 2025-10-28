import 'package:flutter/material.dart';

import 'package:flutter_seguridad_en_casa/services/motion_settings_service.dart';

class MotionThresholdPage extends StatefulWidget {
  const MotionThresholdPage({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  @override
  State<MotionThresholdPage> createState() => _MotionThresholdPageState();
}

class _MotionThresholdPageState extends State<MotionThresholdPage> {
  late double _thresholdCm;

  static const double _minCm = 10;
  static const double _maxCm = 300;

  @override
  void initState() {
    super.initState();
    _thresholdCm = MotionSettingsService.instance.thresholdFor(widget.deviceId);
  }

  Future<void> _save() async {
    await MotionSettingsService.instance
        .setThreshold(widget.deviceId, _thresholdCm);
    if (!mounted) return;
    Navigator.of(context).pop<double>(_thresholdCm);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Sensibilidad • ${widget.deviceName}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Distancia de alerta',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'El detector enviará una alerta cuando detecte un objeto más '
              'cerca que este umbral durante al menos 2 segundos. '
              'Valores negativos que provienen del sensor se ignoran '
              'automáticamente.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(
              '${_thresholdCm.toStringAsFixed(0)} cm',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            Slider(
              min: _minCm,
              max: _maxCm,
              divisions: (_maxCm - _minCm).toInt(),
              label: '${_thresholdCm.toStringAsFixed(0)} cm',
              value: _thresholdCm.clamp(_minCm, _maxCm),
              onChanged: (value) {
                setState(() {
                  _thresholdCm = value;
                });
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_alt),
              label: const Text('Guardar umbral'),
            ),
          ],
        ),
      ),
    );
  }
}
