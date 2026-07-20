// lib/screens/store/store_screen.dart
// ─── Coin store with real IAP using in_app_purchase package ─────────────────
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/iap_listener_service.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key});
  @override State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;

  List<ProductDetails> _products = [];
  bool _available  = false;
  bool _loading    = true;
  String? _error;
  String? _processing; // product ID being processed

  static const _productIds = {
    'coins_100', 'coins_500', 'coins_1200', 'premium_monthly',
  };
  static const _subscriptionIds = {'premium_monthly'};

  static const _productMeta = {
    'coins_100':       {'coins': 100,  'label': 'Starter Pack',   'icon': '🪙', 'popular': false},
    'coins_500':       {'coins': 500,  'label': 'Value Pack',     'icon': '💰', 'popular': true},
    'coins_1200':      {'coins': 1200, 'label': 'Premium Pack',   'icon': '👑', 'popular': false},
    'premium_monthly': {'coins': 500,  'label': 'Monthly Pass',   'icon': '⭐', 'popular': false},
  };

  Map<String, dynamic>? _subscription; // last fetched /store/subscription-status

  @override
  void initState() {
    super.initState();
    // Validation itself happens in IapListenerService (app-wide, so a
    // renewal redelivered while this screen isn't open still gets
    // processed) — this screen only reacts to the outcome for its own UI.
    IapListenerService.instance.onGrant = _handleGrant;
    IapListenerService.instance.onError = (msg) {
      if (mounted) setState(() { _processing = null; _error = msg; });
    };
    _loadProducts();
    _loadSubscriptionStatus();
  }

  void _handleGrant(String productId, int coins, String? subscriptionExpiresAt) {
    if (!mounted) return;
    setState(() => _processing = null);
    if (_subscriptionIds.contains(productId)) _loadSubscriptionStatus();
    _showSuccess(coins, subscriptionExpiresAt: subscriptionExpiresAt);
  }

  Future<void> _loadSubscriptionStatus() async {
    final res = await ApiService.getSubscriptionStatus();
    if (mounted && res.success) setState(() => _subscription = res.data);
  }

  Future<void> _loadProducts() async {
    _available = await _iap.isAvailable();
    if (!_available) {
      setState(() { _loading = false; _error = 'Store not available on this device.'; });
      return;
    }
    final res = await _iap.queryProductDetails(_productIds);
    if (mounted) {
      setState(() {
        _products = res.productDetails;
        _loading  = false;
        if (res.error != null) _error = res.error!.message;
      });
    }
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() { _processing = product.id; _error = null; });
    final param = PurchaseParam(productDetails: product);
    try {
      // Subscriptions must NOT go through buyConsumable — Play/App Store
      // treat consuming a subscription purchase token as invalid and it
      // breaks re-verification. buyNonConsumable is the correct call for
      // both non-consumables and subscriptions.
      if (_subscriptionIds.contains(product.id)) {
        await _iap.buyNonConsumable(purchaseParam: param);
      } else {
        await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
      }
    } catch (e) {
      if (mounted) setState(() { _processing = null; _error = e.toString(); });
    }
  }

  void _showSuccess(int coins, {String? subscriptionExpiresAt}) {
    final subMsg = subscriptionExpiresAt != null
        ? '\n\nYour Monthly Pass is active until ${subscriptionExpiresAt.split(' ').first}.'
        : '';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(children: [
          Text('🎉 '),
          Text('Purchase successful!',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        content: Text('+$coins coins have been added to your account.$subMsg',
          style: const TextStyle(fontSize: 14, color: AppColors.muted)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Great!'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    IapListenerService.instance.onGrant = null;
    IapListenerService.instance.onError = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coin Store'),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              const Icon(Icons.monetization_on, color: AppColors.gold, size: 18),
              const SizedBox(width: 4),
              Text('${user?.coins ?? 0}',
                style: const TextStyle(fontSize: 14,
                  fontWeight: FontWeight.w700, color: AppColors.gold)),
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.red, strokeWidth: 2))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.goldLight,
                      border: Border.all(color: const Color(0xFFE8C56A)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(children: [
                      Text('🪙', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 8),
                      Text('Use coins for hints, boosts & more',
                        style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: AppColors.ink),
                        textAlign: TextAlign.center),
                      SizedBox(height: 4),
                      Text('Earn coins by completing quizzes daily.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                        textAlign: TextAlign.center),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  if (_subscription?['is_subscribed'] == true) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.greenLight,
                        border: const Border(
                          left: BorderSide(color: AppColors.green, width: 3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '⭐ Monthly Pass active until '
                        '${(_subscription?['expires_at'] as String? ?? '').split(' ').first}',
                        style: const TextStyle(fontSize: 12,
                          fontWeight: FontWeight.w700, color: AppColors.green)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.redLight,
                        border: const Border(
                          left: BorderSide(color: AppColors.red, width: 3)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_error!,
                        style: const TextStyle(color: AppColors.red, fontSize: 13)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Products
                  if (_products.isEmpty && !_loading)
                    const Center(child: Text('No products available.',
                      style: TextStyle(color: AppColors.muted)))
                  else
                    ..._products.map((p) {
                      final meta   = _productMeta[p.id];
                      final busy   = _processing == p.id;
                      final popular = meta?['popular'] == true;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              border: Border.all(
                                color: popular
                                    ? AppColors.gold
                                    : AppColors.border,
                                width: popular ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                Text(meta?['icon'] as String? ?? '🪙',
                                  style: const TextStyle(fontSize: 32)),
                                const SizedBox(width: 14),
                                Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(meta?['label'] as String? ?? p.title,
                                      style: const TextStyle(fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink)),
                                    Text('+${meta?['coins'] ?? 0} coins',
                                      style: const TextStyle(fontSize: 13,
                                        color: AppColors.muted)),
                                  ],
                                )),
                                SizedBox(
                                  width: 90,
                                  child: ElevatedButton(
                                    onPressed: busy || _processing != null
                                        ? null : () => _buy(p),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: popular
                                          ? AppColors.gold : AppColors.red,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    ),
                                    child: busy
                                        ? const SizedBox(width: 16, height: 16,
                                            child: CircularProgressIndicator(
                                              color: Colors.white, strokeWidth: 2))
                                        : Text(p.price,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                          if (popular)
                            Positioned(
                              top: -8, right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('POPULAR',
                                  style: TextStyle(fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.5)),
                              ),
                            ),
                        ],
                      );
                    }),

                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Payments processed by Apple / Google.\n'
                      'All purchases are final and non-refundable.',
                      style: TextStyle(fontSize: 10, color: AppColors.muted2),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
