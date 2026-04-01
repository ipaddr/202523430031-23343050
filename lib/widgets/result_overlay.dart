import 'dart:ui';
import 'package:flutter/material.dart';

class ResultOverlay extends StatelessWidget {
  final String label;
  final double confidence;

  const ResultOverlay({
    super.key,
    required this.label,
    required this.confidence,
  });

  static const Map<String, String> _emojiMap = {
    'marah': '😠',
    'senang': '😊',
    'netral': '😐',
    'sedih': '😢',
  };

  static const Map<String, Color> _colorMap = {
    'marah': Color(0xFFE53935),
    'senang': Color(0xFFFDD835),
    'netral': Color(0xFF78909C),
    'sedih': Color(0xFF1E88E5),
  };

  @override
  Widget build(BuildContext context) {
    final emoji = _emojiMap[label.toLowerCase()] ?? '🤔';
    final color = _colorMap[label.toLowerCase()] ?? Colors.grey;
    final pct = (confidence * 100).toStringAsFixed(1);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.25),
                Colors.black.withValues(alpha: 0.45),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: color.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Emoji
              Text(emoji, style: const TextStyle(fontSize: 56)),
              const SizedBox(height: 8),
              // Label
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 16),
              // Confidence bar
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: confidence.clamp(0.0, 1.0),
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 10),
              // Confidence text
              Text(
                '$pct%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
