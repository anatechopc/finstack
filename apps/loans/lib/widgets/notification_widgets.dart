import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:jiffy/jiffy.dart';
import 'package:loooans/app/model/notification_model.dart';
import 'package:loooans/utils/extensions.dart';

class NotificationWidgets {
  static Widget notificationItem(
    BuildContext context, {
    required NotificationModel model,
    bool isFirst = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: 268,
      margin: EdgeInsets.only(
        bottom: 16,
        top: isFirst ? 16 : 0,
        left: 16,
        right: 16,
      ),
      constraints: const BoxConstraints(
        maxWidth: 268,
        // maxHeight: 98,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: colorScheme.surface.withOpacity(0.32),
              ),
            ),
            child: SizedBox.square(
              dimension: 36,
              child: CircleAvatar(
                backgroundColor: colorScheme.surface,
                child: Text(
                  model.company != null
                      ? model.company!.name.initials(limit: 3)
                      : '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.notification.title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.surface,
                  ),
                ),
                const Gap(8),
                ...[
                Text(
                  model.notification.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.surface,
                  ),
                ),
                const Gap(4),
              ],
                Text(
                  Jiffy.parseFromDateTime(model.notification.createdAt)
                      .fromNow(),
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.surface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
