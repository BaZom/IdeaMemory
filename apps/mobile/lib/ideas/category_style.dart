import 'package:flutter/material.dart';

/// How a category looks: an icon and a color, used on cards, chips and the
/// detail page. Uncategorised ideas use a neutral lightbulb.
class CategoryStyle {
  const CategoryStyle(this.icon, this.color);

  final IconData icon;
  final Color color;

  static const _styles = {
    'food': CategoryStyle(Icons.restaurant, Color(0xFFE65100)),
    'activity': CategoryStyle(Icons.directions_run, Color(0xFF2E7D32)),
    'travel': CategoryStyle(Icons.flight_takeoff, Color(0xFF0277BD)),
    'film-series': CategoryStyle(Icons.movie, Color(0xFF6A1B9A)),
    'recipe': CategoryStyle(Icons.soup_kitchen, Color(0xFFC62828)),
    'product': CategoryStyle(Icons.shopping_bag, Color(0xFF00838F)),
    'book': CategoryStyle(Icons.menu_book, Color(0xFF5D4037)),
    'place': CategoryStyle(Icons.place, Color(0xFFAD1457)),
    'other': CategoryStyle(Icons.auto_awesome, Color(0xFF546E7A)),
  };

  static const none = CategoryStyle(Icons.lightbulb_outline, Color(0xFF7E57C2));

  static CategoryStyle of(String? category) => _styles[category] ?? none;
}

/// A round, tinted icon for a category.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 44});

  final String? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: Icon(style.icon, color: style.color, size: size * 0.5),
    );
  }
}

/// "today", "yesterday", "3 days ago", "2 weeks ago", or a date.
String relativeDay(DateTime time, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(time.toLocal());
  final days = today.difference(day).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) return '${days ~/ 7} week${days < 14 ? '' : 's'} ago';
  return '${day.day}.${day.month}.${day.year}';
}
