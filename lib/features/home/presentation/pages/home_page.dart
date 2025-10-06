// lib/features/home/presentation/pages/home_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:flutter_seguridad_en_casa/core/presentation/widgets/theme_toggle_button.dart';
import 'package:flutter_seguridad_en_casa/core/state/circle_state.dart';
import 'package:flutter_seguridad_en_casa/features/auth/domain/entities/auth_user.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/controllers/auth_controller.dart';
import 'package:flutter_seguridad_en_casa/features/auth/presentation/pages/login_screen.dart';

import 'package:flutter_seguridad_en_casa/data/local/app_db.dart';
import 'package:flutter_seguridad_en_casa/screens/devices_page.dart';
import 'package:flutter_seguridad_en_casa/screens/provisioning_screen.dart';
import 'package:flutter_seguridad_en_casa/screens/device_detail_page.dart';
import 'package:flutter_seguridad_en_casa/services/lan_discovery_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.circleNotifier});
  final CircleStateNotifier circleNotifier;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AuthController _auth = Get.find<AuthController>();

  // ---- Estado / datos locales ----
  List<FamilyMember> _family = const [];
  List<Device> _devices = const [];
  bool _loading = true;

  /// IDs que están “online” según mDNS (refrescado periódico).
  /// Se intentará mapear por `device_id`, luego por `host`, y por IP.
  final Set<String> _onlineKeys = <String>{};
  Timer? _lanTimer;

  final _pageCtrl = PageController(viewportFraction: 0.55);
  double _page = 0;

  AuthUser? get _user => _auth.currentUser.value;

  @override
  void initState() {
    super.initState();
    _pageCtrl.addListener(() => setState(() => _page = _pageCtrl.page ?? 0));
    _refresh();
    _startLanPolling();
  }

  @override
  void dispose() {
    _lanTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ============== CARGA DE DATOS ==============

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final db = AppDb.instance;

      // 1) Familia desde SQLite local
      final famRows = await (await db.database).query(FamilyMember.tableName);

      // 2) Dispositivos registrados (DB local). Esto asegura que
      //    SIEMPRE mostramos los registrados —aunque estén desconectados—.
      final devsLocal = await db.fetchAllDevices();

      setState(() {
        _family = famRows.map(FamilyMember.fromMap).toList();
        _devices = devsLocal;
      });

      // 3) Descubrimiento rápido en LAN para marcar conectados (no bloqueante)
      unawaited(_refreshLanOnlineOnce());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startLanPolling() {
    // Hace un barrido por la red local cada 7s para actualizar estado online
    _lanTimer?.cancel();
    _lanTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _refreshLanOnlineOnce();
    });
  }

  Future<void> _refreshLanOnlineOnce() async {
    try {
      final discovery = LanDiscoveryService();
      final found = await discovery.discover(
        timeout: const Duration(seconds: 4),
      );

      // Convertimos los resultados en claves comparables con nuestros registros.
      final keys = <String>{};
      for (final d in found) {
        if (d.deviceId != null && d.deviceId!.trim().isNotEmpty) {
          keys.add('id:${d.deviceId!.trim().toLowerCase()}');
        }
        if (d.host != null && d.host!.trim().isNotEmpty) {
          keys.add('host:${d.host!.trim().toLowerCase()}');
        }
        if (d.ip.trim().isNotEmpty) {
          keys.add('ip:${d.ip.trim()}');
        }
      }

      if (!mounted) return;
      setState(() {
        _onlineKeys
          ..clear()
          ..addAll(keys);
      });
    } catch (_) {
      // Silencioso: si falla el mDNS, no queremos romper la Home
    }
  }

  bool _isOnline(Device d) {
    // Regla: si coincide cualquier clave, lo damos por “online”
    final deviceId = d.deviceId.trim().toLowerCase();
    final host = (d.name.isNotEmpty ? d.name : (d.ip ?? ''))
        .trim(); // por si usas name como host
    final ip = (d.ip ?? '').trim();

    if (deviceId.isNotEmpty && _onlineKeys.contains('id:$deviceId')) {
      return true;
    }
    if (host.isNotEmpty && _onlineKeys.contains('host:${host.toLowerCase()}')) {
      return true;
    }
    if (ip.isNotEmpty && _onlineKeys.contains('ip:$ip')) {
      return true;
    }

    // Fallback adicional con `lastSeenAt` (si hace <= 8s, lo contamos online)
    if (d.lastSeenAt != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(d.lastSeenAt!);
      if (DateTime.now().difference(dt) <= const Duration(seconds: 8)) {
        return true;
      }
    }
    return false;
  }

  // ============== ACCIONES ==============

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Get.offAll(() => LoginScreen(circleNotifier: widget.circleNotifier));
  }

  void _goToDevices() => Get.to(() => const DevicesPage());
  void _goToProvisioning() => Get.to(() => const ProvisioningScreen());

  // ============== UI ==============

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inicio'),
        actions: const [
          // ÚNICO botón de tema en la pantalla
          ThemeToggleButton(),
        ],
        leading: IconButton(
          tooltip: 'Cerrar sesión',
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  // —— Avatar del usuario grande y centrado ——
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Center(
                        child: CircleAvatar(
                          radius: 48,
                          backgroundColor: cs.primaryContainer,
                          child: Text(
                            _initials(_user),
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // —— Sección Familia (carrusel con foco central) ——
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.family_restroom, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Familia',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          if (_family.isNotEmpty)
                            Text(
                              '${_family.length}',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 150,
                      child: _family.isEmpty
                          ? _EmptyInline(
                              icon: Icons.person_add_alt_1,
                              title: 'Sin familiares',
                              actionText: 'Añadir',
                              onAction: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Pantalla de familia pendiente.',
                                    ),
                                  ),
                                );
                              },
                            )
                          : PageView.builder(
                              controller: _pageCtrl,
                              itemCount: _family.length,
                              padEnds: true,
                              itemBuilder: (ctx, i) {
                                final t = (i - _page).abs().clamp(0, 1);
                                final scale = 1 - (0.16 * t);
                                final opacity = 1 - (0.55 * t);
                                return Center(
                                  child: AnimatedScale(
                                    scale: scale,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                    child: AnimatedOpacity(
                                      opacity: opacity,
                                      duration: const Duration(
                                        milliseconds: 250,
                                      ),
                                      child: _FamilyCard(member: _family[i]),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),

                  // —— Sección Dispositivos registrados (DB) + estado LAN (mDNS) ——
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Row(
                        children: [
                          Icon(Icons.devices_other, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Dispositivos',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _goToDevices,
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Ver todos'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_devices.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: _EmptyInline(
                          icon: Icons.link_off,
                          title: 'Sin dispositivos registrados',
                          actionText: 'Provisionar',
                          onAction: _goToProvisioning,
                        ),
                      ),
                    )
                  else
                    SliverList.separated(
                      itemCount: _devices.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (ctx, i) {
                        final d = _devices[i];
                        final online = _isOnline(d);
                        return _DevicePill(
                          name: d.name,
                          subtitle:
                              '${d.ip?.isNotEmpty == true ? d.ip : "—"} • ${d.type.toLowerCase()}',
                          online: online,
                          onTap: () {
                            Get.to(
                              () => DeviceDetailPage(
                                deviceId: d.deviceId,
                                name: d.name,
                                type: d.type,
                                ip: d.ip,
                                lastSeenAt: d.lastSeenAt != null
                                    ? DateTime.fromMillisecondsSinceEpoch(
                                        d.lastSeenAt!,
                                      )
                                    : null,
                              ),
                            );
                          },
                        );
                      },
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
      // Barra inferior simple (sin botón extra de “agregar”, ya está en otra pantalla)
      bottomNavigationBar: _BottomNav(
        onHelp: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Centro de ayuda (pendiente).')),
          );
        },
        onFamily: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pantalla de familia (pendiente).')),
          );
        },
        onHome: () {},
        onDevices: _goToDevices,
      ),
    );
  }

  String _initials(AuthUser? u) {
    final name = (u?.name ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name.split(RegExp(r'\s+'));
      final a = parts.first.isNotEmpty ? parts.first[0] : '';
      final b = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
      return (a + b).toUpperCase();
    }
    final email = (u?.email ?? 'U');
    return email.isNotEmpty ? email[0].toUpperCase() : 'U';
  }
}

/* ======================= Widgets de Sección ======================= */

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.member});
  final FamilyMember member;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 230,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: cs.secondaryContainer,
            child: Text(
              _initials(member.name),
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    member.relation,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  if ((member.phone ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      member.phone!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final a = parts.isNotEmpty ? parts.first[0] : ' ';
    final b = parts.length > 1 ? parts.last[0] : ' ';
    return (a + b).toUpperCase();
  }
}

class _DevicePill extends StatelessWidget {
  const _DevicePill({
    required this.name,
    required this.subtitle,
    required this.online,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final badgeColor = online ? Colors.green : cs.outline;

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.memory, size: 22),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle + (online ? ' • Conectado' : ' • Desconectado'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: online ? Colors.green : cs.onSurfaceVariant),
      ),
      onTap: onTap,
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _EmptyInline extends StatelessWidget {
  const _EmptyInline({
    required this.icon,
    required this.title,
    required this.actionText,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionText;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 36, color: cs.onSurfaceVariant),
        const SizedBox(height: 10),
        Text(title, style: TextStyle(color: cs.onSurfaceVariant)),
        TextButton(onPressed: onAction, child: Text(actionText)),
      ],
    );
  }
}

/* ======================= Bottom Navigation ======================= */

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.onHelp,
    required this.onFamily,
    required this.onHome,
    required this.onDevices,
  });

  final VoidCallback onHelp;
  final VoidCallback onFamily;
  final VoidCallback onHome;
  final VoidCallback onDevices;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavBtn(icon: Icons.help_outline, label: 'Ayuda', onTap: onHelp),
            _NavBtn(
              icon: Icons.people_alt_outlined,
              label: 'Familia',
              onTap: onFamily,
            ),
            _NavBtn(
              icon: Icons.home_filled,
              label: 'Inicio',
              onTap: onHome,
              active: true,
            ),
            _NavBtn(
              icon: Icons.devices_other,
              label: 'Dispositivos',
              onTap: onDevices,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
