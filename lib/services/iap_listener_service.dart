// lib/services/iap_listener_service.dart
// ─── App-wide purchase stream listener ────────────────────────────────────
// Previously this lived entirely inside StoreScreen's initState/dispose, so
// a subscription renewal (or any purchase) redelivered by the platform while
// the user was anywhere else in the app never got validated/credited —
// opening and using the app normally wasn't enough, the user had to happen
// to revisit the Store screen. Owning exactly one subscription for the
// whole app lifetime means every redelivered transaction gets processed
// regardless of what's on screen; StoreScreen just registers callbacks for
// its own UI reactions (success dialog, refreshing subscription status).
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'api_service.dart';
import 'auth_provider.dart';

typedef PurchaseGrantCallback = void Function(
    String productId, int coins, String? subscriptionExpiresAt);
typedef PurchaseErrorCallback = void Function(String message);

class IapListenerService {
  IapListenerService._();
  static final IapListenerService instance = IapListenerService._();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _started = false;

  PurchaseGrantCallback? onGrant;
  PurchaseErrorCallback? onError;

  void start(GlobalKey<NavigatorState> navigatorKey) {
    if (_started) return;
    _started = true;
    _navigatorKey = navigatorKey;
    _sub = _iap.purchaseStream.listen(_handle, onError: (_) {});
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.error) {
        onError?.call(purchase.error?.message ?? 'Purchase failed.');
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue; // pending / canceled — nothing to validate yet
      }

      final receipt = Platform.isIOS
          ? purchase.verificationData.serverVerificationData
          : purchase.verificationData.localVerificationData;

      final res = await ApiService.validateIAPPurchase(
        productId:   purchase.productID,
        receiptData: receipt,
        platform:    Platform.isIOS ? 'ios' : 'android',
      );

      if (res.success) {
        await _iap.completePurchase(purchase);
        final ctx = _navigatorKey?.currentContext;
        if (ctx != null && ctx.mounted) {
          await ctx.read<AuthProvider>().refreshUser();
        }
        onGrant?.call(purchase.productID,
            (res.data?['coins_granted'] ?? 0) as int,
            res.data?['subscription_expires_at'] as String?);
      } else {
        onError?.call(res.error ?? 'Purchase verification failed.');
      }
    }
  }
}
