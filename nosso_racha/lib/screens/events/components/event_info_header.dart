import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/event_model.dart';

class EventInfoHeader extends StatelessWidget {
  final EventModel event;
  final String selectedTab;
  final int countLine;
  final int countGk;
  final bool canViewFullList;
  final Function(String) onTabChanged;
  final bool isExpanded;
  final VoidCallback onToggleExpand; // <--- Callback para alterar o estado

  const EventInfoHeader({
    super.key,
    required this.event,
    required this.selectedTab,
    required this.countLine,
    required this.countGk,
    required this.canViewFullList,
    required this.onTabChanged,
    required this.isExpanded,
    required this.onToggleExpand, // <--- Recebe a função
  });

  bool _isChristmas(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor.value == 0xFFC62828;

  @override
  Widget build(BuildContext context) {
    final iconColor = _isChristmas(context) ? Colors.white70 : Colors.grey;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor,
      child: Column(
        children: [
          // --- ÁREA RETRÁTIL (Info do Evento) ---
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isExpanded
                ? Column(
                    children: [
                      _buildInfoRow(
                        context,
                        LucideIcons.calendar,
                        DateFormat(
                          'dd/MM/yyyy HH:mm',
                        ).format(event.startDateTime),
                      ),
                      const SizedBox(height: 4),
                      _buildInfoRow(context, Icons.sports, event.sportLabel),
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        context,
                        LucideIcons.mapPin,
                        event.location,
                      ),
                      if (event.locationNote?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          context,
                          Icons.speaker_notes_outlined,
                          event.locationNote!,
                        ),
                      ],
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        context,
                        LucideIcons.banknote,
                        "R\$ ${event.price.toStringAsFixed(2)}",
                      ),
                      if (event.sportHasGoalkeeper &&
                          event.externalGoalkeeperSlots > 0) ...[
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          context,
                          LucideIcons.shield,
                          '${event.externalGoalkeeperSlots} vaga(s) externa(s) para goleiro',
                        ),
                      ],
                      if (event.sportHasGoalkeeper &&
                          event.externalGoalkeeperSlots > 0 &&
                          event.goalkeeperAid > 0) ...[
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          context,
                          LucideIcons.shield,
                          'Ajuda de custo do goleiro: R\$ ${event.goalkeeperAid.toStringAsFixed(2)}',
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // --- ÁREA FIXA (Abas de Seleção) ---
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onTabChanged('line'),
                  child: _buildTabButton(
                    context,
                    "JOGADORES LINHA",
                    countLine,
                    event.maxLinePlayers,
                    Colors.green,
                    'line',
                  ),
                ),
              ),
              if (event.sportHasGoalkeeper) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => onTabChanged('goalkeeper'),
                    child: _buildTabButton(
                      context,
                      "GOLEIROS",
                      countGk,
                      event.maxGoalkeepers,
                      Colors.purple,
                      'goalkeeper',
                    ),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 4),

          // --- BOTÃO DE EXPANDIR/RECOLHER (POSICIONADO ABAIXO DAS ABAS) ---
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              height: 24,
              alignment: Alignment.center,
              child: Icon(
                isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 20,
                color: iconColor.withOpacity(0.5),
              ),
            ),
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    final color = _isChristmas(context) ? Colors.white : Colors.black87;
    final iconColor = _isChristmas(context) ? Colors.white70 : Colors.grey;

    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 16, color: color)),
      ],
    );
  }

  Widget _buildTabButton(
    BuildContext context,
    String label,
    int current,
    int max,
    MaterialColor color,
    String tabKey,
  ) {
    bool isSelected = selectedTab == tabKey;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = _isChristmas(context) ? Colors.white : Colors.grey;
    final selectedTextColor = isSelected
        ? (_isChristmas(context) ? Colors.white : color)
        : textColor;
    final countColor = _isChristmas(context)
        ? Colors.white70
        : (isSelected ? (isDark ? Colors.white : Colors.black) : Colors.grey);

    final bgColor = isSelected
        ? (_isChristmas(context) ? Colors.white24 : color[50])
        : (isDark ? Colors.grey[800] : null);
    final borderColor = isSelected
        ? (_isChristmas(context) ? Colors.white30 : color.withOpacity(0.5))
        : (isDark ? Colors.grey[700] : null);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: borderColor != null ? Border.all(color: borderColor) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: selectedTextColor,
            ),
          ),
          if (canViewFullList) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: max > 0 ? (current / max) : 0,
              backgroundColor: _isChristmas(context)
                  ? Colors.black26
                  : Colors.grey[200],
              color: _isChristmas(context) ? Colors.white : color,
              minHeight: 6,
            ),
            const SizedBox(height: 4),
            Text(
              "$current / $max",
              style: TextStyle(fontSize: 12, color: countColor),
            ),
          ] else ...[
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}
