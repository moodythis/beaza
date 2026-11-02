import 'package:flutter/material.dart';

const Color _seed = Color(0xFF00796B);

ThemeData buildTheme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
