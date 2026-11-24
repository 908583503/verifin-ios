// VeriFin 欢迎动画帧函数测试。
//
// 帧计算是纯函数（时间 → 数值），不需要真的等 2.6 秒就能验证节奏；
// 断言锚定模板（login-done-animation）的关键时间点。

import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/welcome/verifin_welcome.dart';

void main() {
  group('veriWelcomeFrameCompute 三幕节奏', () {
    test('开场：一切还没开始', () {
      final f = veriWelcomeFrameCompute(0, 0);
      expect(f.expand, 0);
      expect(f.flood, 0);
      expect(f.spinner.opacity, 0);
      expect(f.loadingText, 0);
      expect(f.avatar.opacity, 0);
      expect(f.ended, isFalse);
      expect(f.dots, hasLength(4));
    });

    test('第一幕结束（520ms）：卡片撑满', () {
      final f = veriWelcomeFrameCompute(520, 520);
      expect(f.expand, closeTo(1, 1e-6));
    });

    test('第二幕中段（800ms）：圆弧可见、文案可见、头像未出现', () {
      final f = veriWelcomeFrameCompute(800, 800);
      expect(f.spinner.opacity, greaterThan(0.9));
      expect(f.spinner.dash, greaterThan(0.6));
      expect(f.loadingText, greaterThan(0.9));
      expect(f.avatar.opacity, 0);
      for (final dot in f.dots) {
        expect(dot.opacity, inInclusiveRange(0, 1));
        expect(dot.scale, inInclusiveRange(0.5, 1.3));
      }
    });

    test('第三幕结束（1800ms）：头像/名字/对勾全部就位', () {
      final f = veriWelcomeFrameCompute(1800, 1800);
      expect(f.avatar.opacity, 1);
      expect(f.avatar.scale, 1);
      expect(f.name, closeTo(1, 1e-6));
      expect(f.tick, closeTo(1, 1e-6));
      expect(f.spinner.opacity, 0);
      expect(f.words, 1);
    });

    test('退场段（2500ms）：文字开始淡出', () {
      final f = veriWelcomeFrameCompute(2500, 2500);
      expect(f.words, lessThan(1));
      expect(f.ended, isFalse);
    });

    test('结束（2620ms）：ended 置位', () {
      final f = veriWelcomeFrameCompute(2620, 2620);
      expect(f.ended, isTrue);
    });

    test('负时间被钳制到开场帧', () {
      final f = veriWelcomeFrameCompute(-100, -100);
      expect(f.expand, 0);
      expect(f.flood, 0);
    });

    test('终态帧（减弱动效）：直接显示落定画面', () {
      final f = veriWelcomeEndFrame();
      expect(f.expand, 1);
      expect(f.flood, 1);
      expect(f.avatar.opacity, 1);
      expect(f.name, 1);
      expect(f.tick, 1);
      expect(f.words, 1);
      expect(f.ended, isFalse);
    });

    test('时间轴总长与控制器时长一致', () {
      expect(VeriWelcomeTimeline.duration.inMilliseconds,
          VeriWelcomeTimeline.T.end.toInt());
    });
  });
}
