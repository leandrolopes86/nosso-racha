import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/event_model.dart';
import '../../../models/participant_model.dart';
import '../../../models/user_model.dart';
import '../../../services/event_service.dart';

class ParticipantList extends StatelessWidget {
  final List<ParticipantModel> participants;
  final EventModel event;
  final UserModel currentUser;
  final String eventId;
  final EventService eventService;
  final bool isListLocked;
  final bool isDark;

  final Function(ParticipantModel) onPaymentToggle;
  final Function(ParticipantModel) onGoalkeeperPayment;
  final Function(ParticipantModel) onRemovePlayer;
  final Function(int, int) onReorder;

  const ParticipantList({
    super.key,
    required this.participants,
    required this.event,
    required this.currentUser,
    required this.eventId,
    required this.eventService,
    required this.isListLocked,
    required this.isDark,
    required this.onPaymentToggle,
    required this.onGoalkeeperPayment,
    required this.onRemovePlayer,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    if (currentUser.canReorderList) {
      return ReorderableListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: participants.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final p = participants[index];
          return KeyedSubtree(
            key: ValueKey(p.uid),
            child: _buildListItem(context, p, index),
          );
        },
      );
    } else {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: participants.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) =>
            _buildListItem(context, participants[index], index),
      );
    }
  }

  Widget _buildListItem(BuildContext context, ParticipantModel p, int index) {
    final canReadPaymentDetails =
        p.uid == currentUser.uid ||
        currentUser.isStaff ||
        currentUser.canMarkPaid ||
        currentUser.uid == event.createdBy;
    if (p.roleInMatch != 'goalkeeper' || !canReadPaymentDetails) {
      return _buildListItemContent(context, p, index);
    }

    return StreamBuilder(
      stream: eventService.getGoaliePaymentStream(eventId, p.uid),
      builder: (context, snapshot) {
        final payment = snapshot.data?.data();
        if (payment == null) {
          return _buildListItemContent(context, p, index);
        }
        return _buildListItemContent(
          context,
          p.copyWith(
            goaliePaymentStatus:
                payment['goalie_payment_status'] as String? ?? 'none',
            pixKey: payment['pix_key'] as String? ?? '',
          ),
          index,
        );
      },
    );
  }

  Widget _buildListItemContent(
    BuildContext context,
    ParticipantModel p,
    int index,
  ) {
    final capacity = p.roleInMatch == 'goalkeeper'
        ? event.maxGoalkeepers
        : event.maxLinePlayers;
    final isSuplente = index >= capacity;
    final pPaid = p.paymentStatus == 'paid';
    final displayName = p.nickname.isNotEmpty ? p.nickname : p.name;
    final registeredDate = DateFormat('dd/MM HH:mm').format(p.registeredAt);
    final canSeeDate = currentUser.isStaff;

    // Cores (Adapte conforme necessidade ou passe via parametro)
    final cardColor =
        Theme.of(context).cardTheme.color ?? Theme.of(context).cardColor;
    final isDarkCard =
        ThemeData.estimateBrightnessForColor(cardColor) == Brightness.dark;

    Color rankBgColor;
    Color rankTextColor;

    if (isDarkCard) {
      if (isSuplente) {
        rankBgColor = Colors.black26;
        rankTextColor = Colors.amberAccent;
      } else if (p.roleInMatch == 'goalkeeper') {
        rankBgColor = Colors.white24;
        rankTextColor = Colors.white;
      } else {
        rankBgColor = Colors.green[900]!.withOpacity(0.5);
        rankTextColor = Colors.white;
      }
    } else {
      rankBgColor = isSuplente
          ? Colors.orange.withOpacity(0.2)
          : (p.roleInMatch == 'goalkeeper'
                ? Colors.purple.withOpacity(0.2)
                : Colors.green.withOpacity(0.2));
      rankTextColor = isSuplente
          ? Colors.orange
          : (p.roleInMatch == 'goalkeeper' ? Colors.purple : Colors.green);
    }

    final textColor = isDarkCard ? Colors.white : Colors.black87;
    final subColor = isDarkCard ? Colors.white70 : Colors.green;

    Widget? subtitleWidget;
    if (isSuplente && !kIsWeb) {
      // Simplificando isMobile
      List<Widget> subColumn = [
        Text(
          "Suplente",
          style: TextStyle(
            color: isDarkCard ? Colors.amberAccent : Colors.orange,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ];
      if (canSeeDate)
        subColumn.add(
          Text(registeredDate, style: TextStyle(fontSize: 12, color: subColor)),
        );
      subtitleWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: subColumn,
      );
    } else {
      List<Widget> subRow = [];
      if (pPaid) {
        subRow.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              "PAGO",
              style: TextStyle(
                fontSize: 10,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
        if (canSeeDate) subRow.add(const SizedBox(width: 8));
      }
      if (canSeeDate)
        subRow.add(
          Text(registeredDate, style: TextStyle(fontSize: 12, color: subColor)),
        );
      if (p.roleInMatch == 'goalkeeper' && p.goaliePaymentStatus != 'none') {
        if (subRow.isNotEmpty) subRow.add(const SizedBox(width: 8));
        subRow.add(
          Text(
            p.goaliePaymentStatus == 'confirmed'
                ? 'PIX CONFIRMADO'
                : 'AGUARDANDO CONFIRMAÇÃO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: p.goaliePaymentStatus == 'confirmed'
                  ? Colors.green
                  : Colors.orange,
            ),
          ),
        );
      }
      if (subRow.isNotEmpty) subtitleWidget = Row(children: subRow);
    }

    final content = ListTile(
      contentPadding: currentUser.canReorderList
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 4)
          : EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: rankBgColor,
        child: Text(
          "${index + 1}",
          style: TextStyle(color: rankTextColor, fontWeight: FontWeight.bold),
        ),
      ),
      title: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: Icon(
              p.isStaff ? LucideIcons.clipboardList : LucideIcons.user,
              size: 16,
              color: p.isStaff
                  ? (isDarkCard ? Colors.lightBlueAccent : Colors.blue)
                  : subColor,
            ),
          ),
          Flexible(
            child: Text(
              displayName + (p.uid == currentUser.uid ? " (Você)" : ""),
              style: TextStyle(
                fontWeight: p.uid == currentUser.uid
                    ? FontWeight.bold
                    : FontWeight.normal,
                fontSize: 14,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
      subtitle: subtitleWidget,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSuplente && kIsWeb)
            Chip(
              label: const Text("Suplente", style: TextStyle(fontSize: 10)),
              backgroundColor: isDarkCard
                  ? Colors.amber[800]
                  : Colors.orangeAccent,
            ),
          if (currentUser.canMarkPaid && (!isSuplente || pPaid))
            IconButton(
              icon: Icon(
                LucideIcons.dollarSign,
                color: pPaid ? Colors.green : subColor,
              ),
              tooltip: "Validar",
              onPressed: () => onPaymentToggle(p),
            ),
          if (p.roleInMatch == 'goalkeeper' &&
              (currentUser.canMarkPaid ||
                  currentUser.isStaff ||
                  currentUser.uid == event.createdBy))
            IconButton(
              icon: const Icon(Icons.qr_code_2, color: Colors.teal),
              tooltip: 'Pagamento do goleiro',
              onPressed: () => onGoalkeeperPayment(p),
            ),
          if (currentUser.canRemovePlayer)
            IconButton(
              icon: Icon(LucideIcons.trash2, size: 20, color: Colors.red),
              tooltip: "Remover",
              onPressed: () => onRemovePlayer(p),
            ),
          if (currentUser.canReorderList)
            Icon(LucideIcons.gripVertical, color: subColor),
        ],
      ),
    );

    if (currentUser.canReorderList)
      return Material(color: Colors.transparent, child: content);
    return content;
  }
}
