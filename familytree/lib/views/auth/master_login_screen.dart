import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../widgets/custom_text_field.dart';

class MasterLoginScreen extends StatefulWidget {
  final VoidCallback? onSwitchToMember;
  final VoidCallback? onSwitchToRegister;
  const MasterLoginScreen({
    super.key,
    this.onSwitchToMember,
    this.onSwitchToRegister,
  });

  @override
  State<MasterLoginScreen> createState() => _MasterLoginScreenState();
}

class _MasterLoginScreenState extends State<MasterLoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool    _passwordVisible = false;
  bool    _loading         = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });

    final auth    = context.read<AuthProvider>();
    final success = await auth.loginMaster(
      email:    _emailCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() { _loading = false; });
    if (!success) {
      setState(() { _error = auth.errorMessage ?? 'Login failed.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.account_tree_rounded,
                      size: 72, color: AppColors.primary),
                  const SizedBox(height: 20),
                  const Text('Master Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  const SizedBox(height: 6),
                  const Text('Manage your family tree',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 40),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(color: AppColors.error)),
                    ),
                    const SizedBox(height: 16),
                  ],

                  CustomTextField(
                    controller: _emailCtrl,
                    label: 'Email Address',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email_outlined),
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Email required' : null,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _passwordCtrl,
                    label: 'Password',
                    obscureText: !_passwordVisible,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_passwordVisible
                          ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible),
                    ),
                    validator: (v) =>
                    (v == null || v.isEmpty) ? 'Password required' : null,
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _loading
                          ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                          : const Text('Sign In',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Register link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? ",
                          style: TextStyle(color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: widget.onSwitchToRegister,
                        child: const Text('Register',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Switch to member
                  if (widget.onSwitchToMember != null)
                    TextButton(
                      onPressed: widget.onSwitchToMember,
                      child: const Text('Login as Family Member instead',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
