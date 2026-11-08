import 'package:flutter/material.dart';

import '../models/venue_model.dart';
import '../services/venue_service.dart';

class VenueLocationField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<Venue> onVenueSelected;
  final String? Function(String?)? validator;

  const VenueLocationField({
    super.key,
    required this.controller,
    required this.onVenueSelected,
    this.validator,
  });

  @override
  State<VenueLocationField> createState() => _VenueLocationFieldState();
}

class _VenueLocationFieldState extends State<VenueLocationField> {
  final VenueService _venueService = VenueService();

  Future<void> _openVenues() async {
    final venue = await showModalBottomSheet<Venue>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VenueSelectionSheet(venueService: _venueService),
    );
    if (venue != null && mounted) widget.onVenueSelected(venue);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    readOnly: true,
    onTap: _openVenues,
    validator: widget.validator,
    decoration: const InputDecoration(
      labelText: 'Campo ou quadra',
      prefixIcon: Icon(Icons.location_on_outlined),
      suffixIcon: Icon(Icons.arrow_drop_down),
    ),
  );
}

class _VenueSelectionSheet extends StatefulWidget {
  final VenueService venueService;

  const _VenueSelectionSheet({required this.venueService});

  @override
  State<_VenueSelectionSheet> createState() => _VenueSelectionSheetState();
}

class _VenueSelectionSheetState extends State<_VenueSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  late final Future<List<Venue>> _venuesFuture = widget.venueService
      .getApprovedVenues();
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestVenue() async {
    final venue = await showDialog<Venue>(
      context: context,
      builder: (_) => _VenueRequestDialog(venueService: widget.venueService),
    );
    if (venue != null && mounted) {
      Navigator.of(context).pop(venue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Escolha o local',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar campo ou quadra',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _searchTerm = value.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Venue>>(
                  future: _venuesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Não foi possível carregar os locais: ${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final venues = (snapshot.data ?? const <Venue>[]).where((
                      venue,
                    ) {
                      final address =
                          '${venue.address ?? ''} ${venue.street ?? ''} '
                          '${venue.neighborhood ?? ''} ${venue.city ?? ''}';
                      return '${venue.name} $address'.toLowerCase().contains(
                        _searchTerm,
                      );
                    }).toList();
                    if (venues.isEmpty) {
                      return Center(
                        child: Text(
                          snapshot.data?.isEmpty ?? true
                              ? 'Ainda não há locais aprovados.'
                              : 'Nenhum local encontrado.',
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: venues.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final venue = venues[index];
                        final address = [
                          venue.address ?? venue.street,
                          venue.neighborhood,
                          venue.city,
                          venue.state,
                        ].whereType<String>().join(', ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.sports_soccer_outlined),
                          title: Text(venue.name),
                          subtitle: address.isEmpty ? null : Text(address),
                          onTap: () => Navigator.of(context).pop(venue),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _requestVenue,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Solicitar Cadastro de Novo Campo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VenueRequestDialog extends StatefulWidget {
  final VenueService venueService;

  const _VenueRequestDialog({required this.venueService});

  @override
  State<_VenueRequestDialog> createState() => _VenueRequestDialogState();
}

class _VenueRequestDialogState extends State<_VenueRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    try {
      await widget.venueService.requestVenue(name: name, address: address);
      if (mounted) {
        Navigator.of(
          context,
        ).pop(Venue(name: name, address: address, street: address));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Não foi possível enviar a solicitação: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Solicitar novo local'),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nome do campo'),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Informe o nome do local.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                textCapitalization: TextCapitalization.words,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Endereço completo',
                  alignLabelWithHint: true,
                ),
                validator: (value) => value == null || value.trim().length < 5
                    ? 'Informe o endereço completo.'
                    : null,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Enviar solicitação'),
      ),
    ],
  );
}
