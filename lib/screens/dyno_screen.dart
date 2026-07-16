import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(children: [
          // ── Logo ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
            child: Row(children: [
              Image.asset('assets/images/logo.png', width: 44, height: 44),
              const SizedBox(width: 12),
              const Text('Dynomic',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: Colors.white, letterSpacing: -.5)),
            ]),
          ),

          // ── Tabs ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  color: const Color(0xFFE51C1C),
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14),
                dividerColor: Colors.transparent,
                tabs: const [Tab(text: 'Log in'), Tab(text: 'Register')],
              ),
            ),
          ),

          // ── Tab views ─────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: const [_LoginForm(), _RegisterForm()],
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  LOGIN FORM
// ══════════════════════════════════════════════════════════════
class _LoginForm extends StatefulWidget {
  const _LoginForm();
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool    _loading    = false;
  bool    _showPwd    = false;
  String? _error;

  // Rate limiting
  int    _rateLimitSecs = 0;
  Timer? _rateLimitTimer;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _rateLimitTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _rateLimitTimer?.cancel();
    setState(() => _rateLimitSecs = seconds);
    _rateLimitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_rateLimitSecs <= 1) {
        t.cancel();
        setState(() => _rateLimitSecs = 0);
      } else {
        setState(() => _rateLimitSecs--);
      }
    });
  }

  Future<void> _submit() async {
    if (_rateLimitSecs > 0) return;

    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final auth   = context.read<AuthService>();
      final result = await auth.login(email: email, password: password);
      if (!mounted) return;
      setState(() => _loading = false);
      if (!result.ok) setState(() => _error = result.error);
      // Jeśli OK — AuthService.notifyListeners() przebuduje root
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = null; });
      _startCountdown(e.retryAfterSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _rateLimitSecs > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text('Welcome back',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Log in to your Dynomic account',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 28),

          if (blocked)
            _RateLimitBanner(_rateLimitSecs),

          if (!blocked && _error != null)
            _ErrorBanner(_error!),

          _Field(label: 'Email', controller: _emailCtrl,
              keyboard: TextInputType.emailAddress, hint: 'jan@example.com'),

          _Field(
            label: 'Password',
            controller: _passwordCtrl,
            obscure: !_showPwd,
            hint: '••••••••',
            suffix: IconButton(
              icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey, size: 20),
              onPressed: () => setState(() => _showPwd = !_showPwd),
            ),
          ),

          const SizedBox(height: 8),
          _PrimaryButton(
            label:    blocked
                ? 'Try again in ${_rateLimitSecs}s'
                : 'Log in',
            loading:  _loading,
            disabled: blocked,
            onTap:    _submit,
          ),

          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () async {
                final uri = Uri.parse('https://dynomic.pro/forgot');
                // ignore: deprecated_member_use
                if (await canLaunchUrl(uri)) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Forgot password?',
                  style: TextStyle(color: Color(0xFFE51C1C))),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  REGISTER FORM
// ══════════════════════════════════════════════════════════════
class _RegisterForm extends StatefulWidget {
  const _RegisterForm();
  @override
  State<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<_RegisterForm> {
  final _firstCtrl    = TextEditingController();
  final _lastCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _serialCtrl   = TextEditingController();
  bool    _loading    = false;
  bool    _showPwd    = false;
  bool    _measUpload = false;
  bool    _terms      = false;
  String? _error;
  String? _success;

  // Rate limiting
  int    _rateLimitSecs = 0;
  Timer? _rateLimitTimer;

  @override
  void dispose() {
    _firstCtrl.dispose(); _lastCtrl.dispose();
    _emailCtrl.dispose(); _passwordCtrl.dispose();
    _serialCtrl.dispose();
    _rateLimitTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _rateLimitTimer?.cancel();
    setState(() => _rateLimitSecs = seconds);
    _rateLimitTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_rateLimitSecs <= 1) {
        t.cancel();
        setState(() => _rateLimitSecs = 0);
      } else {
        setState(() => _rateLimitSecs--);
      }
    });
  }

  Future<void> _submit() async {
    if (_rateLimitSecs > 0) return;

    final firstName = _firstCtrl.text.trim();
    final email     = _emailCtrl.text.trim();
    final password  = _passwordCtrl.text;
    final serial    = _serialCtrl.text.trim().toUpperCase();

    if (firstName.isEmpty || email.isEmpty ||
        password.isEmpty  || serial.isEmpty) {
      setState(() => _error = 'Please fill in all required fields');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (serial.length != 32) {
      setState(() => _error = 'Serial must be 32 characters (check your leaflet)');
      return;
    }
    if (!_terms) {
      setState(() => _error = 'Please accept the Terms of Service');
      return;
    }

    setState(() { _loading = true; _error = null; _success = null; });

    try {
      final auth   = context.read<AuthService>();
      final result = await auth.register(
        email:              email,
        password:           password,
        firstName:          firstName,
        lastName:           _lastCtrl.text.trim(),
        serial:             serial,
        measurementsUpload: _measUpload,
      );

      if (!mounted) return;
      setState(() => _loading = false);

      if (result.ok) {
        setState(() => _success =
            'Account created! Check your email to verify, then log in.');
      } else {
        setState(() => _error = result.error);
      }
    } on RateLimitedException catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = null; });
      _startCountdown(e.retryAfterSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _rateLimitSecs > 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Text('Register your device',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 6),
          const Text('Create an account and pair your hardware',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
          const SizedBox(height: 28),

          if (blocked)
            _RateLimitBanner(_rateLimitSecs),

          if (!blocked && _error != null)
            _ErrorBanner(_error!),

          if (_success != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: .1),
                border: Border.all(color: Colors.green.withValues(alpha: .4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_success!,
                  style: const TextStyle(
                      color: Color(0xFF86EFAC), fontSize: 13)),
            ),

          Row(children: [
            Expanded(child: _Field(label: 'First name *',
                controller: _firstCtrl, hint: 'Jan')),
            const SizedBox(width: 12),
            Expanded(child: _Field(label: 'Last name',
                controller: _lastCtrl,  hint: 'Kowalski')),
          ]),

          _Field(label: 'Email *', controller: _emailCtrl,
              keyboard: TextInputType.emailAddress, hint: 'jan@example.com'),

          _Field(
            label: 'Password * (min. 8 chars)',
            controller: _passwordCtrl,
            obscure: !_showPwd, hint: '••••••••',
            suffix: IconButton(
              icon: Icon(_showPwd ? Icons.visibility_off : Icons.visibility,
                  color: Colors.grey, size: 20),
              onPressed: () => setState(() => _showPwd = !_showPwd),
            ),
          ),

          _Field(
            label: 'Device serial *',
            controller: _serialCtrl,
            hint: 'A3F1B29C... (32 chars from leaflet)',
            keyboard: TextInputType.text,
            uppercase: true,
          ),

          _CheckRow(
            value: _measUpload,
            onChanged: (v) => setState(() => _measUpload = v),
            label: 'Allow cloud backup of my measurements (optional)',
          ),

          _CheckRow(
            value: _terms,
            onChanged: (v) => setState(() => _terms = v),
            label: 'I agree to the Terms of Service and Privacy Policy',
            linkText: 'Terms of Service',
            linkUrl: 'https://dynomic.pro/terms',
          ),

          const SizedBox(height: 8),
          _PrimaryButton(
            label:    blocked
                ? 'Try again in ${_rateLimitSecs}s'
                : 'Create account & pair device',
            loading:  _loading,
            disabled: blocked,
            onTap:    _submit,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
//  HELPER WIDGETS
// ══════════════════════════════════════════════════════════════

class _RateLimitBanner extends StatelessWidget {
  final int seconds;
  const _RateLimitBanner(this.seconds);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE51C1C).withValues(alpha: .08),
        border: Border.all(color: const Color(0xFFE51C1C).withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.timer_outlined, color: Color(0xFFE51C1C), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Too many attempts. Try again in ${seconds}s.',
            style: const TextStyle(color: Color(0xFFFF8080), fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final String? hint;
  final bool obscure;
  final bool uppercase;
  final Widget? suffix;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboard,
    this.hint,
    this.obscure   = false,
    this.uppercase = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: Colors.white70)),
          const SizedBox(height: 7),
          TextField(
            controller: controller,
            keyboardType: keyboard,
            obscureText: obscure,
            textCapitalization: uppercase
                ? TextCapitalization.characters
                : TextCapitalization.none,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.grey),
              suffixIcon: suffix,
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                      color: Color(0xFFE51C1C), width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String       label;
  final bool         loading;
  final bool         disabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: (loading || disabled) ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE51C1C),
          disabledBackgroundColor: const Color(0xFF8B1010),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5))
            : Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .1),
        border: Border.all(color: Colors.red.withValues(alpha: .4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message,
          style: const TextStyle(color: Color(0xFFFF8080), fontSize: 13)),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool   value;
  final void Function(bool) onChanged;
  final String  label;
  final String? linkText;
  final String? linkUrl;

  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.label,
    this.linkText,
    this.linkUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: const Color(0xFFE51C1C),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!value),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 13, height: 1.4)),
            ),
          ),
        ],
      ),
    );
  }
}