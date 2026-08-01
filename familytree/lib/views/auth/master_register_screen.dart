import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../widgets/custom_text_field.dart';

class MasterRegisterScreen extends StatefulWidget {
  final VoidCallback? onSwitchToLogin;
  const MasterRegisterScreen({super.key, this.onSwitchToLogin});

  @override
  State<MasterRegisterScreen> createState() => _MasterRegisterScreenState();
}

class _MasterRegisterScreenState extends State<MasterRegisterScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl  = TextEditingController();
  final _mobileCtrl    = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _confirmCtrl   = TextEditingController();

  bool    _passwordVisible = false;
  bool    _confirmVisible  = false;
  bool    _loading         = false;
  String? _error;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });

    final auth    = context.read<AuthProvider>();
    final success = await auth.registerMaster(
      email:        _emailCtrl.text.trim(),
      password:     _passwordCtrl.text.trim(),
      firstName:    _firstNameCtrl.text.trim(),
      lastName:     _lastNameCtrl.text.trim(),
      mobileNumber: _mobileCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() { _loading = false; });
    if (!success) {
      setState(() { _error = auth.errorMessage ?? 'Registration failed.'; });
    }
    // On success AuthGate auto-navigates to MasterDashboard
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  const Icon(Icons.account_tree_rounded,
                      size: 60, color: AppColors.primary),
                  const SizedBox(height: 12),
                  const Text('Create Your Family',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  const SizedBox(height: 4),
                  const Text('Register as Master to manage your family tree',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 28),

                  // Error banner
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

                  // Name row
                  Row(children: [
                    Expanded(
                      child: CustomTextField(
                        controller: _firstNameCtrl,
                        label: 'First Name *',
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: _lastNameCtrl,
                        label: 'Last Name *',
                        prefixIcon: const Icon(Icons.person_outline),
                        validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // Mobile
                  CustomTextField(
                    controller: _mobileCtrl,
                    label: 'Mobile Number *',
                    hint: '10-digit mobile number',
                    keyboardType: TextInputType.phone,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length != 10) return 'Enter 10-digit number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Email
                  CustomTextField(
                    controller: _emailCtrl,
                    label: 'Email Address *',
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(Icons.email_outlined),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!RegExp(r'^[\w-.]+@[\w-]+\.[a-zA-Z]+$')
                          .hasMatch(v.trim())) return 'Enter valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Password
                  CustomTextField(
                    controller: _passwordCtrl,
                    label: 'Password *',
                    hint: 'Min 6 characters',
                    obscureText: !_passwordVisible,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_passwordVisible
                          ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  // Confirm password
                  CustomTextField(
                    controller: _confirmCtrl,
                    label: 'Confirm Password *',
                    obscureText: !_confirmVisible,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_confirmVisible
                          ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(
                              () => _confirmVisible = !_confirmVisible),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (v != _passwordCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // Register button
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
                          : const Text('Create Family Account',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Switch to login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Already have an account? ',
                          style: TextStyle(color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: widget.onSwitchToLogin,
                        child: const Text('Sign In',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
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
