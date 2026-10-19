import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/translations.dart';
import '../theme/app_theme.dart';
import '../utils/app_routes.dart';
import '../widgets/common.dart';
import 'main_navigation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    final valid = _form.currentState?.validate() ?? false;
    if (!valid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('farmer_name', _name.text.trim());
      if (mounted) {
        Navigator.pushReplacement(
            context, fadeSlideTo(const MainNavigationScreen()));
      }
    } catch (_) {
      setState(() => _error = tr('Could not save your name. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageService.instance.language,
      builder: (context, _, __) => Scaffold(
            body: SafeArea(
                child: Padding(
              padding: Spacing.page,
              child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                          alignment: Alignment.centerRight,
                          child: LanguageToggleButton()),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: AppColors.forest,
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.card,
                        ),
                        child: const Icon(Icons.eco,
                            size: 48, color: AppColors.leafLight),
                      ),
                      const SizedBox(height: 20),
                      const Text('AgriSentry AI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              color: AppColors.forest)),
                      const SizedBox(height: 6),
                      Text(tr('AI-powered crop intelligence.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.pine,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Text(
                          tr('Tell us your name so we can greet you on your farm dashboard.'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppColors.muted, height: 1.45)),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? tr('Please enter your name')
                            : null,
                        decoration: InputDecoration(
                          labelText: tr('Your name'),
                          prefixIcon: const Icon(Icons.person_outline),
                          filled: true,
                          fillColor: Colors.white,
                          errorText: _error,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                        ),
                        onFieldSubmitted: (_) => _continue(),
                      ),
                      const SizedBox(height: 20),
                      _busy
                          ? LoadingView(tr('Setting up your farm...'))
                          : PrimaryButton(
                              label: tr('Continue'),
                              icon: Icons.arrow_forward,
                              onPressed: _continue),
                      const Spacer(),
                    ]),
              ),
            )),
          ));
}
