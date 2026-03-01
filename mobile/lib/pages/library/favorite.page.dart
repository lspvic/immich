import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/multiselect.provider.dart';
import 'package:immich_mobile/providers/timeline.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/asset_grid/multiselect_grid.dart';

@RoutePage()
class FavoritesPage extends HookConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final renderList = ref.watch(favoriteTimelineProvider);

    AppBar buildAppBar() {
      return AppBar(
        leading: IconButton(onPressed: () => context.maybePop(), icon: const Icon(Icons.arrow_back_ios_rounded)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text('favorites').tr(),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'slideshow') {
                final rl = renderList.value;
                if (rl != null && rl.totalAssets > 0) {
                  context.pushRoute(SlideshowRoute(renderList: rl));
                } else {
                  context.showSnackBar(
                    SnackBar(
                      content: Text('no_assets_to_slideshow'.tr()),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'slideshow',
                child: Row(
                  children: [
                    const Icon(Icons.slideshow_rounded),
                    const SizedBox(width: 12),
                    Text('slideshow').tr(),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Scaffold(
      appBar: ref.watch(multiselectProvider) ? null : buildAppBar(),
      body: MultiselectGrid(
        renderListProvider: favoriteTimelineProvider,
        favoriteEnabled: true,
        editEnabled: true,
        unfavorite: true,
      ),
    );
  }
}
