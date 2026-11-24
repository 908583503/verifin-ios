// VeriFin 打开欢迎动画 —— 模板「login-done-animation」的 Flutter 移植。
//
// 三幕结构（与模板时间轴逐帧一致，总长约 2.6 秒）：
//   1. 卡片横向撑开 1.22 倍，背景被克莱因蓝径向填满；
//   2. 圆弧绕用户图标转 + 四个点呼吸 + 「正在打开账本」；
//   3. 圆弧收掉，白色圆形头像弹出、名字浮起、绿色对勾画出；
//   4. 停留约 600ms 让用户看清，然后整体淡出交出主界面。
//
// 架构沿用模板的分工：
//   - VeriWelcomeFrame.compute：纯函数，时间 → 一帧数值（可测试、无 DOM/Widget）；
//   - VeriFinWelcomeOverlay：每帧把数值画成 Widget（CustomPaint / Transform）。
//
// 平台差异说明：Web 版靠 backdrop-filter 透出背景流体；Flutter 里用
// BackdropFilter + 分层渐变等价还原。无障碍：系统开启「减弱动效」时直接
// 显示终态约 260ms 即结束（对应模板 prefers-reduced-motion）。
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// 时间轴关键点（毫秒，相对动画开始），与模板 TIMELINE 完全一致。
/// 实例常量便于帧计算里用 `T.xxx` 短名引用；[T] 是全局唯一实例。
class VeriWelcomeTimeline {
  const VeriWelcomeTimeline._();

  static const VeriWelcomeTimeline T = VeriWelcomeTimeline._();

  final double expandFrom = 0;
  final double expandTo = 520;
  final double floodFrom = 140;
  final double floodTo = 660;

  final double spinnerFrom = 420;
  final double spinnerTo = 1180;
  final double dotsFrom = 540;
  final double textFrom = 460;
  final double textTo = 740;

  final double spinnerOutFrom = 1160;
  final double spinnerOutTo = 1320;
  final double avatarFrom = 1220;
  final double avatarTo = 1620;
  final double nameFrom = 1380;
  final double nameTo = 1700;
  final double emailFrom = 1480;
  final double emailTo = 1780;
  final double tickFrom = 1520;
  final double tickTo = 1800;

  final double leaveFrom = 2400;
  final double end = 2620;

  static const Duration duration = Duration(milliseconds: 2620);
}

// ── 缓动（与模板 bezier 一致，牛顿迭代求值） ──────────────────────────

double _bezierCurve(double t, double a, double b) =>
    ((1 - 3 * b + 3 * a) * t + (3 * b - 6 * a)) * t * t + 3 * a * t;

double _bezierSlope(double t, double a, double b) =>
    (3 * (1 - 3 * b + 3 * a) * t + 2 * (3 * b - 6 * a)) * t + 3 * a;

typedef VeriWelcomeEasing = double Function(double x);

VeriWelcomeEasing veriWelcomeBezier(double x1, double y1, double x2, double y2) {
  double eval(double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    var t = x;
    for (var i = 0; i < 8; i++) {
      final s = _bezierSlope(t, x1, x2);
      if (s.abs() < 1e-4) break;
      t = (t - (_bezierCurve(t, x1, x2) - x) / s).clamp(0.0, 1.0);
    }
    return _bezierCurve(t, y1, y2);
  }

  return eval;
}

final VeriWelcomeEasing _easeOut = veriWelcomeBezier(0.22, 1, 0.36, 1);
final VeriWelcomeEasing _easeSpring = veriWelcomeBezier(0.34, 1.56, 0.64, 1);
final VeriWelcomeEasing _easeInOut = veriWelcomeBezier(0.65, 0, 0.35, 1);

double _part(double t, double from, double to, VeriWelcomeEasing ease) {
  if (to == from) return t >= to ? 1 : 0;
  final raw = (t - from) / (to - from);
  return ease(raw.clamp(0.0, 1.0));
}

double _mix(double a, double b, double k) => a + (b - a) * k;

// ── 帧数据 ─────────────────────────────────────────────────────────────

class VeriWelcomeDotFrame {
  const VeriWelcomeDotFrame({required this.opacity, required this.scale});
  final double opacity;
  final double scale;
}

class VeriWelcomeSpinnerFrame {
  const VeriWelcomeSpinnerFrame({
    required this.opacity,
    required this.turn,
    required this.ringTurn,
    required this.dash,
  });
  final double opacity;
  final double turn;
  final double ringTurn;
  final double dash;
}

class VeriWelcomeAvatarFrame {
  const VeriWelcomeAvatarFrame({
    required this.opacity,
    required this.scale,
    required this.lift,
  });
  final double opacity;
  final double scale;
  final double lift;
}

class VeriWelcomePingFrame {
  const VeriWelcomePingFrame({required this.opacity, required this.scale});
  final double opacity;
  final double scale;
}

class VeriWelcomeFrame {
  const VeriWelcomeFrame({
    required this.expand,
    required this.flood,
    required this.spinner,
    required this.dots,
    required this.loadingText,
    required this.avatar,
    required this.ping,
    required this.name,
    required this.email,
    required this.tick,
    required this.words,
    required this.ended,
  });

  final double expand;
  final double flood;
  final VeriWelcomeSpinnerFrame spinner;
  final List<VeriWelcomeDotFrame> dots;
  final double loadingText;
  final VeriWelcomeAvatarFrame avatar;
  final VeriWelcomePingFrame ping;
  final double name;
  final double email;
  final double tick;
  final double words;
  final bool ended;
}

/// 纯计算：时间 → 一帧数值（与模板 loginDoneFrame 逐行对应）。
VeriWelcomeFrame veriWelcomeFrameCompute(double sinceMs, double clockMs) {
  final t = sinceMs.clamp(0.0, double.infinity);
  const T = VeriWelcomeTimeline.T;

  // 第一幕：卡片展开 + 染蓝
  final expand = _part(t, T.expandFrom, T.expandTo, _easeInOut);
  final flood = _part(t, T.floodFrom, T.floodTo, _easeInOut);

  // 第二幕：读取
  final spinnerIn = _part(t, T.spinnerFrom, T.spinnerFrom + 220, _easeOut);
  final spinnerOut = _part(t, T.spinnerOutFrom, T.spinnerOutTo, (x) => x);
  final spinnerOpacity = (spinnerIn - spinnerOut).clamp(0.0, 1.0);
  // 圆弧持续转：0.55 度/毫秒 ≈ 650ms 一圈；内圈反向慢转形成双层
  final spinTurn = (clockMs * 0.55) % 360;
  final ringTurn = -(clockMs * 0.28) % 360;

  final dotsBase =
      _part(t, T.dotsFrom, T.dotsFrom + 240, _easeOut) * (1 - spinnerOut);
  final dots = <VeriWelcomeDotFrame>[
    for (var i = 0; i < 4; i++)
      () {
        final phase = ((clockMs / 900 + i * 0.22) % 1 + 1) % 1;
        final pulse = math.sin(phase * 2 * math.pi) * 0.5 + 0.5;
        return VeriWelcomeDotFrame(
          opacity: (dotsBase * (0.28 + 0.72 * pulse)).clamp(0.0, 1.0),
          scale: 0.72 + 0.45 * pulse,
        );
      }(),
  ];

  final text = _part(t, T.textFrom, T.textTo, _easeOut);
  final textOut = _part(t, T.spinnerOutFrom, T.spinnerOutTo, (x) => x);
  final loadingText = (text - textOut).clamp(0.0, 1.0);

  // 第三幕：落定
  final avatarIn = _part(t, T.avatarFrom, T.avatarTo, _easeSpring);
  final nameIn = _part(t, T.nameFrom, T.nameTo, _easeOut);
  final emailIn = _part(t, T.emailFrom, T.emailTo, _easeOut);
  final tickIn = _part(t, T.tickFrom, T.tickTo, _easeOut);
  final pinged = _part(t, T.avatarTo, T.avatarTo + 520, _easeOut);

  // 退场
  final words = 1 - _part(t, T.leaveFrom, T.leaveFrom + 260, (x) => x);

  return VeriWelcomeFrame(
    expand: expand,
    flood: flood,
    spinner: VeriWelcomeSpinnerFrame(
      opacity: spinnerOpacity,
      turn: spinTurn,
      ringTurn: ringTurn,
      dash: _mix(0.04, 0.7, _part(t, T.spinnerFrom, T.spinnerFrom + 420, _easeOut)),
    ),
    dots: dots,
    loadingText: loadingText,
    avatar: VeriWelcomeAvatarFrame(
      opacity: avatarIn,
      scale: _mix(0.55, 1, avatarIn),
      lift: (1 - avatarIn) * 12,
    ),
    ping: VeriWelcomePingFrame(
      opacity: pinged > 0 && pinged < 1 ? (1 - pinged) * 0.4 : 0,
      scale: _mix(1, 1.9, pinged),
    ),
    name: nameIn,
    email: emailIn,
    tick: tickIn,
    words: words,
    ended: t >= T.end,
  );
}

/// 减弱动效时的终态（跳过过程直接显示落定画面）。
VeriWelcomeFrame veriWelcomeEndFrame() => VeriWelcomeFrame(
      expand: 1,
      flood: 1,
      spinner: const VeriWelcomeSpinnerFrame(
          opacity: 0, turn: 0, ringTurn: 0, dash: 0.7),
      dots: const [
        VeriWelcomeDotFrame(opacity: 0, scale: 1),
        VeriWelcomeDotFrame(opacity: 0, scale: 1),
        VeriWelcomeDotFrame(opacity: 0, scale: 1),
        VeriWelcomeDotFrame(opacity: 0, scale: 1),
      ],
      loadingText: 0,
      avatar: const VeriWelcomeAvatarFrame(opacity: 1, scale: 1, lift: 0),
      ping: const VeriWelcomePingFrame(opacity: 0, scale: 1),
      name: 1,
      email: 1,
      tick: 1,
      words: 1,
      ended: false,
    );

const double _pi = math.pi;

// ── 打开动画覆盖层 ─────────────────────────────────────────────────────

/// 打开软件时播放的欢迎动画门：动画覆盖在真实内容之上，播完淡出后放行。
class VeriFinWelcomeGate extends StatefulWidget {
  const VeriFinWelcomeGate({super.key, required this.child});

  final Widget child;

  @override
  State<VeriFinWelcomeGate> createState() => _VeriFinWelcomeGateState();
}

class _VeriFinWelcomeGateState extends State<VeriFinWelcomeGate> {
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    // 测试环境下（flutter test 会向测试进程注入 FLUTTER_TEST 环境变量）自动跳过
    // 动画，否则 2.6 秒的覆盖层会挡住被测界面，导致全部 App 级测试失败。
    // 运行时读取（flutter test 并不把该变量作为 --dart-define 传入）。
    _showOverlay = !Platform.environment.containsKey('FLUTTER_TEST');
  }

  void _handleFinished() {
    if (mounted) setState(() => _showOverlay = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showOverlay)
          VeriFinWelcomeOverlay(onFinished: _handleFinished),
      ],
    );
  }
}

class VeriFinWelcomeOverlay extends StatefulWidget {
  const VeriFinWelcomeOverlay({super.key, required this.onFinished});

  /// 动画结束（含淡出）后回调，宿主应移除本层。
  final VoidCallback onFinished;

  @override
  State<VeriFinWelcomeOverlay> createState() => _VeriFinWelcomeOverlayState();
}

class _VeriFinWelcomeOverlayState extends State<VeriFinWelcomeOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Stopwatch _clock = Stopwatch();
  bool _reducedMotion = false;
  bool _started = false;
  AnimationController? _fadeController;

  /// 整层淡出进度：动画播完后 0→1。
  double _fadeOut = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: VeriWelcomeTimeline.duration,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // MediaQuery 读取必须在 didChangeDependencies（initState 里不可用）。
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reducedMotion) {
      // 直接显示终态，短暂停留后交出（对应模板 260ms）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Future.delayed(const Duration(milliseconds: 260), _beginFadeOut);
      });
    } else {
      _clock.start();
      _controller.forward();
    }
  }

  void _beginFadeOut() {
    if (!mounted || _fadeController != null) return;
    final fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _fadeController = fade;
    fade.addListener(() {
      if (!mounted) return;
      setState(() => _fadeOut = fade.value);
      if (fade.isCompleted) widget.onFinished();
    });
    fade.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeController?.dispose();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final reducedMotion =
            MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        final frame = reducedMotion
            ? veriWelcomeEndFrame()
            : veriWelcomeFrameCompute(
                _controller.value * VeriWelcomeTimeline.T.end,
                _clock.elapsedMilliseconds.toDouble(),
              );
        return IgnorePointer(
          ignoring: _fadeOut > 0,
          child: Opacity(
            opacity: (1 - _fadeOut).clamp(0.0, 1.0),
            child: _VeriWelcomeScene(frame: frame, subtitle: l10n.welcomeSubtitle, loadingText: l10n.welcomeLoadingText),
          ),
        );
      },
    );
  }
}

// ── 场景（背景 + 卡片） ───────────────────────────────────────────────

class _VeriWelcomeScene extends StatelessWidget {
  const _VeriWelcomeScene({
    required this.frame,
    required this.subtitle,
    required this.loadingText,
  });

  final VeriWelcomeFrame frame;
  final String subtitle;
  final String loadingText;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景：深蓝底 + 两团径向光（与演示页 body 渐变一致）
          const ColoredBox(color: Color(0xFF060A17)),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.7, 1.0),
                  radius: 1.6,
                  colors: [
                    const Color.fromRGBO(90, 140, 255, 0.16),
                    const Color.fromRGBO(90, 140, 255, 0.0),
                  ],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.8, -1.0),
                  radius: 1.4,
                  colors: [
                    const Color.fromRGBO(0, 47, 167, 0.22),
                    const Color.fromRGBO(0, 47, 167, 0.0),
                  ],
                  stops: const [0, 0.55],
                ),
              ),
            ),
          ),
          Center(
            child: _VeriWelcomeCard(
              frame: frame,
              subtitle: subtitle,
              loadingText: loadingText,
            ),
          ),
        ],
      ),
    );
  }
}

class _VeriWelcomeCard extends StatelessWidget {
  const _VeriWelcomeCard({
    required this.frame,
    required this.subtitle,
    required this.loadingText,
  });

  final VeriWelcomeFrame frame;
  final String subtitle;
  final String loadingText;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final baseWidth = (screen.width * 0.88).clamp(0.0, 420.0);
    final width = baseWidth * (1 + 0.22 * frame.expand);
    const height = 440.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 玻璃底：半透明深色 + 模糊
            BackdropFilter(
              filter: ui.ImageFilter.compose(
                outer: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                inner: ui.ColorFilter.matrix(<double>[
                  1.5, 0, 0, 0, 0, //
                  0, 1.5, 0, 0, 0, //
                  0, 0, 1.5, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
              ),
              child: const ColoredBox(color: Color.fromRGBO(6, 12, 28, 0.72)),
            ),
            // 蓝色染色（clip 圆形从中心长出）
            if (frame.flood > 0)
              CustomPaint(
                painter: _FloodPainter(progress: frame.flood),
              ),
            // 读取态：圆弧 + 图标 + 点 + 文案
            if (frame.spinner.opacity > 0 || frame.loadingText > 0)
              _LoadingLayer(frame: frame, loadingText: loadingText),
            // 落定态：头像 + 名字 + 对勾
            _SettledLayer(frame: frame, subtitle: subtitle),
          ],
        ),
      ),
    );
  }
}

// ── 染色层 ─────────────────────────────────────────────────────────────

class _FloodPainter extends CustomPainter {
  const _FloodPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final cy = size.height * 0.46;
    final maxR = math.sqrt(cx * cx + cy * cy) * 2 + 20;
    final r = maxR * progress;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
    final rect = Offset.zero & size;

    // ④ 主体（先画底层）：#205AED 带透明度
    canvas.drawRect(rect, Paint()..color = const Color.fromRGBO(32, 90, 237, 0.80));
    // ③ 顶部压暗
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, 0),
          Offset(0, size.height),
          [
            const Color.fromRGBO(7, 16, 42, 0.55),
            const Color.fromRGBO(14, 34, 90, 0.16),
            const Color.fromRGBO(32, 90, 237, 0.0),
          ],
          [0, 0.34, 0.62],
        ),
    );
    // ② 底部透光
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.36, size.height * 1.08),
          size.width * 1.2,
          [
            const Color.fromRGBO(70, 122, 250, 0.62),
            const Color.fromRGBO(46, 100, 244, 0.30),
            const Color.fromRGBO(32, 90, 237, 0.0),
          ],
          [0, 0.48, 0.78],
        ),
    );
    // ① 中心聚光
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * 0.5, size.height * 0.48),
          size.width * 0.46,
          [
            const Color.fromRGBO(126, 166, 255, 0.58),
            const Color.fromRGBO(82, 130, 250, 0.30),
            const Color.fromRGBO(32, 90, 237, 0.0),
          ],
          [0, 0.45, 0.76],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FloodPainter old) => old.progress != progress;
}

// ── 读取层 ─────────────────────────────────────────────────────────────

class _LoadingLayer extends StatelessWidget {
  const _LoadingLayer({required this.frame, required this.loadingText});

  final VeriWelcomeFrame frame;
  final String loadingText;

  @override
  Widget build(BuildContext context) {
    final spinOpacity = frame.spinner.opacity;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Opacity(
          opacity: spinOpacity.clamp(0.0, 1.0),
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(84, 84),
                  painter: _ArcPainter(
                    radius: 38,
                    strokeWidth: 2.2,
                    dash: frame.spinner.dash,
                    rotationDeg: frame.spinner.turn,
                    color: const Color.fromRGBO(190, 214, 255, 0.92),
                  ),
                ),
                CustomPaint(
                  size: const Size(84, 84),
                  painter: _ArcPainter(
                    radius: 34,
                    strokeWidth: 1.2,
                    dash: 0.62,
                    rotationDeg: frame.spinner.ringTurn,
                    color: const Color.fromRGBO(150, 185, 255, 0.38),
                  ),
                ),
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CustomPaint(painter: _UserIconPainter()),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < frame.dots.length; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.scale(
                    scale: frame.dots[i].scale,
                    child: Opacity(
                      opacity: frame.dots[i].opacity.clamp(0.0, 1.0),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          color: Color.fromRGBO(200, 220, 255, 0.95),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Transform.translate(
          offset: Offset(0, 6 * (1 - frame.loadingText)),
          child: Opacity(
            opacity: frame.loadingText.clamp(0.0, 1.0),
            child: Text(
              loadingText,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                letterSpacing: 0.78,
                fontWeight: FontWeight.w500,
                color: Color.fromRGBO(210, 226, 255, 0.9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.rotationDeg,
    required this.color,
  });

  final double radius;
  final double strokeWidth;
  final double dash;
  final double rotationDeg;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotationDeg * _pi / 180);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: radius),
      0,
      2 * _pi * dash,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.dash != dash || old.rotationDeg != rotationDeg;
}

class _UserIconPainter extends CustomPainter {
  const _UserIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale, scale);
    final paint = Paint()
      ..color = const Color.fromRGBO(214, 230, 255, 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 头
    canvas.drawCircle(const Offset(12, 8.5), 3.6, paint);
    // 肩
    final path = Path()
      ..moveTo(4.8, 20)
      ..cubicTo(4.8, 16.4, 8.0, 13.8, 12.0, 13.8)
      ..cubicTo(16.0, 13.8, 19.2, 16.4, 19.2, 20);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── 落定层 ─────────────────────────────────────────────────────────────

class _SettledLayer extends StatelessWidget {
  const _SettledLayer({required this.frame, required this.subtitle});

  final VeriWelcomeFrame frame;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final avatar = frame.avatar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 78,
          height: 78,
          child: Stack(
            children: [
              Center(
                child: Opacity(
                  opacity: avatar.opacity.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, avatar.lift),
                    child: Transform.scale(
                      scale: avatar.scale,
                      child: Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment(-0.6, -1),
                            end: Alignment(0.6, 1),
                            colors: [Color(0xFFFFFFFF), Color(0xFFDCE7FF)],
                          ),
                          border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.45),
                              blurRadius: 42,
                              offset: Offset(0, 22),
                              spreadRadius: -10,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'V',
                          style: TextStyle(
                            fontSize: 31,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF205AED),
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 脉冲圈
              Center(
                child: Transform.scale(
                  scale: frame.ping.scale,
                  child: Opacity(
                    opacity: frame.ping.opacity.clamp(0.0, 1.0),
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color.fromRGBO(255, 255, 255, 0.85),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 绿色对勾徽章
              Positioned(
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: (frame.tick * frame.words).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.5 + 0.5 * frame.tick,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF34D399),
                        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(16, 185, 129, 0.5),
                            blurRadius: 14,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: CustomPaint(painter: _TickPainter(progress: frame.tick)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Transform.translate(
          offset: Offset(0, 10 * (1 - frame.name)),
          child: Opacity(
            opacity: (frame.name * frame.words).clamp(0.0, 1.0),
            child: const Text(
              'VeriFin',
              style: TextStyle(
                fontSize: 27,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFFFFF),
                shadows: [
                  Shadow(color: Color.fromRGBO(0, 0, 0, 0.35), blurRadius: 18, offset: Offset(0, 2)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Transform.translate(
          offset: Offset(0, 8 * (1 - frame.email)),
          child: Opacity(
            opacity: (frame.email * frame.words).clamp(0.0, 1.0),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: Color.fromRGBO(190, 210, 250, 0.62),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale, scale);
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 路径长度约 26，与模板 stroke-dasharray 26 一致：progress 0→1 画出。
    final path = Path()
      ..moveTo(4, 12.5)
      ..lineTo(9.2, 17.7)
      ..lineTo(20, 7);
    final metric = path.computeMetrics().first;
    final visible = metric.length * progress.clamp(0.0, 1.0);
    canvas.drawPath(metric.extractPath(0, visible), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.progress != progress;
}
