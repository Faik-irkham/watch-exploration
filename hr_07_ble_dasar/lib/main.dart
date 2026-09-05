import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hr_07_ble_dasar/background_service.dart';
import 'package:hr_07_ble_dasar/cubit/ble_server_cubit.dart';
import 'package:hr_07_ble_dasar/cubit/heart_rate_cubit.dart';
import 'package:hr_07_ble_dasar/heart_rate_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: MultiBlocProvider(
        providers: [
          BlocProvider(create: (context) => HeartRateCubit()),
          BlocProvider(create: (context) => BleServerCubit()),
        ],
        child: const HeartRatePage(),
      ),
    );
  }
}
