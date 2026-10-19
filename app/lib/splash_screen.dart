import 'package:flutter/material.dart';

import 'core/theme/app_tokens.dart';
import 'core/widgets/widgets.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandHeader(),
              SizedBox(height: Spacing.s32),
              CircularProgressIndicator(),
              WakingUpNotice(),
            ],
          ),
        ),
      ),
    );
  }
}
