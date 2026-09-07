import 'package:flutter/widgets.dart';
import 'package:hr_07_ble_dasar/heart_rate_page.dart';
import 'package:hr_07_ble_dasar/history_page.dart';

class RootShell extends StatefulWidget {
  const new({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  final _historyKey = GlobalKey<HistoryPageState>();
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        // Muat ulang data riwayat tiap kali halaman kedua digeser masuk.
        if (index == 1) {
          _historyKey.currentState?.reload();
        }
      },
      children: [
        const HeartRatePage(),
        HistoryPage(key: _historyKey),
      ],
    );
  }
}
