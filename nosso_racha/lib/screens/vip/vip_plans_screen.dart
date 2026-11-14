import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user_model.dart';
import '../../models/vip_plans_config.dart';
import '../../services/auth_service.dart';
import '../../services/vip_checkout_popup_stub.dart'
    if (dart.library.js_interop) '../../services/vip_checkout_popup_web.dart'
    as checkout_popup;
import '../../widgets/vip_plan_badge.dart';

class VipPlansScreen extends StatefulWidget {
  const VipPlansScreen({super.key});

  @override
  State<VipPlansScreen> createState() => _VipPlansScreenState();
}

class _VipPlansScreenState extends State<VipPlansScreen>
    with WidgetsBindingObserver {
  static const _planIds = ['bronze', 'silver', 'gold', 'platinum'];
  final _functions = FirebaseFunctions.instanceFor(
    region: 'southamerica-east1',
  );
  late final _paymentConfigStream = FirebaseFirestore.instance
      .collection('settings')
      .doc('payment_config')
      .snapshots();
  final _couponCodeController = TextEditingController();
  String? _manualRequestsStreamUid;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _manualRequestsStream;
  String _selectedPlan = 'bronze';
  bool _isSubmitting = false;
  bool _isValidatingCoupon = false;
  int _couponValidationGeneration = 0;
  bool _manualRequestSent = false;
  Map<String, dynamic>? _validatedCoupon;
  String? _couponMessage;
  bool _couponError = false;
  String? _orderId;
  String? _checkoutUrl;
  String? _paymentQrCode;
  String? _paymentQrBase64;
  DateTime? _paymentExpiresAt;
  String? _paymentError;
  String? _orderStreamId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _orderStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _orderSubscription;
  String _orderStatus = 'pending';
  bool _orderReloadScheduled = false;
  bool _paymentExpired = false;
  bool _isRestoringOrder = false;
  bool _restoreScheduled = false;
  bool _isCheckingPayment = false;
  bool _isCancellingPayment = false;
  bool _isOpeningCheckout = false;
  bool _isLegacyPixOrder = false;
  String? _restorationUid;
  Timer? _paymentPollingTimer;
  final Set<String> _expiredNoticeShownOrderIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _hasPendingMercadoPagoPayment) {
      unawaited(_checkMercadoPagoPayment(_orderId!, showPendingMessage: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _paymentPollingTimer?.cancel();
    final orderSubscription = _orderSubscription;
    if (orderSubscription != null) unawaited(orderSubscription.cancel());
    _couponCodeController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) => date == null
      ? 'Sem data de vencimento'
      : DateFormat('dd/MM/yyyy').format(date);

  String _formatPrice(int? cents) => cents == null
      ? 'Preço não configurado'
      : NumberFormat.currency(
          locale: 'pt_BR',
          symbol: 'R\$',
        ).format(cents / 100);

  Stream<QuerySnapshot<Map<String, dynamic>>> _manualRequestsFor(String uid) {
    if (_manualRequestsStreamUid != uid || _manualRequestsStream == null) {
      _manualRequestsStreamUid = uid;
      _manualRequestsStream = FirebaseFirestore.instance
          .collection('vip_payment_requests')
          .where('uid', isEqualTo: uid)
          .snapshots();
    }
    return _manualRequestsStream!;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _orderFor(String orderId) {
    if (_orderStreamId != orderId || _orderStream == null) {
      _orderStreamId = orderId;
      _orderStream = FirebaseFirestore.instance
          .collection('vip_payment_orders')
          .doc(orderId)
          .snapshots();
    }
    return _orderStream!;
  }

  bool get _hasPendingMercadoPagoPayment =>
      _orderId != null && _orderStatus == 'pending';

  bool get _canChangePlan =>
      !_restoreScheduled &&
      !_isRestoringOrder &&
      !_isSubmitting &&
      !_hasPendingMercadoPagoPayment &&
      !(_orderId != null && _orderStatus == 'expired');

  void _startMercadoPagoPaymentPolling(String orderId) {
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted ||
          _orderId != orderId ||
          !_hasPendingMercadoPagoPayment ||
          _paymentExpired) {
        return;
      }
      unawaited(_checkMercadoPagoPayment(orderId, showPendingMessage: false));
    });
  }

  void _stopMercadoPagoPaymentPolling() {
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer = null;
  }

  void _clearCoupon() {
    _couponValidationGeneration++;
    _couponCodeController.clear();
    if (!mounted) return;
    setState(() {
      _isValidatingCoupon = false;
      _validatedCoupon = null;
      _couponMessage = null;
      _couponError = false;
    });
  }

  void _watchMercadoPagoOrder(String orderId) {
    final previousSubscription = _orderSubscription;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _orderSubscription = _orderFor(orderId).listen(
      (snapshot) {
        final data = snapshot.data();
        if (data == null || !mounted) return;
        final status = data['status'] as String? ?? 'pending';
        final cancelReason = data['cancelReason'] as String?;
        setState(
          () => _orderStatus = cancelReason == 'expired' ? 'expired' : status,
        );
        if (status == 'approved' ||
            status == 'expired' ||
            cancelReason == 'expired') {
          _clearCoupon();
        }
        if (status == 'pending' && cancelReason != 'expired') {
          _startMercadoPagoPaymentPolling(orderId);
        } else {
          _stopMercadoPagoPaymentPolling();
        }
        if (status == 'approved') _reloadVipUser();
        if (cancelReason == 'expired') {
          unawaited(_showExpiredPaymentDialog(orderId));
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _paymentError =
              'Não foi possível acompanhar o pagamento: '
              '${_callableErrorMessage(error)}';
        });
      },
    );
  }

  void _reloadVipUser() {
    if (_orderReloadScheduled || !mounted) return;
    _orderReloadScheduled = true;
    unawaited(context.read<AuthService>().reloadUser());
  }

  bool get _hasCurrentCoupon {
    final coupon = _validatedCoupon;
    return coupon != null &&
        coupon['plan'] == _selectedPlan &&
        coupon['code'] == _couponCodeController.text.trim().toUpperCase();
  }

  void _selectPlan(String plan) {
    if (!_canChangePlan) return;
    if (plan == _selectedPlan) return;
    setState(() {
      _couponValidationGeneration++;
      _isValidatingCoupon = false;
      _selectedPlan = plan;
      _validatedCoupon = null;
      _couponMessage = null;
    });
  }

  Future<void> _validateCoupon() async {
    final code = _couponCodeController.text.trim().toUpperCase();
    final plan = _selectedPlan;
    final validationGeneration = ++_couponValidationGeneration;
    if (code.isEmpty) {
      setState(() {
        _isValidatingCoupon = false;
        _validatedCoupon = null;
        _couponMessage = 'Informe o código do cupom.';
        _couponError = true;
      });
      return;
    }

    setState(() {
      _isValidatingCoupon = true;
      _validatedCoupon = null;
      _couponMessage = null;
    });
    try {
      final result = await _functions.httpsCallable('validateVipCoupon').call({
        'code': code,
        'plan': plan,
      });
      final coupon = Map<String, dynamic>.from(result.data as Map);
      if (!mounted ||
          validationGeneration != _couponValidationGeneration ||
          plan != _selectedPlan ||
          code.toUpperCase() !=
              _couponCodeController.text.trim().toUpperCase()) {
        return;
      }
      setState(() {
        _validatedCoupon = {...coupon, 'plan': plan};
        _couponMessage =
            'Cupom aplicado: ${_formatPrice(coupon['discountCents'] as int)} de desconto. '
            'Total: ${_formatPrice(coupon['finalAmountCents'] as int)}.';
        _couponError = false;
      });
    } catch (error) {
      if (!mounted || validationGeneration != _couponValidationGeneration) {
        return;
      }
      setState(() {
        _validatedCoupon = null;
        _couponMessage = _callableErrorMessage(error);
        _couponError = true;
      });
    } finally {
      if (mounted && validationGeneration == _couponValidationGeneration) {
        setState(() => _isValidatingCoupon = false);
      }
    }
  }

  String _callableErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Não foi possível validar o cupom.';
    }
    final message = error.toString().replaceFirst('Exception: ', '');
    final details = RegExp(r'message:\s*([^\]]+)').firstMatch(message);
    return details?.group(1)?.trim() ?? message;
  }

  Future<void> _startSubscription(
    UserModel user,
    Map<String, dynamic> config,
  ) async {
    if (_isSubmitting || !_canChangePlan) return;
    final planPrice =
        (config['prices'] as Map<String, dynamic>?)?[_selectedPlan]
            as Map<String, dynamic>?;
    final amountCents = planPrice?['amountCents'];
    final durationDays = planPrice?['durationDays'];
    if (_couponCodeController.text.trim().isNotEmpty && !_hasCurrentCoupon) {
      setState(() {
        _paymentError = 'Valide o cupom antes de assinar.';
      });
      return;
    }
    if (amountCents is! int ||
        amountCents <= 0 ||
        durationDays is! int ||
        durationDays <= 0) {
      setState(
        () => _paymentError = 'O preço deste plano ainda não foi configurado.',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
      _paymentError = null;
      _manualRequestSent = false;
    });
    try {
      final couponCode = _hasCurrentCoupon
          ? _validatedCoupon!['code'] as String
          : null;
      final finalAmount = _hasCurrentCoupon
          ? _validatedCoupon!['finalAmountCents'] as int
          : amountCents;
      if (config['provider'] == 'pix_manual') {
        await _showManualPixDialog(config, finalAmount, couponCode);
      } else if (config['provider'] == 'mercadopago') {
        await _createMercadoPagoCheckout(couponCode);
      } else {
        throw StateError('Nenhum meio de pagamento VIP está ativo.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _paymentError = _callableErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _showManualPixDialog(
    Map<String, dynamic> config,
    int amountCents,
    String? couponCode,
  ) async {
    final pixKey = config['manualPixKey'] as String? ?? '';
    final beneficiary = config['manualBeneficiary'] as String? ?? '';
    final instructions = config['manualInstructions'] as String? ?? '';
    if (pixKey.trim().isEmpty) {
      throw StateError('A chave Pix do grupo ainda não foi configurada.');
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pagamento Pix'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatPrice(amountCents),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (beneficiary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Beneficiário: $beneficiary'),
              ],
              const SizedBox(height: 12),
              const Text(
                'Chave Pix',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(pixKey),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: pixKey));
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('Chave Pix copiada.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar chave'),
                ),
              ),
              if (instructions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(instructions),
              ],
              const SizedBox(height: 12),
              const Text(
                'Após pagar, avise o administrador para validar a assinatura.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Agora não'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Já paguei'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _functions.httpsCallable('createVipManualPixRequest').call({
      'plan': _selectedPlan,
      'couponCode': couponCode,
      'expectedAmountCents': amountCents,
    });
    if (mounted) setState(() => _manualRequestSent = true);
  }

  Future<void> _createMercadoPagoCheckout(String? couponCode) async {
    final (confirmed, popup) = await _confirmMercadoPagoCheckout();
    if (!confirmed) return;

    try {
      final callable = _functions.httpsCallable('createVipMercadoPagoCheckout');
      final result = await callable.call({
        'plan': _selectedPlan,
        'couponCode': couponCode,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final orderId = data['orderId'];
      final checkoutUrl = data['checkoutUrl'];
      final expiresAtValue = data['expiresAt'];
      if (orderId is! String ||
          checkoutUrl is! String ||
          expiresAtValue is! String) {
        throw StateError(
          'A resposta do Mercado Pago não contém um checkout válido.',
        );
      }
      final expiresAt = DateTime.tryParse(expiresAtValue);
      if (expiresAt == null) {
        throw StateError(
          'A resposta do Mercado Pago não contém um prazo válido.',
        );
      }
      if (!mounted) {
        checkout_popup.closeVipCheckoutPopup(popup);
        return;
      }
      setState(() {
        _orderId = orderId;
        _checkoutUrl = checkoutUrl;
        _isLegacyPixOrder = false;
        _paymentQrCode = null;
        _paymentQrBase64 = null;
        _paymentExpiresAt = expiresAt;
        _paymentExpired = false;
        _orderStatus = 'pending';
        _orderReloadScheduled = false;
      });
      _watchMercadoPagoOrder(orderId);
      await _launchMercadoPagoCheckout(checkoutUrl, popup);
    } catch (error) {
      checkout_popup.closeVipCheckoutPopup(popup);
      rethrow;
    }
  }

  Future<void> _openMercadoPagoCheckout(String orderId) async {
    final checkoutUrl = _checkoutUrl;
    if (checkoutUrl == null || _isOpeningCheckout) return;
    setState(() => _isOpeningCheckout = true);
    Object? popup;
    try {
      final confirmation = await _confirmMercadoPagoCheckout();
      if (!confirmation.$1 || !mounted) return;
      popup = confirmation.$2;
      await _launchMercadoPagoCheckout(checkoutUrl, popup);
      if (mounted &&
          _orderId == orderId &&
          _orderStatus == 'pending' &&
          _paymentQrCode == null) {
        await _checkMercadoPagoPayment(orderId, showPendingMessage: false);
      }
    } catch (error) {
      checkout_popup.closeVipCheckoutPopup(popup);
      if (mounted) {
        setState(() => _paymentError = _callableErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isOpeningCheckout = false);
    }
  }

  Future<(bool, Object?)> _confirmMercadoPagoCheckout() async {
    Object? popup;
    String? popupError;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: const Text('Pagamento em ambiente seguro'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kIsWeb
                    ? 'Uma janela popup segura do Mercado Pago será aberta. O pedido fica válido por 10 minutos; ao retornar, o pagamento será consultado automaticamente.'
                    : 'Uma visualização segura do Mercado Pago será aberta para concluir o pagamento. O pedido fica válido por 10 minutos e o status continuará sendo consultado.',
              ),
              if (popupError != null) ...[
                const SizedBox(height: 12),
                Text(
                  popupError!,
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Agora não'),
            ),
            FilledButton(
              onPressed: () {
                if (kIsWeb) {
                  popup = checkout_popup.openVipCheckoutPopup();
                  if (popup == null) {
                    setDialogState(() {
                      popupError =
                          'O navegador bloqueou o popup. Permita pop-ups para este site e tente novamente.';
                    });
                    return;
                  }
                }
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                kIsWeb ? 'Abrir popup seguro' : 'Continuar para pagamento',
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      checkout_popup.closeVipCheckoutPopup(popup);
      return (false, null);
    }
    return (true, popup);
  }

  Future<void> _launchMercadoPagoCheckout(
    String checkoutUrl,
    Object? popup,
  ) async {
    final uri = Uri.tryParse(checkoutUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        !(uri.host == 'mercadopago.com.br' ||
            uri.host.endsWith('.mercadopago.com.br') ||
            uri.host == 'mercadopago.com' ||
            uri.host.endsWith('.mercadopago.com'))) {
      throw StateError('O link de checkout do Mercado Pago é inválido.');
    }
    if (kIsWeb) {
      if (checkout_popup.vipCheckoutPopupIsClosed(popup)) {
        throw StateError(
          'O popup do pagamento foi fechado. Abra novamente para continuar.',
        );
      }
      checkout_popup.navigateVipCheckoutPopup(popup, checkoutUrl);
      return;
    }

    final inAppBrowserSupported =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final launched = await launchUrl(
      uri,
      mode: inAppBrowserSupported
          ? LaunchMode.inAppBrowserView
          : LaunchMode.platformDefault,
    );
    if (!launched) {
      throw StateError('Não foi possível abrir o checkout do Mercado Pago.');
    }
  }

  Future<void> _restoreMercadoPagoOrder(String uid) async {
    if (_isRestoringOrder) return;
    if (mounted) setState(() => _isRestoringOrder = true);
    try {
      var isLegacyPixOrder = false;
      var result = await _functions
          .httpsCallable('getVipMercadoPagoCheckoutOrder')
          .call();
      var data = Map<String, dynamic>.from(result.data as Map);
      if (data['status'] == 'none') {
        isLegacyPixOrder = true;
        result = await _functions
            .httpsCallable('getVipMercadoPagoOrder')
            .call();
        data = Map<String, dynamic>.from(result.data as Map);
      }
      final status = data['status'] as String?;
      if (status == null || status == 'none') return;
      if (!mounted || context.read<AuthService>().currentUser?.uid != uid) {
        return;
      }
      if (status == 'approved') {
        _clearCoupon();
        _reloadVipUser();
        return;
      }

      final orderId = data['orderId'];
      final plan = data['plan'];
      if (orderId is! String || plan is! String || !_planIds.contains(plan)) {
        throw StateError('A resposta do pedido VIP pendente é inválida.');
      }
      final expiresAtValue = data['expiresAt'];
      final expiresAt = expiresAtValue is String
          ? DateTime.tryParse(expiresAtValue)
          : null;
      final qrCode = data['qrCode'];
      final checkoutUrl = data['checkoutUrl'];
      if (status == 'pending' &&
          ((qrCode is! String && checkoutUrl is! String) ||
              expiresAt == null)) {
        throw StateError('O pedido VIP não contém os dados do pagamento.');
      }

      if (!mounted) return;
      if (status == 'expired') _clearCoupon();
      setState(() {
        _orderId = orderId;
        _orderStatus = status;
        _selectedPlan = plan;
        _isLegacyPixOrder = isLegacyPixOrder;
        _checkoutUrl = checkoutUrl is String ? checkoutUrl : null;
        _paymentQrCode = qrCode is String ? qrCode : null;
        _paymentQrBase64 = data['qrCodeBase64'] as String?;
        _paymentExpiresAt = expiresAt;
        _paymentExpired = status == 'expired';
        _orderReloadScheduled = false;
      });
      _watchMercadoPagoOrder(orderId);
      if (status == 'expired') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_showExpiredPaymentDialog(orderId));
        });
      } else if (status == 'approved') {
        _reloadVipUser();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentError = _callableErrorMessage(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoringOrder = false;
          _restoreScheduled = false;
          _restorationUid = uid;
        });
      }
    }
  }

  Future<void> _checkMercadoPagoPayment(
    String orderId, {
    bool showPendingMessage = true,
  }) async {
    if (_isCheckingPayment) return;
    setState(() => _isCheckingPayment = true);
    try {
      final result = await _functions
          .httpsCallable(
            _isLegacyPixOrder
                ? 'checkVipMercadoPagoPix'
                : 'checkVipMercadoPagoCheckout',
          )
          .call({'orderId': orderId});
      final data = Map<String, dynamic>.from(result.data as Map);
      final status = data['status'] as String? ?? 'pending';
      final cancelReason = data['cancelReason'] as String?;
      final effectiveStatus = cancelReason == 'expired' ? 'expired' : status;
      if (!mounted) return;
      if (status == 'approved' || effectiveStatus == 'expired') {
        _clearCoupon();
      }
      setState(() {
        _orderStatus = effectiveStatus;
        if (status == 'approved' || status == 'rejected') {
          _paymentExpired = false;
        }
      });
      if (effectiveStatus == 'pending') {
        _startMercadoPagoPaymentPolling(orderId);
      } else {
        _stopMercadoPagoPaymentPolling();
      }
      if (status == 'approved') {
        _reloadVipUser();
        _showPaymentMessage('Pagamento confirmado.');
      } else if (cancelReason == 'expired' || status == 'expired') {
        await _showExpiredPaymentDialog(orderId);
      } else if (status == 'pending') {
        if (showPendingMessage) {
          _showPaymentMessage('O pagamento ainda está pendente.');
        }
      } else {
        _showPaymentMessage('Status atual do pagamento: $status.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _paymentError = _callableErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isCheckingPayment = false);
    }
  }

  Future<void> _confirmMercadoPagoCancellation(String orderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar pagamento?'),
        content: const Text(
          'O checkout será encerrado e este plano não será ativado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Manter pagamento'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancelar pagamento'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isCancellingPayment) return;

    setState(() {
      _isCancellingPayment = true;
      _paymentError = null;
    });
    try {
      final result = await _functions
          .httpsCallable(
            !_isLegacyPixOrder
                ? 'cancelVipMercadoPagoCheckout'
                : 'cancelVipMercadoPagoPix',
          )
          .call({'orderId': orderId, 'reason': 'user'});
      final data = Map<String, dynamic>.from(result.data as Map);
      final status = data['status'] as String? ?? 'pending';
      final cancelReason = data['cancelReason'] as String?;
      if (!mounted) return;
      if (cancelReason == 'expired' || status == 'expired') {
        _clearCoupon();
        setState(() {
          _orderStatus = 'expired';
        });
        await _showExpiredPaymentDialog(orderId);
      } else if (data['cancelled'] == true ||
          status == 'cancelled' ||
          status == 'canceled') {
        _clearMercadoPagoOrder();
        _showPaymentMessage('Pagamento cancelado.');
      } else if (status == 'approved') {
        _clearCoupon();
        setState(() => _orderStatus = 'approved');
        _reloadVipUser();
        _showPaymentMessage('Este pagamento já foi confirmado.');
      } else {
        setState(() => _orderStatus = status);
        _showPaymentMessage('O pagamento ainda não foi cancelado.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _paymentError = _callableErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isCancellingPayment = false);
    }
  }

  Future<void> _onMercadoPagoPaymentExpired(String orderId) async {
    if (!mounted || _paymentExpired) return;
    _stopMercadoPagoPaymentPolling();
    _clearCoupon();
    var showExpirationNotice = false;
    setState(() {
      _paymentExpired = true;
      _paymentError = null;
    });
    try {
      final result = await _functions
          .httpsCallable(
            !_isLegacyPixOrder
                ? 'cancelVipMercadoPagoCheckout'
                : 'cancelVipMercadoPagoPix',
          )
          .call({'orderId': orderId, 'reason': 'expired'});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (mounted) {
        final status = data['status'] as String? ?? 'pending';
        final cancelReason = data['cancelReason'] as String?;
        if (status == 'approved' ||
            cancelReason == 'expired' ||
            status == 'expired') {
          _clearCoupon();
        }
        setState(() {
          _orderStatus = cancelReason == 'expired' ? 'expired' : status;
          if (status == 'approved' || status == 'rejected') {
            _paymentExpired = false;
          }
        });
        if (status == 'approved') {
          _reloadVipUser();
          _showPaymentMessage('Pagamento confirmado.');
        } else if (cancelReason == 'expired' || status == 'expired') {
          showExpirationNotice = true;
        } else if (status == 'rejected') {
          _showPaymentMessage('O pagamento não foi aprovado.');
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentError = _callableErrorMessage(error);
          _paymentExpired = false;
        });
        _startMercadoPagoPaymentPolling(orderId);
      }
    } finally {
      if (mounted && showExpirationNotice) {
        await _showExpiredPaymentDialog(orderId);
      }
    }
  }

  Future<void> _showExpiredPaymentDialog(String orderId) async {
    if (!mounted || !_expiredNoticeShownOrderIds.add(orderId)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Pagamento expirado'),
          content: const Text(
            'O prazo de 10 minutos terminou. Inicie um novo pagamento para continuar.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Entendi'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _functions
          .httpsCallable(
            !_isLegacyPixOrder
                ? 'acknowledgeVipMercadoPagoCheckoutExpiration'
                : 'acknowledgeVipPaymentExpiration',
          )
          .call({'orderId': orderId});
    } catch (error) {
      if (mounted) {
        setState(() => _paymentError = _callableErrorMessage(error));
      }
    }
    if (mounted) _clearMercadoPagoOrder();
  }

  void _clearMercadoPagoOrder() {
    _stopMercadoPagoPaymentPolling();
    final subscription = _orderSubscription;
    _orderSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    setState(() {
      _orderId = null;
      _isLegacyPixOrder = false;
      _checkoutUrl = null;
      _paymentQrCode = null;
      _paymentQrBase64 = null;
      _paymentExpiresAt = null;
      _orderStatus = 'pending';
      _paymentExpired = false;
      _orderReloadScheduled = false;
      _orderStreamId = null;
      _orderStream = null;
    });
  }

  void _showPaymentMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _paymentStatusMessage(String status) {
    if (status == 'expired') return 'Pagamento expirado.';
    if (_paymentExpired) {
      return 'Prazo encerrado. Confirmando o cancelamento do pagamento...';
    }
    if (const ['cancelled', 'canceled'].contains(status)) {
      return 'Pagamento cancelado.';
    }
    if (status == 'rejected') return 'O pagamento não foi aprovado.';
    return 'Pagamento em processamento.';
  }

  Widget _buildManualRequests(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _manualRequestsFor(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final pending =
            snapshot.data?.docs.any(
              (document) => document.data()['status'] == 'pending',
            ) ??
            false;
        if (!_manualRequestSent && !pending) return const SizedBox.shrink();
        return Card(
          child: ListTile(
            leading: const Icon(Icons.hourglass_top, color: Colors.orange),
            title: const Text('Pagamento aguardando validação'),
            subtitle: const Text(
              'O plano será ativado após a confirmação do administrador.',
            ),
          ),
        );
      },
    );
  }

  Widget _buildMercadoPagoOrder() {
    final orderId = _orderId;
    final qrCode = _paymentQrCode;
    if (orderId == null) return const SizedBox.shrink();
    final status = _orderStatus;
    final isPending = status == 'pending' && !_paymentExpired;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              status == 'approved'
                  ? 'Pagamento confirmado'
                  : isPending
                  ? _checkoutUrl == null
                        ? 'Pague com Pix'
                        : 'Conclua o pagamento no Mercado Pago'
                  : _paymentStatusMessage(status),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (status == 'approved')
              const Icon(Icons.check_circle, color: Colors.green, size: 46)
            else if (isPending && qrCode != null) ...[
              if (_paymentQrBase64 != null)
                Image.memory(
                  Uri.parse(
                    'data:image/png;base64,$_paymentQrBase64',
                  ).data!.contentAsBytes(),
                  width: 180,
                  height: 180,
                )
              else
                QrImageView(data: qrCode, size: 180),
              const SizedBox(height: 12),
              SelectableText(qrCode, textAlign: TextAlign.center),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: qrCode));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pix copia e cola copiado.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar Pix copia e cola'),
              ),
              if (_paymentExpiresAt != null)
                _VipPaymentCountdown(
                  key: ValueKey(orderId),
                  expiresAt: _paymentExpiresAt!,
                  onExpired: () => _onMercadoPagoPaymentExpired(orderId),
                ),
              const Text(
                'Você pode sair desta tela e retornar antes do vencimento.',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isCheckingPayment
                        ? null
                        : () => _checkMercadoPagoPayment(orderId),
                    icon: _isCheckingPayment
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Já paguei'),
                  ),
                  TextButton.icon(
                    onPressed: _isCancellingPayment
                        ? null
                        : () => _confirmMercadoPagoCancellation(orderId),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar'),
                  ),
                ],
              ),
            ] else if (isPending && _checkoutUrl != null) ...[
              const Text(
                'O Mercado Pago apresentará os meios de pagamento disponíveis para esta conta, incluindo cartão quando habilitado.',
                textAlign: TextAlign.center,
              ),
              if (_paymentExpiresAt != null)
                _VipPaymentCountdown(
                  key: ValueKey(orderId),
                  expiresAt: _paymentExpiresAt!,
                  onExpired: () => _onMercadoPagoPaymentExpired(orderId),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isOpeningCheckout
                    ? null
                    : () => _openMercadoPagoCheckout(orderId),
                icon: _isOpeningCheckout
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.open_in_new),
                label: const Text('Abrir checkout do Mercado Pago'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isCheckingPayment
                        ? null
                        : () => _checkMercadoPagoPayment(orderId),
                    icon: _isCheckingPayment
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Já paguei'),
                  ),
                  TextButton.icon(
                    onPressed: _isCancellingPayment
                        ? null
                        : () => _confirmMercadoPagoCancellation(orderId),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar'),
                  ),
                ],
              ),
            ] else
              Icon(
                status == 'rejected'
                    ? Icons.error_outline
                    : status == 'expired' ||
                          const ['cancelled', 'canceled'].contains(status)
                    ? Icons.cancel_outlined
                    : Icons.hourglass_top,
                color: status == 'rejected' ? Colors.orange : Colors.grey,
                size: 46,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(String id, Map<String, dynamic> config) {
    final plan = VipPlansConfig.tierFor(id);
    if (plan == null || !plan.active) return const SizedBox.shrink();
    final prices = config['prices'] as Map<String, dynamic>? ?? const {};
    final price = prices[id] as Map<String, dynamic>? ?? const {};
    final cents = price['amountCents'] as int?;
    final days = price['durationDays'] as int?;
    final isSelected = _selectedPlan == id;
    final color = Color(
      int.parse(plan.color.substring(1), radix: 16) | 0xFF000000,
    );
    final benefits = id == 'platinum'
        ? 'Recursos avançados para organizadores'
        : 'Mais organizações e recursos VIP para atletas';

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? color : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: _canChangePlan ? () => _selectPlan(id) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.workspace_premium, color: color, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(benefits),
                    Text('${_formatPrice(cents)} · ${days ?? '—'} dias'),
                  ],
                ),
              ),
              Radio<String>(
                value: id,
                groupValue: _selectedPlan,
                onChanged: _canChangePlan
                    ? (value) {
                        if (value != null) _selectPlan(value);
                      }
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCouponSection() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cupom de desconto', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _couponCodeController,
                    enabled: _canChangePlan,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      TextInputFormatter.withFunction((_, newValue) {
                        if (!newValue.composing.isCollapsed) return newValue;
                        final uppercaseText = newValue.text.toUpperCase();
                        if (uppercaseText == newValue.text) return newValue;

                        int uppercaseOffset(int offset) => offset < 0
                            ? offset
                            : newValue.text
                                  .substring(0, offset)
                                  .toUpperCase()
                                  .length;

                        return newValue.copyWith(
                          text: uppercaseText,
                          selection: TextSelection(
                            baseOffset: uppercaseOffset(
                              newValue.selection.baseOffset,
                            ),
                            extentOffset: uppercaseOffset(
                              newValue.selection.extentOffset,
                            ),
                            affinity: newValue.selection.affinity,
                            isDirectional: newValue.selection.isDirectional,
                          ),
                        );
                      }),
                    ],
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Código do cupom',
                      hintText: 'Digite seu cupom',
                      suffixIcon: _couponCodeController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _couponCodeController.clear();
                                setState(() {
                                  _couponValidationGeneration++;
                                  _isValidatingCoupon = false;
                                  _validatedCoupon = null;
                                  _couponMessage = null;
                                });
                              },
                              tooltip: 'Limpar cupom',
                              icon: const Icon(Icons.close),
                            ),
                    ),
                    onChanged: (_) {
                      setState(() {
                        _couponValidationGeneration++;
                        _isValidatingCoupon = false;
                        _validatedCoupon = null;
                        _couponMessage = null;
                      });
                    },
                    onSubmitted: (_) => _validateCoupon(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: !_canChangePlan || _isValidatingCoupon
                      ? null
                      : _validateCoupon,
                  child: _isValidatingCoupon
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Validar'),
                ),
              ],
            ),
            if (_couponMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _couponMessage!,
                style: TextStyle(
                  color: _couponError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Entre na sua conta para ver os planos.')),
      );
    }
    if (_restorationUid != user.uid && !_restoreScheduled) {
      _restoreScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_restoreMercadoPagoOrder(user.uid));
      });
    }
    final activeVip = user.hasActiveVipPlan;
    final expiresAt = user.vipExpiresAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Planos VIP')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _paymentConfigStream,
        builder: (context, configSnapshot) {
          if (configSnapshot.hasError) {
            return Center(
              child: Text(
                'Não foi possível carregar pagamentos: ${configSnapshot.error}',
              ),
            );
          }
          if (configSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final config =
              configSnapshot.data?.data() ?? const <String, dynamic>{};
          final provider = config['provider'] as String?;
          final providerReady = provider == 'pix_manual'
              ? (config['manualPixKey'] as String? ?? '').isNotEmpty
              : provider == 'mercadopago' &&
                    config['hasMercadoPagoToken'] == true;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              activeVip
                                  ? 'Assinatura VIP ativa'
                                  : 'Plano ${user.vipPlan.isEmpty ? 'Free' : VipPlansConfig.displayNameFor(user.vipPlan)}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          VipPlanBadge(
                            plan: user.vipPlan,
                            expiresAt: user.vipExpiresAt,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        activeVip
                            ? 'Válida até ${_formatDate(expiresAt)}'
                            : expiresAt != null &&
                                  VipPlansConfig.isPaidVipTier(user.vipPlan)
                            ? 'Expirada em ${_formatDate(expiresAt)}'
                            : 'Aproveite os recursos do plano gratuito.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_hasPendingMercadoPagoPayment)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'O plano e o cupom ficam bloqueados enquanto este Pix estiver pendente.',
                  ),
                ),
              for (final id in _planIds) _buildPlanCard(id, config),
              const SizedBox(height: 4),
              _buildCouponSection(),
              const SizedBox(height: 8),
              if (provider == 'pix_manual')
                const Text('Método de pagamento: Pix Manual')
              else if (provider == 'mercadopago')
                const Text('Método de pagamento: Mercado Pago')
              else
                const Text(
                  'O administrador ainda não configurou um método de pagamento.',
                ),
              if (_paymentError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _paymentError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !providerReady || !_canChangePlan
                    ? null
                    : () => _startSubscription(user, config),
                icon: _isSubmitting || _isRestoringOrder || _restoreScheduled
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.workspace_premium),
                label: Text(
                  _hasPendingMercadoPagoPayment
                      ? 'Pagamento pendente'
                      : activeVip
                      ? 'Renovar agora'
                      : 'Assinar agora',
                ),
              ),
              const SizedBox(height: 12),
              _buildManualRequests(user.uid),
              _buildMercadoPagoOrder(),
            ],
          );
        },
      ),
    );
  }
}

class _VipPaymentCountdown extends StatefulWidget {
  const _VipPaymentCountdown({
    required this.expiresAt,
    required this.onExpired,
    super.key,
  });

  final DateTime expiresAt;
  final VoidCallback onExpired;

  @override
  State<_VipPaymentCountdown> createState() => _VipPaymentCountdownState();
}

class _VipPaymentCountdownState extends State<_VipPaymentCountdown> {
  Timer? _timer;
  late Duration _remaining;
  bool _expirationNotified = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.expiresAt.difference(DateTime.now());
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      WidgetsBinding.instance.addPostFrameCallback((_) => _expire());
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _expire();
      return;
    }
    setState(() => _remaining = remaining);
  }

  void _expire() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _remaining = Duration.zero);
    if (_expirationNotified) return;
    _expirationNotified = true;
    widget.onExpired();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Tempo restante: $minutes:$seconds',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}
