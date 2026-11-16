import 'package:flutter/widgets.dart';

/// Minimal EN/VI localisation: `tr(context, 'English', 'Tiếng Việt')`.
/// Vietnamese when the phone language is Vietnamese, English otherwise.
bool isVi(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.languageCode == 'vi';

String tr(BuildContext context, String en, String vi) => isVi(context) ? vi : en;

/// Category ids used by the IR DB and saved devices.
class Cat {
  static const tv = 'TV';
  static const fan = 'Fan';
  static const projector = 'Projector';
  static const box = 'Box';
  static const audio = 'Audio';
  static const airPurifier = 'AirPurifier';
  static const ac = 'AC';

  static const irCategories = [tv, fan, projector, box, audio, airPurifier];

  static String label(BuildContext c, String id) => switch (id) {
        tv => 'TV',
        fan => tr(c, 'Fan', 'Quạt'),
        projector => tr(c, 'Projector', 'Máy chiếu'),
        box => tr(c, 'TV box / Set-top', 'Đầu thu / TV box'),
        audio => tr(c, 'Speaker / Amplifier', 'Loa / Ampli'),
        airPurifier => tr(c, 'Air purifier', 'Máy lọc không khí'),
        ac => tr(c, 'Air conditioner', 'Điều hòa'),
        _ => id,
      };
}
