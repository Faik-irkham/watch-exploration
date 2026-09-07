import 'package:flutter/material.dart';

import 'pages/hr_receiver_page.dart';

void main() {
  runApp(const ReceiverApp());
}

class ReceiverApp extends StatelessWidget {
  const ReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HR Receiver',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HrReceiverPage(),
    );
  }
}
