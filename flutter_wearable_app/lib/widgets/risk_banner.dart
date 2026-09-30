import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../models/risk_result.dart';

class RiskBanner extends StatelessWidget {
  final RiskResult riskResult;

  const RiskBanner({super.key, required this.riskResult});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (riskResult.tier) {
      case RiskTier.criticalRed:
        color = AppColors.dangerRed;
        icon = Icons.warning_rounded;
        break;
      case RiskTier.warningOrange:
        color = AppColors.warningOrange;
        icon = Icons.error_outline_rounded;
        break;
      case RiskTier.cautionYellow:
        color = AppColors.warningYellow;
        icon = Icons.info_outline_rounded;
        break;
      case RiskTier.nominalGreen:
        color = AppColors.accentGreen;
        icon = Icons.check_circle_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: CircularProgressIndicator(
                  value: riskResult.compositeScore,
                  strokeWidth: 7,
                  backgroundColor: AppColors.surfaceBorder,
                  color: color,
                ),
              ),
              Text(
                '${(riskResult.compositeScore * 100).toInt()}%',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 6),
                    Text(
                      riskResult.statusTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  riskResult.primaryReason,
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                ),
                if (riskResult.activeAlerts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    riskResult.activeAlerts.first,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
