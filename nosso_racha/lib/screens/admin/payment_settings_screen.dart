import 'dart:convert'; // Para base64Decode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para Clipboard
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../services/payment_gateway_service.dart';
import '../../services/auth_service.dart';
import '../../models/payment_config_model.dart';
import '../../models/event_model.dart'; // Necessário para criar evento dummy

class PaymentSettingsScreen extends StatefulWidget {
  final String groupId;

  const PaymentSettingsScreen({super.key, required this.groupId});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  String _selectedProvider = 'manual';

  final _mpAccessTokenController = TextEditingController();
  final _mpPublicKeyController = TextEditingController();

  final _manualKeyController = TextEditingController();
  final _manualBeneficiaryController = TextEditingController();
  final _manualBankNameController = TextEditingController();

  bool _isLoadingData = true;
  bool _isTesting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _fetchSettings();
  }

  Future<void> _fetchSettings() async {
    final service = Provider.of<PaymentGatewayService>(context, listen: false);

    try {
      await service.loadConfig(groupId: widget.groupId);
      if (mounted) {
        setState(() {
          if (service.config != null) {
            _selectedProvider = service.config!.provider;
            _mpAccessTokenController.text = service.config!.accessToken;
            _mpPublicKeyController.text = service.config!.publicKey;
            _manualKeyController.text = service.config!.manualPixKey;
            _manualBeneficiaryController.text =
                service.config!.manualBeneficiary;
            _manualBankNameController.text = service.config!.manualBankName;
          }
          _isLoadingData = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error.toString();
          _isLoadingData = false;
        });
      }
    }
  }

  // --- FUNÇÃO DE TESTE ---
  Future<void> _testConfiguration() async {
    setState(() => _isTesting = true);

    final service = Provider.of<PaymentGatewayService>(context, listen: false);
    final user = Provider.of<AuthService>(context, listen: false).currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erro: Usuário não logado.")),
      );
      setState(() => _isTesting = false);
      return;
    }

    final tempConfig = PaymentConfigModel(
      provider: _selectedProvider,
      isActive: true,
      accessToken: _mpAccessTokenController.text.trim(),
      publicKey: _mpPublicKeyController.text.trim(),
      manualPixKey: _manualKeyController.text.trim(),
      manualBeneficiary: _manualBeneficiaryController.text.trim(),
      manualBankName: _manualBankNameController.text.trim(),
    );

    try {
      if (_selectedProvider == 'mercadopago') {
        final dummyEvent = EventModel(
          id: 'test_event',
          title: 'Teste de Configuração',
          location: 'Teste',
          price: 1.00,
          startDateTime: DateTime.now(),
          endDateTime: DateTime.now().add(const Duration(hours: 1)),
          cancellationDeadline: DateTime.now(),
          votingOpensAt: DateTime.now(),
          numberOfTeams: 2,
          linePlayersPerTeam: 5,
          status: 'scheduled',
          createdBy: user.uid,
        );

        // CORREÇÃO AQUI: Mudamos de generateMercadoPagoPix para generatePix
        final result = await service.generatePix(
          event: dummyEvent,
          payer: user,
          configOverride: tempConfig,
        );

        if (mounted) _showTestResultDialog(result);
      } else {
        _showManualTestDialog(tempConfig);
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = e.toString();
        String helpText = "";

        if (errorMessage.contains("Failed to fetch") ||
            errorMessage.contains("XMLHttpRequest")) {
          helpText =
              "⚠️ NOTA: Se você está testando na WEB, este erro é esperado (Bloqueio de segurança CORS do Mercado Pago). Por favor, teste no Android ou Windows.";
        }

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(
              "Falha no Teste",
              style: TextStyle(color: Colors.red),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (helpText.isNotEmpty) ...[
                    Text(
                      helpText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 12),
                  ],
                  const Text("Detalhes do erro técnico:"),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey[400]!),
                    ),
                    child: SelectableText(
                      errorMessage,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: Icon(LucideIcons.copy, size: 16),
                label: const Text("COPIAR ERRO"),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: e.toString()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Log de erro copiado!")),
                  );
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK"),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  void _showTestResultDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sucesso! PIX Gerado"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.checkCircle, color: Colors.green, size: 48),
              const SizedBox(height: 16),
              const Text(
                "A comunicação com o Mercado Pago funcionou. Aqui está o QR Code de teste de R\$ 1,00:",
              ),
              const SizedBox(height: 16),
              if (data['qr_code_base64'] != null)
                Image.memory(
                  base64Decode(data['qr_code_base64']),
                  height: 150,
                  width: 150,
                ),
              const SizedBox(height: 16),
              const Text(
                "Copia e Cola:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey[200],
                child: SelectableText(
                  data['qr_code'] ?? '',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("FECHAR"),
          ),
        ],
      ),
    );
  }

  void _showManualTestDialog(PaymentConfigModel config) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Teste Manual"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Assim que os dados aparecerão para o atleta:"),
            const SizedBox(height: 16),
            Text(
              "Chave: ${config.manualPixKey}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text("Nome: ${config.manualBeneficiary}"),
            if (config.manualBankName.isNotEmpty)
              Text(
                "Banco: ${config.manualBankName}",
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _save() async {
    final service = Provider.of<PaymentGatewayService>(context, listen: false);

    final newConfig = PaymentConfigModel(
      provider: _selectedProvider,
      isActive: true,
      accessToken: _mpAccessTokenController.text.trim(),
      publicKey: _mpPublicKeyController.text.trim(),
      manualPixKey: _manualKeyController.text.trim(),
      manualBeneficiary: _manualBeneficiaryController.text.trim(),
      manualBankName: _manualBankNameController.text.trim(),
    );

    try {
      await service.saveConfig(newConfig, groupId: widget.groupId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Configurações de pagamento salvas!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = Provider.of<PaymentGatewayService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Recebimentos e pagamentos")),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Text('Falha ao carregar as configurações: $_loadError'),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    "Selecione o método de recebimento:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProvider,
                    decoration: const InputDecoration(
                      labelText: "Provedor Ativo",
                      prefixIcon: Icon(LucideIcons.creditCard),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'manual',
                        child: Text("Manual (Chave PIX Estática)"),
                      ),
                      DropdownMenuItem(
                        value: 'mercadopago',
                        child: Text("Mercado Pago (Automático)"),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedProvider = v!),
                  ),
                  const SizedBox(height: 24),
                  if (_selectedProvider == 'mercadopago') ...[
                    Card(
                      color: Colors.blue[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.blue),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.zap, color: Colors.blue),
                                const SizedBox(width: 8),
                                Text(
                                  "Credenciais Mercado Pago",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[900],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Acesse: https://www.mercadopago.com.br/developers/panel",
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _mpAccessTokenController,
                              decoration: const InputDecoration(
                                labelText: "Access Token (Produção)",
                                prefixIcon: Icon(LucideIcons.key),
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _mpPublicKeyController,
                              decoration: const InputDecoration(
                                labelText: "Public Key (Opcional)",
                                prefixIcon: Icon(LucideIcons.lock),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_selectedProvider == 'manual') ...[
                    Card(
                      color: Colors.green[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Colors.green),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(LucideIcons.qrCode, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(
                                  "Dados do PIX do grupo",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[900],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _manualKeyController,
                              decoration: const InputDecoration(
                                labelText: "Chave PIX do grupo",
                                prefixIcon: Icon(LucideIcons.key),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _manualBeneficiaryController,
                              decoration: const InputDecoration(
                                labelText: "Nome do Beneficiário",
                                prefixIcon: Icon(LucideIcons.user),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _manualBankNameController,
                              decoration: const InputDecoration(
                                labelText: "Nome do Banco / Instituição",
                                prefixIcon: Icon(LucideIcons.landmark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isTesting ? null : _testConfiguration,
                          icon: _isTesting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(LucideIcons.testTube2),
                          label: const Text("TESTAR GERAÇÃO"),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: service.isLoading ? null : _save,
                          icon: Icon(LucideIcons.save),
                          label: service.isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text("SALVAR"),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
