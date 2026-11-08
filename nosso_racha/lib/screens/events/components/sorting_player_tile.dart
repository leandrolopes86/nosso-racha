import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/participant_model.dart';

class SortingPlayerTile extends StatelessWidget {
  final ParticipantModel player;
  final bool isEditable;
  final bool isTeamView;
  final double? rating;
  final int tier;
  final bool showRating;
  final VoidCallback? onOptionsTap;

  const SortingPlayerTile({
    super.key,
    required this.player,
    required this.isEditable,
    this.isTeamView = false,
    this.rating,
    this.tier = 0,
    this.showRating = false,
    this.onOptionsTap,
  });

  bool _isChristmasTheme(BuildContext context) {
    return Theme.of(context).cardTheme.color?.value == 0xFF2E7D32;
  }

  // --- FUNÇÃO DE FORMATAÇÃO (OVR 1-99) ---
  String _getFormattedRating() {
    if (rating == null || rating! <= 0) return '-';
    // Removemos a lógica de multiplicar por 10.
    // Retornamos o valor exatamente como está no banco de dados.
    return rating!.toInt().toString();
  }

  // --- O WIDGET FLUTUANTE DURANTE O ARRASTO ---
  Widget _buildFeedback(BuildContext context) {
    return Material(
      elevation: 6,
      color: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
        ),
        child: Text(player.nickname.isNotEmpty ? player.nickname : player.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  // --- O ÍCONE ISOLADO PARA ARRASTE ---
  Widget _buildDragHandle(BuildContext context, Color iconColor) {
    if (!isEditable) {
      return Icon(LucideIcons.gripVertical, size: 20, color: iconColor);
    }

    // O Draggable agora fica SOMENTE no ícone!
    return Draggable<ParticipantModel>(
      data: player,
      // RESOLUÇÃO DEFINITIVA: FractionalTranslation desenha o card para a ESQUERDA do seu dedo!
      feedback: FractionalTranslation(
        translation: const Offset(-0.85,
            -0.5), // Empurra 85% do card para a esquerda e centraliza no dedo (Y)
        child: _buildFeedback(context),
      ),
      feedbackOffset:
          Offset.zero, // Zeramos o offset nativo para evitar conflito
      childWhenDragging: Opacity(
          opacity: 0.3,
          child: Icon(LucideIcons.gripVertical, size: 24, color: iconColor)),
      // Aumentei o padding para ficar mais fácil acertar o dedo no celular
      child: Padding(
        padding: const EdgeInsets.only(
            left: 12.0, right: 4.0, top: 4.0, bottom: 4.0),
        child: Icon(LucideIcons.gripVertical, size: 24, color: iconColor),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Agora retornamos a linha direto (sem o LongPressDraggable englobando tudo)
    return isTeamView ? _buildTeamRow(context) : _buildSimpleRow(context);
  }

  Widget _buildSimpleRow(BuildContext context) {
    final displayName =
        player.nickname.isNotEmpty ? player.nickname : player.name;
    final textColor = Colors.black;
    final isChristmas = _isChristmasTheme(context);
    final iconColor = isChristmas ? Colors.white70 : textColor.withOpacity(0.7);
    final textStyleColor = isChristmas ? Colors.white : textColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color?.withOpacity(0.9) ?? Colors.white,
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.user, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
              child:
                  Text(displayName, style: TextStyle(color: textStyleColor))),

          if (showRating && rating != null && rating! > 0)
            Text(_getFormattedRating(),
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.amber)),

          const SizedBox(width: 8),

          // Botão das setas azuis (Mover via Popup)
          if (isEditable && onOptionsTap != null)
            GestureDetector(
              onTap: onOptionsTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Icon(LucideIcons.arrowRightLeft,
                    size: 18, color: Colors.blue),
              ),
            ),

          // Ícone isolado de arrasto
          _buildDragHandle(context, iconColor),
        ],
      ),
    );
  }

  Widget _buildTeamRow(BuildContext context) {
    final bool isGoleiro = player.roleInMatch == 'goalkeeper';
    final displayName =
        player.nickname.isNotEmpty ? player.nickname : player.name;
    final textColor = Colors.black;
    final isChristmas = _isChristmasTheme(context);
    final iconColor = isGoleiro
        ? (isChristmas ? Colors.amberAccent : Colors.purple)
        : (isChristmas ? Colors.white70 : textColor.withOpacity(0.7));
    final tierTextColor = isChristmas ? Colors.white70 : Colors.grey;
    final nameColor = isChristmas ? Colors.white : textColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color?.withOpacity(0.9) ?? Colors.white,
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(isGoleiro ? LucideIcons.shield : LucideIcons.user,
              size: 16, color: iconColor),
          const SizedBox(width: 8),
          if (tier > 0) ...[
            Text("($tier)",
                style: TextStyle(
                    fontSize: 12,
                    color: tierTextColor,
                    fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(displayName,
                style: TextStyle(fontSize: 16, color: nameColor),
                overflow: TextOverflow.ellipsis),
          ),

          // Botão das setas azuis (Mover via Popup)
          if (isEditable && onOptionsTap != null)
            GestureDetector(
              onTap: onOptionsTap,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: Icon(LucideIcons.arrowRightLeft,
                    size: 18, color: Colors.blue),
              ),
            ),

          // Ícone isolado de arrasto
          _buildDragHandle(context, iconColor),
        ],
      ),
    );
  }
}
