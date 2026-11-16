import 'package:flutter/material.dart';

import '../devices/device_store.dart';
import '../l10n.dart';
import 'add_device.dart';
import 'ir_remote_screen.dart';
import 'widgets.dart';
import 'wifi_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final store = DeviceStore.instance;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    if (!store.loaded) store.load();
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _add() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));

  void _open(SavedDevice d) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => d.isWifi ? TvRemoteScreen(device: d) : IrRemoteScreen(device: d),
      ));

  Future<void> _menu(SavedDevice d) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(tr(c, 'Rename', 'Đổi tên')),
            onTap: () => Navigator.pop(c, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr(c, 'Delete', 'Xóa')),
            onTap: () => Navigator.pop(c, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') {
      await store.remove(d);
    } else if (action == 'rename') {
      final name = await askName(context, d.name);
      if (name != null) {
        d.name = name;
        await store.update(d);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = store.devices;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Zapio', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 28)),
        actions: [
          IconButton(icon: const Icon(Icons.add, size: 30), onPressed: _add),
          const SizedBox(width: 8),
        ],
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : devices.isEmpty
              ? _Empty(onAdd: _add)
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: devices.length,
                  itemBuilder: (context, i) {
                    final d = devices[i];
                    return Card(
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _open(d),
                        onLongPress: () => _menu(d),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              Row(children: [
                                Icon(categoryIcon(d.category), size: 40),
                                const Spacer(),
                                Icon(d.isWifi ? Icons.wifi : Icons.settings_remote,
                                    size: 18, color: Colors.white38),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings_remote, size: 72, color: Colors.white38),
          const SizedBox(height: 16),
          Text(tr(context, 'No devices yet', 'Chưa có thiết bị nào'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            tr(context, 'Add your TV, fan, projector… to control it from your phone.',
                'Thêm TV, quạt, máy chiếu… để điều khiển bằng điện thoại.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr(context, 'Add device', 'Thêm thiết bị')),
            onPressed: onAdd,
          ),
        ]),
      ),
    );
  }
}

Future<String?> askName(BuildContext context, String initial) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr(c, 'Device name', 'Tên thiết bị')),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(c, 'Cancel', 'Hủy'))),
        FilledButton(
          onPressed: () {
            final t = ctrl.text.trim();
            Navigator.pop(c, t.isEmpty ? null : t);
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
