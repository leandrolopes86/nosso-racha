import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/event_model.dart';
import '../../../models/user_model.dart';
import '../../../services/payment_gateway_service.dart';
import '../../../services/payment/payment_polling_policy.dart';

class PaymentModal extends StatefulWidget {
  final EventModel event;
  final UserModel user;

  const PaymentModal({super.key, required this.event, required this.user});

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  bool _isLoading = true;
  bool _isAutoPix = false;

  String _manualPixKey = "";
  String _manualBeneficiary = "";
  String _manualBankName = "";

  Map<String, dynamic>? _mpData;
  String? _errorMsg;
  bool _isSandbox = false;

  Timer? _pollingTimer;

  // Controle de Expiração
  DateTime? _expirationDate;
  bool _isExpired = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final paymentService = Provider.of<PaymentGatewayService>(
      context,
      listen: false,
    );

    try {
      await paymentService.loadConfig(groupId: widget.event.groupId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg =
              'Não foi possível carregar as configurações de pagamento. '
              'Tente novamente mais tarde.';
          _isLoading = false;
        });
      }
      return;
    }

    if (!mounted) return;
    final config = paymentService.config;

    if (config != null && config.accessToken.startsWith("TEST")) {
      _isSandbox = true;
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('pending_payments')
          .doc(widget.user.uid);

      final doc = await docRef.get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        bool isExpiredLocal = false;

        if (data['expiration_date'] != null) {
          final expiration = DateTime.parse(data['expiration_date']);
          if (DateTime.now().isAfter(expiration)) {
            isExpiredLocal = true;
            await docRef.delete();
          } else {
            _expirationDate = expiration;
          }
        }

        if (!isExpiredLocal &&
            mounted &&
            PaymentPollingPolicy.shouldPoll(data)) {
          setState(() {
            _mpData = data;
            _isAutoPix = true;
            _isLoading = false;
            _isExpired = false;
          });
          _startPolling();
          return;
        }
      }
    } catch (e) {
      print("Erro ao recuperar PIX pendente: $e");
    }

    if (mounted) {
      if (config != null &&
          config.provider == 'mercadopago' &&
          config.isActive) {
        setState(() {
          _isAutoPix = true;
          _isLoading = false;
          _isExpired = false;
        });
      } else {
        setState(() {
          _isAutoPix = false;
          _manualPixKey = config?.manualPixKey ?? "Chave não configurada";
          _manualBeneficiary = config?.manualBeneficiary ?? "";
          _manualBankName = config?.manualBankName ?? "";
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generatePix() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
      _isExpired = false;
    });
    final paymentService = Provider.of<PaymentGatewayService>(
      context,
      listen: false,
    );

    try {
      final result = await paymentService.generatePix(
        event: widget.event,
        payer: widget.user,
      );

      if (result['expiration_date'] != null) {
        _expirationDate = DateTime.parse(result['expiration_date']);
      }

      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .collection('pending_payments')
          .doc(widget.user.uid)
          .set(result);

      final eventRef = FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(eventRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>;
        List<dynamic> participantsRaw = data['participants'] ?? [];

        int index = participantsRaw.indexWhere(
          (p) =>
              p['uid'] == widget.user.uid || p['user_uid'] == widget.user.uid,
        );

        if (index != -1) {
          participantsRaw[index]['payment_gateway_id'] = result['payment_id']
              .toString();
          transaction.update(eventRef, {'participants': participantsRaw});
        }
      });

      if (mounted) {
        setState(() {
          _mpData = result;
          _isLoading = false;
        });
        if (PaymentPollingPolicy.shouldPoll(result)) _startPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _startPolling() {
    if (_pollingTimer != null) return;
    if (_mpData == null || !PaymentPollingPolicy.shouldPoll(_mpData!)) return;
    _pollingTimer = Timer.periodic(PaymentPollingPolicy.interval, (
      timer,
    ) async {
      if (_mpData == null || !PaymentPollingPolicy.shouldPoll(_mpData!)) {
        timer.cancel();
        return;
      }
      if (_isCheckingPaymentStatus) return;
      _isCheckingPaymentStatus = true;
      if (_mpData!['payment_id'] == null) {
        timer.cancel();
        _isCheckingPaymentStatus = false;
        return;
      }
      final paymentId = _mpData!['payment_id'].toString();

      if (!mounted) {
        timer.cancel();
        _isCheckingPaymentStatus = false;
        return;
      }

      try {
        final paymentService = Provider.of<PaymentGatewayService>(
          context,
          listen: false,
        );
        final status = await paymentService.checkPaymentStatus(paymentId);
        if (PaymentPollingPolicy.isTerminalStatus(status)) timer.cancel();
      } finally {
        _isCheckingPaymentStatus = false;
      }
    });
  }

  bool _isCheckingPaymentStatus = false;

  void _handleExpiration() {
    _pollingTimer?.cancel();
    if (mounted) {
      setState(() {
        _isExpired = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final isChristmas = Theme.of(context).cardTheme.color?.value == 0xFF2E7D32;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('events')
          .doc(widget.event.id)
          .snapshots(),
      builder: (context, snapshot) {
        bool isUserPaid = false;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final List<dynamic> participants = data['participants'] ?? [];

          final participantData = participants.firstWhere(
            (p) =>
                (p['uid'] == widget.user.uid ||
                p['user_uid'] == widget.user.uid),
            orElse: () => null,
          );

          if (participantData != null &&
              participantData['payment_status'] == 'paid') {
            isUserPaid = true;
          }
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isUserPaid) ...[
                    Icon(
                      LucideIcons.checkCircle,
                      size: 64,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Pagamento Confirmado!",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Seu status já foi atualizado na lista.",
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("FECHAR"),
                      ),
                    ),
                  ] else ...[
                    if (_isExpired)
                      Icon(LucideIcons.timerOff, size: 48, color: Colors.orange)
                    else
                      Icon(LucideIcons.qrCode, size: 48, color: Colors.green),

                    const SizedBox(height: 16),

                    Text(
                      _isExpired ? "Código Expirado" : "Pagamento via PIX",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_isSandbox &&
                        _isAutoPix &&
                        !_isExpired &&
                        _mpData != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              LucideIcons.alertTriangle,
                              color: Colors.amber,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "MODO TESTE: Use uma conta de teste do Mercado Pago.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.brown,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),

                    if (!_isLoading && _errorMsg != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.red[50],
                        child: Column(
                          children: [
                            Text(
                              "Erro: $_errorMsg",
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () => setState(() => _errorMsg = null),
                              child: const Text("Tentar Novamente"),
                            ),
                          ],
                        ),
                      ),

                    // MANUAL
                    if (!_isLoading && !_isAutoPix && _errorMsg == null) ...[
                      const Text(
                        "Copie a chave abaixo e realize o pagamento no seu banco.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      PixCopyBox(
                        pixKey: _manualPixKey,
                        beneficiary: _manualBeneficiary,
                        bankName: _manualBankName,
                      ),
                    ],

                    // AUTOMÁTICO (Mercado Pago)
                    if (!_isLoading && _isAutoPix && _errorMsg == null) ...[
                      if (_isExpired) ...[
                        const Text(
                          "O tempo para pagamento acabou.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _generatePix,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                            icon: Icon(LucideIcons.refreshCw),
                            label: const Text("GERAR NOVO CÓDIGO"),
                          ),
                        ),
                      ] else if (_mpData == null) ...[
                        const Text(
                          "Clique abaixo para gerar um QR Code exclusivo.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _generatePix,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[800],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                            ),
                            icon: Icon(LucideIcons.zap),
                            label: const Text("GERAR PIX AGORA"),
                          ),
                        ),
                      ] else ...[
                        // --- CONTADOR ISOLADO PARA EVITAR PISCAR O QR CODE ---
                        if (_expirationDate != null)
                          PaymentTimer(
                            expirationDate: _expirationDate!,
                            onExpire: _handleExpiration,
                          ),

                        const SizedBox(height: 16),

                        if (_mpData!['qr_code_base64'] != null)
                          Image.memory(
                            base64Decode(_mpData!['qr_code_base64']),
                            height: 200,
                            width: 200,
                          ),

                        const SizedBox(height: 16),
                        const Text(
                          "Escaneie o QR Code ou copie a chave:",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),

                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Aguardando confirmação...",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        PixCopyBox(
                          pixKey: _mpData!['qr_code'],
                          beneficiary: "Mercado Pago",
                          bankName: "",
                          isChristmas: isChristmas,
                        ),
                      ],
                    ],

                    const SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// --- WIDGET ISOLADO DO TIMER ---
class PaymentTimer extends StatefulWidget {
  final DateTime expirationDate;
  final VoidCallback onExpire;

  const PaymentTimer({
    super.key,
    required this.expirationDate,
    required this.onExpire,
  });

  @override
  State<PaymentTimer> createState() => _PaymentTimerState();
}

class _PaymentTimerState extends State<PaymentTimer> {
  late Timer _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startLocalTimer();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _startLocalTimer() {
    // Primeira atualização imediata
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    if (now.isAfter(widget.expirationDate)) {
      _timer.cancel();
      widget.onExpire(); // Notifica o pai para mudar o estado
    } else {
      setState(() {
        _timeLeft = widget.expirationDate.difference(now);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _timeLeft.inMinutes.toString().padLeft(2, '0');
    final seconds = (_timeLeft.inSeconds % 60).toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.timer, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Text(
            "Expira em: $minutes:$seconds",
            style: const TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class PixCopyBox extends StatefulWidget {
  final String pixKey;
  final String beneficiary;
  final String bankName;
  final bool isChristmas;

  const PixCopyBox({
    super.key,
    required this.pixKey,
    required this.beneficiary,
    this.bankName = '',
    this.isChristmas = false,
  });

  @override
  State<PixCopyBox> createState() => _PixCopyBoxState();
}

class _PixCopyBoxState extends State<PixCopyBox> {
  bool _isCopied = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: widget.isChristmas ? Colors.white24 : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              SelectableText(
                widget.pixKey,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.beneficiary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.beneficiary,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
              if (widget.bankName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  "Banco: ${widget.bankName}",
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.pixKey));
              setState(() => _isCopied = true);

              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Chave PIX copiada!"),
                  backgroundColor: Colors.green,
                ),
              );

              Future.delayed(const Duration(seconds: 3), () {
                if (mounted) setState(() => _isCopied = false);
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _isCopied ? Colors.green[700] : null,
            ),
            icon: Icon(_isCopied ? LucideIcons.check : LucideIcons.copy),
            label: Text(_isCopied ? "COPIADO!" : "COPIAR CHAVE"),
          ),
        ),
      ],
    );
  }
}
