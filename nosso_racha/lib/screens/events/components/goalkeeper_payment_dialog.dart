import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../models/event_model.dart';
import '../../../models/participant_model.dart';
import '../../../models/user_model.dart';
import '../../../services/event_service.dart';
import '../../../utils/pix_payload.dart';

Future<void> showGoalkeeperPaymentDialog({
  required BuildContext context,
  required EventModel event,
  required ParticipantModel goalkeeper,
  required UserModel organizer,
  required EventService eventService,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _GoalkeeperPaymentDialog(
      event: event,
      goalkeeper: goalkeeper,
      organizer: organizer,
      eventService: eventService,
    ),
  );
}

class _GoalkeeperPaymentDialog extends StatefulWidget {
  final EventModel event;
  final ParticipantModel goalkeeper;
  final UserModel organizer;
  final EventService eventService;

  const _GoalkeeperPaymentDialog({
    required this.event,
    required this.goalkeeper,
    required this.organizer,
    required this.eventService,
  });

  @override
  State<_GoalkeeperPaymentDialog> createState() =>
      _GoalkeeperPaymentDialogState();
}

class _GoalkeeperPaymentDialogState extends State<_GoalkeeperPaymentDialog> {
  bool _isSubmitting = false;
  bool _copied = false;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final key = widget.goalkeeper.pixKey.trim();
    final amount = _parseAmount(_amountController.text);
    final canPay =
        widget.goalkeeper.goaliePaymentStatus == 'none' &&
        amount != null &&
        amount > 0;
    final payload = key.isEmpty || amount == null || amount <= 0
        ? null
        : PixPayload.build(
            pixKey: key,
            receiverName: widget.goalkeeper.name,
            amount: amount,
          );
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AlertDialog(
      title: const Text('Pagamento opcional do goleiro'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < 420
              ? MediaQuery.sizeOf(context).width - 80
              : 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.goalkeeper.nickname.isNotEmpty
                    ? widget.goalkeeper.nickname
                    : widget.goalkeeper.name,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Defina o valor combinado com o goleiro. Deixe em branco ou '
                'feche o modal se não houver pagamento acordado.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Valor combinado (R\$)',
                  helperText: widget.event.goalkeeperAid > 0
                      ? 'Sugestão negociável: ${currency.format(widget.event.goalkeeperAid)}'
                      : 'Opcional; informe somente se houver valor acordado.',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (payload != null)
                QrImageView(
                  data: payload,
                  size: MediaQuery.sizeOf(context).width < 380
                      ? MediaQuery.sizeOf(context).width - 160
                      : 220,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                  backgroundColor: Colors.white,
                )
              else
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    key.isEmpty
                        ? 'O goleiro não cadastrou chave Pix. Combine outro '
                              'meio de pagamento antes de marcar como realizado.'
                        : 'Informe um valor acordado maior que zero para gerar o Pix.',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 8),
              SelectableText(
                key.isEmpty ? 'Chave Pix não cadastrada (opcional)' : key,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: key.isEmpty ? null : _copyPixKey,
                icon: Icon(_copied ? Icons.check : Icons.copy),
                label: Text(_copied ? 'Chave copiada' : 'Copiar Chave Pix'),
              ),
              const SizedBox(height: 8),
              _paymentStatus(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
        if (widget.goalkeeper.goaliePaymentStatus == 'none')
          FilledButton(
            onPressed: canPay && !_isSubmitting ? _markAsPaid : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Marcar pagamento realizado'),
          ),
      ],
    );
  }

  Widget _paymentStatus() {
    switch (widget.goalkeeper.goaliePaymentStatus) {
      case 'pending_confirmation':
        return const Text(
          'Pagamento pendente de confirmação pelo goleiro.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        );
      case 'confirmed':
        return const Text(
          'Pagamento confirmado pelo goleiro.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        );
      default:
        if (_parseAmount(_amountController.text) == null ||
            _parseAmount(_amountController.text)! <= 0) {
          return const Text(
            'Nenhum pagamento é obrigatório. Só registre se houver valor acordado.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey),
          );
        }
        return const Text(
          'Após realizar o pagamento acordado, marque-o para pedir a confirmação.',
          textAlign: TextAlign.center,
        );
    }
  }

  Future<void> _copyPixKey() async {
    await Clipboard.setData(ClipboardData(text: widget.goalkeeper.pixKey));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chave Pix copiada para a área de transferência.'),
      ),
    );
  }

  Future<void> _markAsPaid() async {
    setState(() => _isSubmitting = true);
    try {
      await widget.eventService.markGoalkeeperPaymentPending(
        eventId: widget.event.id!,
        goalkeeperUid: widget.goalkeeper.uid,
        organizer: widget.organizer,
        amount: _parseAmount(_amountController.text)!,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível registrar o pagamento: $error'),
        ),
      );
    }
  }

  double? _parseAmount(String value) {
    final normalized = value.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final amount = double.tryParse(normalized);
    return amount != null && amount.isFinite ? amount : null;
  }
}
