import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/app_theme.dart';
import 'screens/bookshelf_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const EnglishReaderApp());
}

class EnglishReaderApp extends StatelessWidget {
  const EnglishReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Reader',
      theme: AppTheme.theme,
      debugShowCheckedModeBanner: false,
      home: const BookshelfScreen(),
    );
  }
}
