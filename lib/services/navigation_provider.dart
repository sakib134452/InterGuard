import 'package:flutter/material.dart';

enum LogFilterType { all, allowed, blocked }

class NavigationProvider extends ChangeNotifier {
  int _selectedIndex = 0;
  LogFilterType _logFilter = LogFilterType.all;

  int get selectedIndex => _selectedIndex;
  LogFilterType get logFilter => _logFilter;

  void setTab(int index, {LogFilterType filter = LogFilterType.all}) {
    _selectedIndex = index;
    _logFilter = filter;
    notifyListeners();
  }
}
