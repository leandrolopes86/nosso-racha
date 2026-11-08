import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'home_publica_view.dart';
import 'services/theme_service.dart';

import 'services/auth_service.dart';
import 'services/event_service.dart';
import 'services/finance_service.dart';
import 'services/match_service.dart';
import 'services/notification_service.dart';
import 'services/payment_gateway_service.dart';
import 'services/settings_service.dart';
import 'services/user_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const NossoRachaApp());
}

class NossoRachaApp extends StatelessWidget {
  const NossoRachaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<EventService>(create: (_) => EventService()),
        Provider<NotificationService>(create: (_) => NotificationService()),
        ChangeNotifierProvider<FinanceService>(create: (_) => FinanceService()),
        ChangeNotifierProvider<MatchService>(create: (_) => MatchService()),
        ChangeNotifierProvider<PaymentGatewayService>(
          create: (_) => PaymentGatewayService(),
        ),
        ChangeNotifierProvider<SettingsService>(
          create: (_) => SettingsService(),
        ),
        ChangeNotifierProvider<UserService>(create: (_) => UserService()),
        ChangeNotifierProvider<ThemeService>(create: (_) => ThemeService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, _) => MaterialApp(
          title: 'Nosso Racha',
          debugShowCheckedModeBanner: false,
          theme: themeService.getThemeData(),
          home: const HomePublicaView(),
        ),
      ),
    );
  }
}
