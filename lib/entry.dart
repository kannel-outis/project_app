import 'package:flutter/material.dart';
import 'package:project_app/main_.dart' as a;
import 'package:project_app/main_direct.dart' as d;

void main(List<String> args) {
  runApp(const EntryWidget());
}

class EntryWidget extends StatelessWidget {
  static double blockHeight = 0.0;
  static double blockWidth = 0.0;

  static void getBothBlockHeightWidth(BuildContext context) {
    blockHeight = MediaQuery.of(context).size.height / 100;
    blockWidth = MediaQuery.of(context).size.width / 100;
  }

  const EntryWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        getBothBlockHeightWidth(context);
        return child!;
      },
      home: a.MyApp(),
    );
  }
}
