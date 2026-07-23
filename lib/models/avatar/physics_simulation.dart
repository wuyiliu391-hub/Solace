import 'package:flutter/material.dart';

/// Verlet integration 单粒子节点
///
/// 每个可摆动部位（hair_back / hair_front / accessories）持有一个 [Particle]。
/// 头部移动时通过弹簧约束驱动粒子滞后摆动，产生自然的物理效果。
///
/// Verlet 积分公式：
/// ```
/// velocity = (position - previous) * damping
/// previous = position
/// position = position + velocity + externalForce + springForce
/// ```
class Particle {
  /// 当前位置（相对于头部静止锚点）
  Offset position;

  /// 上一帧位置（用于隐式速度计算）
  Offset _previous;

  /// 静止锚点位置（弹簧目标）
  final Offset rest;

  Particle(this.rest)
      : position = rest,
        _previous = rest;

  /// 应用外力并更新位置
  ///
  /// [headVelocity] 头部移动速度（拖拽 / 呼吸位移）
  /// [damping] 阻尼系数（0~1，越大越摇摆）
  /// [stiffness] 弹簧刚度（越大回弹越快）
  /// [mass] 粒子质量（影响惯性）
  void applyForce(
    Offset headVelocity,
    double damping,
    double stiffness,
    double mass,
  ) {
    // 隐式速度 = 当前 - 上一帧
    final velocity = (position - _previous) * damping;
    _previous = position;

    // 弹簧力：朝向静止位置
    final spring = (rest - position) * (stiffness / mass);

    // Verlet 积分
    position = position + velocity + headVelocity + spring;

    // 限制最大偏移，防止飞出画面
    final dx = position.dx.clamp(-20.0, 20.0);
    final dy = position.dy.clamp(-20.0, 20.0);
    position = Offset(dx, dy);
  }

  /// 当前相对于静止位置的偏移量（用于渲染叠加）
  Offset get offset => position - rest;

  /// 重置到静止位置
  void reset() {
    position = rest;
    _previous = rest;
  }
}

/// 链式物理模拟系统
///
/// 管理所有可摆动部位的 [Particle]，每帧通过 [update] 推进模拟。
/// 头部移动速度驱动头发 / 饰品滞后摆动。
///
/// 参数：
/// - [damping] = 0.92（阻尼，保留 92% 速度）
/// - [stiffness] = 0.3（弹簧刚度）
/// - [mass] = 1.0（粒子质量）
class PhysicsSimulation {
  final double damping;
  final double stiffness;
  final double mass;

  /// 可摆动部位 → 粒子映射
  final Map<String, Particle> particles;

  PhysicsSimulation({
    this.damping = 0.92,
    this.stiffness = 0.3,
    this.mass = 1.0,
  }) : particles = {
          'hair_back': Particle(Offset.zero),
          'hair_front': Particle(Offset.zero),
          'accessories': Particle(Offset.zero),
        };

  /// 推进物理模拟一步
  ///
  /// [delta] 距离上一帧的时间间隔（用于帧率归一化）
  /// [headVelocity] 头部移动速度（像素 / 帧）
  ///
  /// 返回每个部位的额外偏移量 Map，可直接叠加到 [AvatarPartSpec.offset]。
  Map<String, Offset> update(Duration delta, Offset headVelocity) {
    // 帧率归一化：60fps 时 scale ≈ 1.0
    final dt = delta.inMilliseconds.toDouble() / 1000.0;
    final frameScale = (dt * 60.0).clamp(0.1, 3.0);
    final scaledVelocity = headVelocity * frameScale;

    for (final p in particles.values) {
      p.applyForce(scaledVelocity, damping, stiffness, mass);
    }

    return particles.map((key, p) => MapEntry(key, p.offset));
  }

  /// 查询某个部位的当前偏移量（未知部位返回 [Offset.zero]）
  Offset offsetFor(String part) {
    final p = particles[part];
    return p?.offset ?? Offset.zero;
  }

  /// 注入冲量（如点击头部时让头发甩动）
  ///
  /// Verlet 技巧：直接移动 position，下一帧的隐式速度就会包含这个位移。
  void injectImpulse(Offset impulse) {
    for (final p in particles.values) {
      p.position = p.position + impulse;
    }
  }

  /// 重置所有粒子到静止位置
  void reset() {
    for (final p in particles.values) {
      p.reset();
    }
  }
}
