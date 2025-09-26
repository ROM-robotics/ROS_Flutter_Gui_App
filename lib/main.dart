import 'dart:async';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:ros_flutter_gui_app/global/setting.dart';
import 'package:ros_flutter_gui_app/provider/global_state.dart';
import 'package:ros_flutter_gui_app/provider/nav_point_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ros_flutter_gui_app/page/main_page.dart';
import 'package:ros_flutter_gui_app/page/connect_page.dart';
import 'package:ros_flutter_gui_app/provider/ros_channel.dart';
import 'package:ros_flutter_gui_app/page/setting_page.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'provider/them_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ros_flutter_gui_app/language/l10n/gen/app_localizations.dart';

import 'package:oktoast/oktoast.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Set up global error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    print('Flutter Error: ${details.exception}');
    print('Stack trace: ${details.stack}');
  };
  
  // Catch unhandled async exceptions
  PlatformDispatcher.instance.onError = (error, stack) {
    print('Unhandled async error: $error');
    print('Stack trace: $stack');
    return true; // Prevent app crashes
  };
  
  await _setInitialOrientation();
  runApp(MultiProvider(providers: [
    Provider<RosChannel>(create: (_) => RosChannel()),
    ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ChangeNotifierProvider<GlobalState>(create: (_) => GlobalState()),
    ChangeNotifierProvider<NavPointManager>(create: (_) => NavPointManager())
  ], child: MyApp()));
}

Future<void> _setInitialOrientation() async {
  final prefs = await SharedPreferences.getInstance();
  final orientationValue = prefs.getString('screenOrientation') ?? 'landscape';
  if (orientationValue == 'portrait') {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = Locale('en'); // Default language

  @override
  void initState() {
    super.initState();
    _loadLocale(); // Load saved language settings
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    WakelockPlus.toggle(enable: true);

    // Move globalSetting.setLanguage assignment to initState
    globalSetting.setLanguage = (Locale locale) {
      setState(() {
        _locale = locale;
      });
    };
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString('language') ?? 'en';
    setState(() {
      _locale = Locale(languageCode);
    });
  }

  void setLocale(Locale newLocale) {
    _locale = newLocale;
  }

  @override
  Widget build(BuildContext context) {
    return OKToast(
      child: MaterialApp(
      title: 'Ros Flutter GUI App',
      debugShowCheckedModeBanner: false,
      locale: _locale, // Set application language
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        Locale('en'), // English
        Locale('zh'), // Chinese
      ],
      initialRoute: "/connect",
      routes: {
        "/connect": ((context) => ConnectPage()),
        "/map": ((context) => MainFlamePage()),
        "/setting": ((context) => SettingsPage()),
        // "/gamepad":((context) => GamepadPage()),
      },
      themeMode: Provider.of<ThemeProvider>(context, listen: true).themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.blue,
          secondary: Colors.blue[50],
          background: Color.fromRGBO(240, 240, 240, 1),
          surface: Color.fromARGB(153, 224, 224, 224),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        iconTheme: IconThemeData(
          color: Colors.black, // Set global icon color to black
        ),
        cardColor: Color.fromRGBO(230, 230, 230, 1),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(elevation: 0),
        chipTheme: ThemeData.light().chipTheme.copyWith(
              backgroundColor: Colors.white,
              elevation: 10.0,
              shape: StadiumBorder(
                side: BorderSide(
                  color: Colors.grey[300]!, // Set border color
                  width: 1.0, // Set border width
                ),
              ),
            ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme:
            ColorScheme.fromSwatch(brightness: Brightness.dark).copyWith(
          primary: Colors.blue,
          secondary: Colors.blueGrey,
          surface: Color.fromRGBO(60, 60, 60, 1),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        cardColor: Color.fromRGBO(230, 230, 230, 1),
        scaffoldBackgroundColor: Color.fromRGBO(40, 40, 40, 1),
        appBarTheme: AppBarTheme(elevation: 0),
        iconTheme: IconThemeData(
          color: Colors.white, // Set global icon color to white
        ),
        chipTheme: ThemeData.dark().chipTheme.copyWith(
              backgroundColor: Color.fromRGBO(60, 60, 60, 1),
              elevation: 10.0,
              shape: StadiumBorder(
                side: BorderSide(
                  color: Colors.white, // Set border color
                  width: 1.0, // Set border width
                ),
              ),
            ),
      ),
      home: ConnectPage(),
      ),
    );
  }
}
