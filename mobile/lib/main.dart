import 'package:flutter/material.dart';

import 'screens/role.dart';
import 'ui.dart';

void main() {
  runApp(const SottoApp());
}

class SottoApp extends StatelessWidget {
  const SottoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sotto',
        debugShowCheckedModeBanner: false,
        theme: sottoTheme(),
        home: const RoleScreen(),
      );
}
