import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'task_target.dart';

class NotificationCapabilities {
  const NotificationCapabilities({
    this.supported = false,
    this.allowed = false,
    this.promotedSupported = false,
    this.promotedAllowed,
    this.dismissed = false,
  });
  final bool supported;
  final bool allowed;
  final bool promotedSupported;
  final bool? promotedAllowed;
  final bool dismissed;
}

abstract interface class TaskNotificationPlatform {
  Future<void> initialize(
      void Function(TaskTarget) onTap, void Function() onDismiss);
  Future<NotificationCapabilities> capabilities();
  Future<bool> requestPermission();
  Future<bool> showProgress({
    required String title,
    required String text,
    required String shortText,
    required TaskTarget target,
    required bool allowStart,
  });
  Future<void> stopProgress();
  Future<void> showFinished(String title, String text, TaskTarget target);
  Future<void> openSettings();
  void dispose();
}

class AndroidTaskNotifications implements TaskNotificationPlatform {
  static const channel = MethodChannel('zcode_remote/notifications');
  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> initialize(
      void Function(TaskTarget) onTap, void Function() onDismiss) async {
    if (!_supported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onTap') {
        final target = TaskTarget.parse(call.arguments);
        if (target != null) onTap(target);
      } else if (call.method == 'onDismiss') {
        onDismiss();
      }
    });
    final payload = await channel.invokeMethod<String>('initialize');
    final target = TaskTarget.parse(payload);
    if (target != null) onTap(target);
  }

  @override
  Future<NotificationCapabilities> capabilities() async {
    if (!_supported) return const NotificationCapabilities();
    final map = await channel.invokeMapMethod<String, dynamic>('capabilities');
    return NotificationCapabilities(
      supported: true,
      allowed: map?['allowed'] == true,
      promotedSupported: map?['promotedSupported'] == true,
      promotedAllowed: map?['promotedAllowed'] as bool?,
      dismissed: map?['dismissed'] == true,
    );
  }

  @override
  Future<bool> requestPermission() async =>
      _supported &&
      (await channel.invokeMethod<bool>('requestPermission') ?? false);

  @override
  Future<bool> showProgress({
    required String title,
    required String text,
    required String shortText,
    required TaskTarget target,
    required bool allowStart,
  }) async =>
      _supported &&
      (await channel.invokeMethod<bool>('showProgress', {
            'title': title,
            'text': text,
            'shortText': shortText,
            'payload': jsonEncode(target.toJson()),
            'allowStart': allowStart,
          }) ??
          false);

  @override
  Future<void> stopProgress() async {
    if (_supported) await channel.invokeMethod<void>('stopProgress');
  }

  @override
  Future<void> showFinished(
      String title, String text, TaskTarget target) async {
    if (_supported) {
      await channel.invokeMethod<void>('showFinished', {
        'title': title,
        'text': text,
        'payload': jsonEncode(target.toJson()),
        'key': target.key,
      });
    }
  }

  @override
  Future<void> openSettings() async {
    if (_supported) await channel.invokeMethod<void>('openSettings');
  }

  @override
  void dispose() {
    if (_supported) channel.setMethodCallHandler(null);
  }
}
