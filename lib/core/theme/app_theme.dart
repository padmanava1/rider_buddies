import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.tealGreen,
    scaffoldBackgroundColor: Colors.white,
    textTheme: TextTheme(
      displayLarge: GoogleFonts.montserrat(
        fontWeight: FontWeight.bold,
        fontSize: 32,
        color: AppColors.tealGreen,
      ),
      bodyLarge: GoogleFonts.nunito(fontSize: 16, color: Colors.black),
      titleLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: AppColors.tealGreen,
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.darkTeal,
    scaffoldBackgroundColor: AppColors.darkGrey,
    textTheme: TextTheme(
      displayLarge: GoogleFonts.montserrat(
        fontWeight: FontWeight.bold,
        fontSize: 32,
        color: AppColors.darkTeal,
      ),
      bodyLarge: GoogleFonts.nunito(fontSize: 16, color: Colors.white),
      titleLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 20,
        color: AppColors.darkTeal,
      ),
    ),
  );
}
