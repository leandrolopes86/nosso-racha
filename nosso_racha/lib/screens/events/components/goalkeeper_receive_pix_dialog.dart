import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../utils/pix_payload.dart';

Future<void> showGoalkeeperReceivePixDialog({
  required BuildContext context,
  required String pixKey,
  required String goalkeeperName,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _GoalkeeperReceivePixDialog(
      pixKey: pixKey,
      goalkeeperName: goalkeeperName,
    ),
  );
}

class _GoalkeeperReceivePixDialog extends StatefulWidget {
  final String pixKey;
  final String goalkeeperName;

  const _GoalkeeperReceivePixDialog({
    required this.pixKey,
    required this.goalkeeperName,
  });

  @override
  State<_GoalkeeperReceivePixDialog> createState() =>
      _GoalkeeperReceivePixDialogState();
}

class _GoalkeeperReceivePixDialogState
    extends State<_GoalkeeperReceivePixDialog> {
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
    final normalizedAmount = _amountController.text.trim().replaceAll(',', '.');
    final amount = normalizedAmount.isEmpty
        ? null
        : double.tryParse(normalizedAmount);
    final hasInvalidAmount =
        normalizedAmount.isNotEmpty &&
        (amount == null || !amount.isFinite || amount <= 0);
    final payload = hasInvalidAmount
        ? null
        : PixPayload.build(
            pixKey: widget.pixKey,
            receiverName: widget.goalkeeperName,
            amount: amount,
          );
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AlertDialog(
      title: const Text('QR Pix para receber'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width < 400
              ? MediaQuery.sizeOf(context).width - 80
              : 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.goalkeeperName,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Peça ao organizador para escanear este código. Sem valor '
                'fixo, ele poderá informar o valor combinado no aplicativo do banco.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Valor combinado (opcional)',
                  helperText: 'Deixe em branco para não fixar o valor no QR.',
                  errorText: hasInvalidAmount
                      ? 'Informe um valor maior que zero.'
                      : null,
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
                ),
              const SizedBox(height: 8),
              Text(
                amount == null || hasInvalidAmount
                    ? 'Pix sem valor definido'
                    : currency.format(amount),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(widget.pixKey, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.pixKey));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Chave Pix copiada para a área de transferência.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar chave Pix'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
