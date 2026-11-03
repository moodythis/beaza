import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

IconData categoryIcon(String bucket) => switch (bucket) {
      'food' => Icons.restaurant_outlined,
      'groceries' => Icons.shopping_basket_outlined,
      'shopping' => Icons.shopping_bag_outlined,
      'transport' => Icons.directions_car_outlined,
      'bills' => Icons.receipt_long_outlined,
      'health' => Icons.favorite_border,
      'entertainment' => Icons.movie_outlined,
      'education' => Icons.school_outlined,
      'other' => Icons.category_outlined,
      kTransferBucket => Icons.swap_horiz,
      _ => Icons.help_outline,
    };

String categoryName(AppLocalizations l10n, String bucket) => switch (bucket) {
      'food' => l10n.categoryFood,
      'groceries' => l10n.categoryGroceries,
      'shopping' => l10n.categoryShopping,
      'transport' => l10n.categoryTransport,
      'bills' => l10n.categoryBills,
      'health' => l10n.categoryHealth,
      'entertainment' => l10n.categoryEntertainment,
      'education' => l10n.categoryEducation,
      'other' => l10n.categoryOther,
      kTransferBucket => l10n.categoryTransfer,
      _ => l10n.categoryUnsorted,
    };
