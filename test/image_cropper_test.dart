import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solace/widgets/image_cropper.dart';

void main() {
  group('CropGeometry.effectiveSize — 旋转后的显示尺寸', () {
    test('0° / 180° 保持原宽高', () {
      expect(CropGeometry.effectiveSize(800, 400, 0), const Size(800, 400));
      expect(CropGeometry.effectiveSize(800, 400, 2), const Size(800, 400));
    });

    test('90° / 270° 交换宽高', () {
      expect(CropGeometry.effectiveSize(800, 400, 1), const Size(400, 800));
      expect(CropGeometry.effectiveSize(800, 400, 3), const Size(400, 800));
    });

    test('非正尺寸兜底为 1x1，避免除零', () {
      expect(CropGeometry.effectiveSize(0, 0, 0), const Size(1, 1));
      expect(CropGeometry.effectiveSize(-5, 10, 1), const Size(1, 1));
    });
  });

  group('CropGeometry.coverScale — 刚好铺满取景框', () {
    test('横图按高度铺满', () {
      // 800x400 放进 400x400：高度是瓶颈 → scale = 1
      expect(CropGeometry.coverScale(const Size(800, 400), 400), 1.0);
    });

    test('竖图按宽度铺满', () {
      // 400x800 放进 400x400：宽度是瓶颈 → scale = 1
      expect(CropGeometry.coverScale(const Size(400, 800), 400), 1.0);
    });

    test('小图被放大到至少铺满', () {
      expect(CropGeometry.coverScale(const Size(200, 100), 400), 4.0);
    });

    test('非法输入返回 1，不抛异常', () {
      expect(CropGeometry.coverScale(const Size(0, 0), 400), 1.0);
      expect(CropGeometry.coverScale(const Size(100, 100), 0), 1.0);
    });

    test('coverScale 保证两个方向都不小于取景框', () {
      const box = 300.0;
      const cases = <Size>[
        const Size(800, 400),
        const Size(400, 800),
        const Size(500, 500),
        const Size(120, 900),
      ];
      for (final disp in cases) {
        final s = CropGeometry.coverScale(disp, box);
        expect(disp.width * s, greaterThanOrEqualTo(box - 1e-9),
            reason: '宽方向必须铺满 $disp');
        expect(disp.height * s, greaterThanOrEqualTo(box - 1e-9),
            reason: '高方向必须铺满 $disp');
      }
    });
  });

  group('CropGeometry.clampScale — 缩放上下限', () {
    test('不允许缩到比 coverScale 更小（否则露白）', () {
      expect(CropGeometry.clampScale(0.1, 2.0), 2.0);
    });

    test('上限为 coverScale 的 4 倍', () {
      expect(CropGeometry.clampScale(999, 2.0), 8.0);
    });

    test('区间内原样返回', () {
      expect(CropGeometry.clampScale(3.0, 2.0), 3.0);
      expect(CropGeometry.clampScale(2.0, 2.0), 2.0);
      expect(CropGeometry.clampScale(8.0, 2.0), 8.0);
    });
  });

  group('CropGeometry.clampOffset — 平移不能露出白边', () {
    const box = 400.0;
    const disp = Size(800, 400);

    test('coverScale 恰好铺满高度时，水平方向可自由移动', () {
      // 800x400, scale=1 → 高度正好 400，垂直方向不能动
      final o = CropGeometry.clampOffset(const Offset(999, 999), disp, box, 1.0);
      expect(o.dx, 200.0); // (800-400)/2
      expect(o.dy, 0.0); // (400-400)/2 = 0
    });

    test('放大后两个方向都可移动，且不越界', () {
      final o = CropGeometry.clampOffset(const Offset(9999, 9999), disp, box, 2.0);
      expect(o.dx, 600.0); // (1600-400)/2
      expect(o.dy, 200.0); // (800-400)/2
    });

    test('clamp 后图片四边始终覆盖取景框', () {
      final raws = <Offset>[
        Offset.zero,
        const Offset(100, 100),
        const Offset(-100, -100),
        const Offset(99999, -99999),
      ];
      for (final scale in [1.0, 1.5, 2.0, 4.0]) {
        for (final raw in raws) {
          final o = CropGeometry.clampOffset(raw, disp, box, scale);
          final shownW = disp.width * scale;
          final shownH = disp.height * scale;
          // 中心 + 位移 之后仍要盖住 [-box/2, box/2]
          expect(o.dx - shownW / 2, lessThanOrEqualTo(-box / 2 + 1e-9));
          expect(o.dx + shownW / 2, greaterThanOrEqualTo(box / 2 - 1e-9));
          expect(o.dy - shownH / 2, lessThanOrEqualTo(-box / 2 + 1e-9));
          expect(o.dy + shownH / 2, greaterThanOrEqualTo(box / 2 - 1e-9));
        }
      }
    });

    test('box 非法时原样返回', () {
      const raw = Offset(5, 6);
      expect(CropGeometry.clampOffset(raw, disp, 0, 1.0), raw);
    });
  });

  group('CropGeometry.offsetForScale — 缩放时焦点保持不动', () {
    test('焦点下的图像局部坐标在缩放前后一致（核心不变量）', () {
      const startScale = 2.0;
      const startOffset = Offset(30, -20);
      const focal = Offset(60, 40);
      for (final newScale in [1.0, 2.0, 3.7, 8.0]) {
        final newOffset = CropGeometry.offsetForScale(
          focal: focal,
          startScale: startScale,
          startOffset: startOffset,
          newScale: newScale,
        );
        // 缩放前：focal = offset + p * scale  =>  p = (focal - offset)/scale
        final pxBefore = (focal.dx - startOffset.dx) / startScale;
        final pyBefore = (focal.dy - startOffset.dy) / startScale;
        // 缩放后同一 p 仍落在 focal
        final pxAfter = (focal.dx - newOffset.dx) / newScale;
        final pyAfter = (focal.dy - newOffset.dy) / newScale;
        expect(pxAfter, closeTo(pxBefore, 1e-9));
        expect(pyAfter, closeTo(pyBefore, 1e-9));
      }
    });

    test('startScale 非法时返回原点而不是 NaN', () {
      final o = CropGeometry.offsetForScale(
        focal: const Offset(10, 10),
        startScale: 0,
        startOffset: const Offset(5, 5),
        newScale: 2,
      );
      expect(o, Offset.zero);
    });

    test('scale 不变时位移保持不变', () {
      final o = CropGeometry.offsetForScale(
        focal: const Offset(60, 40),
        startScale: 2.0,
        startOffset: const Offset(30, -20),
        newScale: 2.0,
      );
      expect(o.dx, closeTo(30, 1e-9));
      expect(o.dy, closeTo(-20, 1e-9));
    });
  });

  group('CropTransform', () {
    test('initial 是未缩放未旋转的零位移', () {
      const t = CropTransform.initial;
      expect(t.scale, 1.0);
      expect(t.offset, Offset.zero);
      expect(t.quarterTurns, 0);
    });
  });

  group('CropGeometry 非正方形取景框（背景图横竖屏）', () {
    const wide = Size(1600, 900); // 横屏取景框
    const tall = Size(900, 1600); // 竖屏取景框

    test('coverScaleForBox 按瓶颈边铺满', () {
      // 1600x900 的图放进 1600x900 框 -> scale 1
      expect(CropGeometry.coverScaleForBox(const Size(1600, 900), wide), 1.0);
      // 900x1600 的竖图放进横屏框：宽度是瓶颈 -> 1600/900
      expect(CropGeometry.coverScaleForBox(const Size(900, 1600), wide),
          closeTo(1600 / 900, 1e-9));
    });

    test('coverScaleForBox 两个方向都不小于取景框', () {
      final cases = <List<Size>>[
        [const Size(4000, 3000), wide],
        [const Size(3000, 4000), wide],
        [const Size(4000, 3000), tall],
        [const Size(1080, 2400), wide],
        [const Size(500, 500), wide],
      ];
      for (final c in cases) {
        final s = CropGeometry.coverScaleForBox(c[0], c[1]);
        expect(c[0].width * s, greaterThanOrEqualTo(c[1].width - 1e-9),
            reason: '宽方向必须铺满 ${c[0]} -> ${c[1]}');
        expect(c[0].height * s, greaterThanOrEqualTo(c[1].height - 1e-9),
            reason: '高方向必须铺满 ${c[0]} -> ${c[1]}');
      }
    });

    test('coverScale 是 coverScaleForBox 在正方形下的特例', () {
      const disp = Size(800, 400);
      expect(CropGeometry.coverScale(disp, 400),
          closeTo(CropGeometry.coverScaleForBox(disp, const Size(400, 400)),
              1e-12));
    });

    test('clampOffsetForBox 宽幅下垂直方向不能露白', () {
      // 图 1600x900, scale 1 -> 高度正好等于框高，垂直方向位移必须为 0
      final o = CropGeometry.clampOffsetForBox(
          const Offset(9999, 9999), const Size(1600, 900), wide, 1.0);
      expect(o.dy, 0.0);
      expect(o.dx, 0.0); // 宽度也正好等于框宽
    });

    test('clampOffsetForBox 放大后两轴都可移动且不越界', () {
      // 注意输入 dy 是 -99999，clamp 后应保留负号
      final o = CropGeometry.clampOffsetForBox(
          const Offset(99999, -99999), const Size(1600, 900), wide, 2.0);
      expect(o.dx, 800.0); // (3200-1600)/2
      expect(o.dy, -450.0); // -(1800-900)/2
    });

    test('clampOffsetForBox 各种缩放下四边始终覆盖取景框', () {
      for (final scale in [1.0, 1.3, 2.0, 4.0]) {
        for (final raw in const [
          Offset.zero,
          Offset(50, -50),
          Offset(-99999, 99999),
        ]) {
          final o = CropGeometry.clampOffsetForBox(
              raw, const Size(1600, 900), wide, scale);
          final sw = 1600 * scale;
          final sh = 900 * scale;
          expect(o.dx - sw / 2, lessThanOrEqualTo(-wide.width / 2 + 1e-9));
          expect(o.dx + sw / 2, greaterThanOrEqualTo(wide.width / 2 - 1e-9));
          expect(o.dy - sh / 2, lessThanOrEqualTo(-wide.height / 2 + 1e-9));
          expect(o.dy + sh / 2, greaterThanOrEqualTo(wide.height / 2 - 1e-9));
        }
      }
    });

    test('竖屏取景框同样成立', () {
      const img = Size(1080, 1920);
      // 1080x1920 放进 900x1600：两轴比例一致，cover 缩放后正好贴合
      final s = CropGeometry.coverScaleForBox(img, tall);
      expect(s, closeTo(1600 / 1920, 1e-9));
      // 低于 cover 的缩放会被抬回 cover，正好不露白
      final s2 = CropGeometry.clampScale(0.1, s);
      expect(s2, closeTo(s, 1e-12));

      final o = CropGeometry.clampOffsetForBox(
          const Offset(999, 999), img, tall, s2);
      expect(o.dx.abs(), lessThanOrEqualTo((img.width * s2 - tall.width) / 2 + 1e-9));
      expect(o.dy.abs(), lessThanOrEqualTo((img.height * s2 - tall.height) / 2 + 1e-9));
    });

    test('非法取景框原样返回', () {
      const raw = Offset(3, 4);
      expect(
          CropGeometry.clampOffsetForBox(
              raw, const Size(100, 100), Size.zero, 1.0),
          raw);
    });
  });
}
