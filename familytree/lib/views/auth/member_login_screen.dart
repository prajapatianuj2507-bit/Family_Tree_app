import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/firebase_service.dart';
import '../../providers/auth_provider.dart';
import '../widgets/custom_text_field.dart';

class MemberLoginScreen extends StatefulWidget {
  final VoidCallback? onSwitchToMaster;
  const MemberLoginScreen({super.key, this.onSwitchToMaster});

  @override
  State<MemberLoginScreen> createState() => _MemberLoginScreenState();
}

class _MemberLoginScreenState extends State<MemberLoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _mobileCtrl   = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool    _passwordVisible = false;
  bool    _loading         = false;
  String? _error;

  @override
  void dispose() {
    _mobileCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });

    final auth    = context.read<AuthProvider>();
    final success = await auth.loginMember(
      mobile:   _mobileCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() { _loading = false; });
    if (!success) {
      setState(() {
        _error = auth.errorMessage ?? 'Login failed. Please try again.';
      });
    }
  }

  void _showForgotPassword() {
    final mobileCtrl = TextEditingController(text: _mobileCtrl.text.trim());
    bool sending = false;
    String? msg;
    bool isError = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.lock_reset, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Forgot Password'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your mobile number and we will send a password reset request to your Master.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: mobileCtrl,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (msg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isError
                        ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: isError
                            ? Colors.red.shade200 : Colors.green.shade200),
                  ),
                  child: Row(children: [
                    Icon(
                      isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16,
                      color: isError ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(msg!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isError
                                ? AppColors.error : AppColors.success,
                          )),
                    ),
                  ]),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary),
              onPressed: sending ? null : () async {
                final mobile = mobileCtrl.text.trim();
                if (mobile.length != 10) {
                  setS(() {
                    msg = 'Please enter a valid 10-digit mobile number.';
                    isError = true;
                  });
                  return;
                }
                setS(() { sending = true; msg = null; });

                try {
                  await FirebaseService.instance
                      .sendPasswordResetRequest(mobile);
                  setS(() {
                    sending = false;
                    msg = 'Request sent! Your Master will reset your password shortly.';
                    isError = false;
                  });
                } on FirebaseServiceException catch (e) {
                  setS(() {
                    sending = false;
                    msg = e.message;
                    isError = true;
                  });
                } catch (e) {
                  setS(() {
                    sending = false;
                    msg = 'Failed to send request. Try again.';
                    isError = true;
                  });
                }
              },
              child: sending
                  ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
                  : const Text('Send Request',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.people_alt_rounded,
                      size: 72, color: AppColors.accent),
                  const SizedBox(height: 20),
                  const Text('Family Member Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      )),
                  const SizedBox(height: 6),
                  const Text('View your family tree',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 40),

                  // Error banner
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppColors.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    color: AppColors.error, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  CustomTextField(
                    controller: _mobileCtrl,
                    label: 'Mobile Number',
                    hint: '10-digit mobile number',
                    keyboardType: TextInputType.phone,
                    prefixIcon: const Icon(Icons.phone_outlined),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (v) {
                      if (v == null || v.trim().isEmpty)
                        return 'Mobile number is required';
                      if (v.trim().length != 10)
                        return 'Enter a valid 10-digit number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _passwordCtrl,
                    label: 'Password',
                    hint: 'Password provided by your Master',
                    obscureText: !_passwordVisible,
                    keyboardType: TextInputType.number,
                    prefixIcon: const Icon(Icons.lock_outline),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(8),
                    ],
                    suffixIcon: IconButton(
                      icon: Icon(_passwordVisible
                          ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(
                              () => _passwordVisible = !_passwordVisible),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length != 8) return 'Password must be 8 digits';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),

                  // Forgot password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showForgotPassword,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Forgot Password?',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          )),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(                        backgroundColor: AppColors.accent,

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
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 12),

                  if (widget.onSwitchToMaster != null)
                    OutlinedButton.icon(
                      onPressed: widget.onSwitchToMaster,
                      icon: const Icon(Icons.admin_panel_settings_outlined),
                      label: const Text('Login as Master'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
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
