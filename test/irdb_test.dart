import 'package:flutter_test/flutter_test.dart';
import 'package:zapio/ir/encoders.dart';
import 'package:zapio/ir/irdb.dart';
import 'package:zapio/l10n.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled signal encodes to a sane pattern', () async {
    var total = 0;
    for (final cat in Cat.irCategories) {
      final remotes = await IrDb.category(cat);
      expect(remotes, isNotEmpty, reason: cat);
      for (final r in remotes) {
        for (final s in r.signals) {
          final f = encodeSignal(s);
          expect(f.pattern, isNotEmpty, reason: '${r.id} ${s.name}');
          expect(f.pattern.every((d) => d > 0), isTrue, reason: '${r.id} ${s.name}');
          expect(f.durationUs, lessThan(2000000), reason: '${r.id} ${s.name}');
          total++;
        }
      }
    }
    expect(total, greaterThan(50000));
  });

  test('probe groups dedupe power codes', () async {
    final tvs = await IrDb.category(Cat.tv);
    final groups = IrDb.probeGroups(tvs, 'Samsung');
    final count = tvs.where((r) => r.brand == 'Samsung').length;
    expect(groups, isNotEmpty);
    expect(groups.length, lessThanOrEqualTo(count));
  });
}
