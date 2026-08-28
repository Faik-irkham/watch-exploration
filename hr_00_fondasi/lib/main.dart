import 'package:flutter/material.dart';

void main() {
  runApp(const HeartRateApp());
}

class HeartRateApp extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: Scaffold(body: Text("25 BPM")));
  }
}
