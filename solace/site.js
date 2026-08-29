(() => {
  'use strict';

  // 本站为品牌展示，动效是核心体验，始终播放（不跟随系统「减少动态效果」设置）
  const prefersReduced = false;
  const hasGSAP = typeof window.gsap !== 'undefined' && typeof window.ScrollTrigger !== 'undefined';
  const hasLenis = typeof window.Lenis !== 'undefined';
  const finePointer = window.matchMedia('(pointer: fine)').matches;
  let lenis = null;

  // ── 1. 平滑滚动引擎（Lenis + ScrollTrigger） ──────────────────
  if (hasLenis && hasGSAP && !prefersReduced) {
    lenis = new Lenis({ lerp: .1, wheelMultiplier: 1 });
    lenis.on('scroll', ScrollTrigger.update);
    gsap.ticker.add((time) => { lenis.raf(time * 1000); });
    gsap.ticker.lagSmoothing(0);
    // 开场动画期间暂停平滑滚动
    if (document.getElementById('siteIntro')) lenis.stop();
  }
  if (hasGSAP) gsap.registerPlugin(ScrollTrigger);

  // ── 2. 导航滚动状态 ──────────────────────────────────────────
  const nav = document.querySelector('.site-nav');
  let ticking = false;
  const checkNav = () => {
    nav?.classList.toggle('scrolled', window.scrollY > 20);
    ticking = false;
  };
  window.addEventListener('scroll', () => {
    if (!ticking) { requestAnimationFrame(checkNav); ticking = true; }
  }, { passive: true });
  if (window.scrollY > 20) nav?.classList.add('scrolled');

  // ── 3. 移动端菜单 ────────────────────────────────────────────
  const toggle = document.querySelector('[data-menu-toggle]');
  const links = document.querySelector('.nav-links');
  if (toggle && links) {
    const closeMenu = () => {
      links.classList.remove('open');
      toggle.setAttribute('aria-expanded', 'false');
      document.body.classList.remove('no-scroll');
    };
    toggle.addEventListener('click', () => {
      const willOpen = !links.classList.contains('open');
      links.classList.toggle('open', willOpen);
      toggle.setAttribute('aria-expanded', String(willOpen));
      document.body.classList.toggle('no-scroll', willOpen);
    });
    links.querySelectorAll('a').forEach(a => {
      a.addEventListener('click', closeMenu);
    });
    document.addEventListener('click', (e) => {
      if (links.classList.contains('open') &&
          !toggle.contains(e.target) && !links.contains(e.target)) {
        closeMenu();
      }
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && links.classList.contains('open')) closeMenu();
    });
  }

  // ── 4. 锚点跳转接入平滑滚动 ──────────────────────────────────
  if (lenis) {
    document.querySelectorAll('a[href^="#"]').forEach((a) => {
      a.addEventListener('click', (e) => {
        const id = a.getAttribute('href').slice(1);
        const target = document.getElementById(id);
        if (target) { e.preventDefault(); lenis.scrollTo(target, { offset: -70 }); }
      });
    });
  }

  // ── 5. 滚动渐显（ScrollTrigger 优先，IntersectionObserver 兜底） ──
  const revealEls = document.querySelectorAll('[data-reveal]');
  // 同组兄弟元素按顺序递增入场延迟（stagger 节奏）
  revealEls.forEach((el) => {
    const group = el.parentElement;
    if (!group) return;
    const siblings = [...group.children].filter((c) => c.hasAttribute('data-reveal'));
    const idx = siblings.indexOf(el);
    if (siblings.length > 1 && idx >= 0) el.style.transitionDelay = `${idx * 90}ms`;
  });
  if (revealEls.length) {
    if (hasGSAP) {
      revealEls.forEach((el) => {
        ScrollTrigger.create({
          trigger: el,
          start: 'top 85%',
          once: true,
          onEnter: () => el.classList.add('revealed'),
        });
      });
    } else if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver(
        (entries) => {
          entries.forEach(entry => {
            if (entry.isIntersecting) {
              entry.target.classList.add('revealed');
              observer.unobserve(entry.target);
            }
          });
        },
        { rootMargin: '-40px 0px -60px 0px', threshold: 0.05 }
      );
      revealEls.forEach(el => observer.observe(el));
    } else {
      revealEls.forEach(el => el.classList.add('revealed'));
    }
  }

  // ── 6. Hero 标题字符级动画（保留 <br> 与金色高亮词） ─────────
  const heroH1 = document.querySelector('.hero h1.display');
  if (heroH1 && hasGSAP && !prefersReduced) {
    const frag = document.createDocumentFragment();
    [...heroH1.childNodes].forEach((node) => {
      if (node.nodeType === Node.TEXT_NODE) {
        for (const ch of node.textContent) {
          const span = document.createElement('span');
          span.className = 'ch';
          span.textContent = ch === ' ' ? '\u00A0' : ch;
          frag.appendChild(span);
        }
      } else if (node.nodeName === 'BR') {
        frag.appendChild(node);
      } else {
        node.classList.add('ch', 'ch--unit');
        frag.appendChild(node);
      }
    });
    heroH1.replaceChildren(frag);
    gsap.fromTo('.hero .ch',
      { yPercent: 118, opacity: 0 },
      { yPercent: 0, opacity: 1, duration: .85, stagger: .03, ease: 'power3.out', delay: .3 }
    );
  }

  // ── 7. Hero 光标视差（桌面端） ───────────────────────────────
  const hero = document.querySelector('.hero');
  if (hero && hasGSAP && !prefersReduced && finePointer) {
    const heroQuote = hero.querySelector('.hero-quote');
    const float1 = hero.querySelector('.hq-float--1');
    const float2 = hero.querySelector('.hq-float--2');
    const lights = hero.querySelector('.hero-light');
    hero.addEventListener('pointermove', (e) => {
      const x = (e.clientX / window.innerWidth - .5) * 2;
      const y = (e.clientY / window.innerHeight - .5) * 2;
      if (heroQuote) gsap.to(heroQuote, { x: x * 14, y: y * 9, duration: .9, ease: 'power2.out' });
      if (float1) gsap.to(float1, { x: x * 24, y: y * 15, duration: 1.3, ease: 'power2.out' });
      if (float2) gsap.to(float2, { x: x * -20, y: y * -12, duration: 1.1, ease: 'power2.out' });
      if (lights) gsap.to(lights, { x: x * -8, y: y * -5, duration: .8, ease: 'power2.out' });
    });
  }

  // ── 8. 数字滚动 countup（easeOutExpo） ───────────────────────
  const countEls = document.querySelectorAll('[data-count]');
  if (countEls.length) {
    const animateCount = (el) => {
      const target = parseFloat(el.dataset.count) || 0;
      const dur = 1600;
      const t0 = performance.now();
      const step = (now) => {
        const p = Math.min(1, (now - t0) / dur);
        const eased = p === 1 ? 1 : 1 - Math.pow(2, -10 * p);
        el.textContent = Math.round(target * eased);
        if (p < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    };
    if (hasGSAP) {
      countEls.forEach((el) => {
        ScrollTrigger.create({ trigger: el, start: 'top 88%', once: true, onEnter: () => animateCount(el) });
      });
    } else if ('IntersectionObserver' in window) {
      const io = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) { animateCount(entry.target); io.unobserve(entry.target); }
        });
      }, { threshold: .5 });
      countEls.forEach((el) => io.observe(el));
    } else {
      countEls.forEach((el) => { el.textContent = el.dataset.count; });
    }
  }

  // ── 9. 自定义光标（仅桌面指针设备） ──────────────────────────
  const cursorRing = document.getElementById('cursorRing');
  const cursorDot = document.getElementById('cursorDot');
  if (cursorRing && cursorDot && finePointer) {
    // 只有自定义光标确认初始化后，才隐藏原生光标（避免鼠标消失）
    document.body.classList.add('cursor-active');
    let mx = innerWidth / 2, my = innerHeight / 2;
    let rx = mx, ry = my, dx = mx, dy = my;
    window.addEventListener('mousemove', (e) => { mx = e.clientX; my = e.clientY; }, { passive: true });
    const loop = () => {
      dx += (mx - dx) * .4; dy += (my - dy) * .4;   // 圆点快
      rx += (mx - rx) * .16; ry += (my - ry) * .16; // 圆环慢
      cursorDot.style.transform = `translate(${dx}px, ${dy}px) translate(-50%, -50%)`;
      cursorRing.style.transform = `translate(${rx}px, ${ry}px) translate(-50%, -50%)`;
      requestAnimationFrame(loop);
    };
    loop();
    document.addEventListener('mouseover', (e) => {
      const hit = e.target.closest('a, button, summary, .card, .cap, .step');
      cursorRing.classList.toggle('is-hover', !!hit);
      cursorDot.classList.toggle('is-hover', !!hit);
    });
    document.addEventListener('mousedown', () => cursorRing.classList.add('is-down'));
    document.addEventListener('mouseup', () => cursorRing.classList.remove('is-down'));
  }

  // ── 10. 滚动进度条 ───────────────────────────────────────────
  const progressFill = document.querySelector('.scroll-progress i');
  if (progressFill) {
    const updateProgress = () => {
      const doc = document.documentElement;
      const max = doc.scrollHeight - window.innerHeight;
      progressFill.style.width = `${(max > 0 ? window.scrollY / max : 0) * 100}%`;
    };
    window.addEventListener('scroll', updateProgress, { passive: true });
    updateProgress();
  }

  // ── 11. 页脚年份 ──────────────────────────────────────────────
  const yearSpan = document.querySelector('[data-year]');
  if (yearSpan) yearSpan.textContent = new Date().getFullYear();

  // ── 12. WebGL 关系图谱星图（克制单场景） ──────────────────────
  const webglStage = document.getElementById('webglStage');
  if (webglStage && typeof THREE !== 'undefined' && hasGSAP && !prefersReduced) {
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, 1, 1, 100);
    camera.position.z = 26;
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    webglStage.appendChild(renderer.domElement);

    const COUNT = 150;
    const positions = new Float32Array(COUNT * 3);
    const colors = new Float32Array(COUNT * 3);
    const palette = [
      [.72, .58, .36], [.9, .78, .65],   // 金
      [.42, .55, .94],                    // 蓝
      [.9, .47, .63],                     // 粉
    ];
    const stars = [];
    for (let i = 0; i < COUNT; i++) {
      const r = 6 + Math.random() * 9;
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      const x = r * Math.sin(phi) * Math.cos(theta);
      const y = r * Math.sin(phi) * Math.sin(theta) * .7;
      const z = r * Math.cos(phi) * .8;
      positions[i * 3] = x; positions[i * 3 + 1] = y; positions[i * 3 + 2] = z;
      const c = palette[i % palette.length];
      colors[i * 3] = c[0]; colors[i * 3 + 1] = c[1]; colors[i * 3 + 2] = c[2];
      stars.push({ x, y, z });
    }
    const pGeo = new THREE.BufferGeometry();
    pGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    pGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    const pMat = new THREE.PointsMaterial({
      size: .24, vertexColors: true, transparent: true, opacity: 0,
      depthWrite: false, blending: THREE.AdditiveBlending,
    });
    const points = new THREE.Points(pGeo, pMat);
    scene.add(points);

    // 相邻星点连线（星图骨架）
    const linePos = [];
    for (let i = 0; i < COUNT; i++) {
      for (let j = i + 1; j < COUNT; j++) {
        const dx = stars[i].x - stars[j].x;
        const dy = stars[i].y - stars[j].y;
        const dz = stars[i].z - stars[j].z;
        if (dx * dx + dy * dy + dz * dz < 16) {
          linePos.push(stars[i].x, stars[i].y, stars[i].z, stars[j].x, stars[j].y, stars[j].z);
        }
      }
    }
    const lGeo = new THREE.BufferGeometry();
    lGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(linePos), 3));
    const lMat = new THREE.LineBasicMaterial({
      color: 0xB08D57, transparent: true, opacity: 0, blending: THREE.AdditiveBlending,
    });
    const lines = new THREE.LineSegments(lGeo, lMat);
    scene.add(lines);

    let rotX = 0, rotY = 0, tx = 0, ty = 0;
    webglStage.addEventListener('pointermove', (e) => {
      tx = (e.clientX / window.innerWidth - .5) * .6;
      ty = (e.clientY / window.innerHeight - .5) * .4;
    }, { passive: true });

    const resizeWebgl = () => {
      const w = webglStage.clientWidth || 1;
      const h = webglStage.clientHeight || 1;
      renderer.setSize(w, h);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    resizeWebgl();
    window.addEventListener('resize', resizeWebgl);

    const renderLoop = () => {
      rotY += .0018;
      rotX += (.0006 + ty * .001);
      points.rotation.y = rotY + tx;
      points.rotation.x = rotX;
      lines.rotation.y = rotY + tx;
      lines.rotation.x = rotX;
      renderer.render(scene, camera);
      requestAnimationFrame(renderLoop);
    };
    requestAnimationFrame(renderLoop);

    // 滚动进出：淡入/淡出星图
    ScrollTrigger.create({
      trigger: webglStage,
      start: 'top 80%',
      end: 'bottom 20%',
      onEnter: () => { gsap.to(pMat, { opacity: .9, duration: 1.4, ease: 'power2.out' }); gsap.to(lMat, { opacity: .3, duration: 1.6, delay: .2, ease: 'power2.out' }); },
      onLeaveBack: () => { gsap.to(pMat, { opacity: 0, duration: .8 }); gsap.to(lMat, { opacity: 0, duration: .8 }); },
    });
  }

  // ── 13. 一段关系的旅程 · 横向滚动叙事（pin + scrub） ─────────
  const hTrack = document.querySelector('.h-track');
  const hProgress = document.querySelector('.h-progress i');
  if (hTrack && hasGSAP && !prefersReduced) {
    const dist = () => hTrack.scrollWidth - window.innerWidth;
    gsap.to(hTrack, {
      x: () => -Math.max(dist(), 0),
      ease: 'none',
      scrollTrigger: {
        trigger: '.h-pin',
        start: 'top top',
        end: () => '+=' + (Math.max(dist(), 0) + window.innerHeight * .5),
        scrub: 1,
        pin: true,
        invalidateOnRefresh: true,
        onUpdate: (self) => { if (hProgress) hProgress.style.width = `${self.progress * 100}%`; },
      },
    });
    // 面板逐个入场
    gsap.utils.toArray('.h-panel').forEach((panel, i) => {
      gsap.from(panel, {
        opacity: 0, y: 40, duration: .6, delay: i * .1,
        scrollTrigger: { trigger: '.h-pin', start: 'top top' },
      });
    });

    // 自动推进（幻灯片）：章节在视口内且用户约 2.6s 未操作时，缓慢自动滚动推进
    const hPinEl = document.querySelector('.h-pin');
    if (hPinEl && lenis) {
      let autoAdvance = false;
      let lastUserScroll = 0;
      ['wheel', 'touchstart', 'touchmove'].forEach((ev) => {
        window.addEventListener(ev, () => { lastUserScroll = performance.now(); }, { passive: true });
      });
      const advLoop = () => {
        if (autoAdvance && lenis && performance.now() - lastUserScroll > 2600) {
          lenis.scrollTo(lenis.scroll + 1.7, { duration: .12 });
        }
        requestAnimationFrame(advLoop);
      };
      requestAnimationFrame(advLoop);
      ScrollTrigger.create({
        trigger: hPinEl,
        start: 'top 42%',
        end: 'bottom 58%',
        onToggle: (self) => { autoAdvance = self.isActive; },
      });
    }
  }

  // ── 14. 章节编号指示（0X / 0N） ──────────────────────────────
  const chapterNow = document.getElementById('chapterNow');
  const chapterTotal = document.getElementById('chapterTotal');
  const chapterSections = document.querySelectorAll('main > section, main > .h-scroll');
  if (chapterNow && chapterTotal && chapterSections.length && hasGSAP) {
    chapterTotal.textContent = String(chapterSections.length).padStart(2, '0');
    chapterSections.forEach((sec, i) => {
      ScrollTrigger.create({
        trigger: sec,
        start: 'top 55%',
        end: 'bottom 55%',
        onToggle: (self) => {
          if (self.isActive) chapterNow.textContent = String(i + 1).padStart(2, '0');
        },
      });
    });
  }

  // ── 15. View Transitions（内页过渡，Chrome 系渐进增强） ───────
  if (document.startViewTransition) {
    document.querySelectorAll('a[href$=".html"]').forEach((a) => {
      a.addEventListener('click', (e) => {
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
        if (a.target === '_blank') return;
        const href = a.getAttribute('href');
        if (!href || href.startsWith('http') || href.startsWith('#')) return;
        e.preventDefault();
        document.startViewTransition(() => { window.location.href = href; });
      });
    });
  }

  // ── 16. 时间线滚动动画（about 页） ───────────────────────────
  const tlItems = document.querySelectorAll('.tl-item');
  const tlProgress = document.querySelector('.timeline .tl-progress');
  if (tlItems.length && tlProgress && hasGSAP && !prefersReduced) {
    gsap.fromTo(tlProgress,
      { scaleY: 0 },
      {
        scaleY: 1, ease: 'none',
        scrollTrigger: { trigger: '.timeline', start: 'top 72%', end: 'bottom 45%', scrub: .6 },
      }
    );
    tlItems.forEach((item) => {
      ScrollTrigger.create({
        trigger: item,
        start: 'top 78%',
        onEnter: () => item.classList.add('on'),
      });
    });
  }

  // ── 17. 开场动画（光流交汇 · 微笑爱心） ───────────────────────
  const intro = document.getElementById('siteIntro');
  if (intro) {
    const canvas = document.getElementById('introCanvas');
    const percent = document.getElementById('introPercent');
    const skipBtn = document.getElementById('introSkip');
    // 始终播放完整开场（动效为本站核心体验）
    const reduceMotion = false;
    let ended = false;

    const endIntro = () => {
      if (ended) return;
      ended = true;
      intro.classList.add('intro--done');
      document.body.classList.remove('no-scroll');
      window.removeEventListener('resize', onResize);
      lenis?.start();
      setTimeout(() => intro.remove(), 700);
    };

    // ── 粒子系统：粉蓝颗粒 · 两侧汇聚 → 环绕光团 ──
    const ctx = canvas ? canvas.getContext('2d') : null;
    let W = 0, H = 0, dpr = 1, parts = [];
    const PALETTE = [
      [156, 196, 245],  // 蓝亮
      [91, 141, 239],   // 蓝
      [247, 179, 196],  // 粉亮
      [230, 120, 160],  // 粉
      [176, 141, 87],   // 金（品牌点缀）
    ];

    function onResize() {
      if (!ctx) return;
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      W = canvas.width = window.innerWidth * dpr;
      H = canvas.height = window.innerHeight * dpr;
    }
    onResize();
    window.addEventListener('resize', onResize);

    function initParts() {
      parts = [];
      const n = Math.min(80, Math.max(40, Math.floor(W / 20)));
      for (let i = 0; i < n; i++) {
        const c = PALETTE[Math.floor(Math.random() * PALETTE.length)];
        const side = i % 2 === 0 ? -1 : 1; // 左/右两侧
        parts.push({
          x: (side < 0 ? Math.random() * W * .34 : W - Math.random() * W * .34),
          y: Math.random() * H,
          r: (Math.random() * 2.4 + 1.2) * dpr,
          c,
          side,
          ph: Math.random() * Math.PI * 2,
          orbit: (Math.random() * 95 + 34) * dpr, // 汇聚后的环绕半径
          speed: Math.random() * .8 + .5,
          life: Math.random() * .5 + .25,
        });
      }
    }
    initParts();

    let raf = 0;
    function tick(now) {
      if (!ctx) return; // 防御：canvas 不可用时不抛错
      const t = now / 1000;
      const CX = W / 2;
      const CY = H * .56; // 汇聚点（与 SVG 光团对齐）
      ctx.clearRect(0, 0, W, H);
      for (const p of parts) {
        if (t < 2.1) {
          // 汇聚阶段：从两侧向中心涌入
          p.x += (CX - p.x) * .016 * p.speed * dpr + Math.sin(p.ph + t * 1.4) * .3 * dpr;
          p.y += (CY - p.y) * .008 * p.speed * dpr + Math.cos(p.ph + t) * .22 * dpr;
        } else {
          // 环绕阶段：绕中心光团椭圆流动
          const a = p.ph + t * .75 * p.speed;
          const tx = CX + Math.cos(a) * p.orbit;
          const ty = CY + Math.sin(a) * p.orbit * .55;
          p.x += (tx - p.x) * .07;
          p.y += (ty - p.y) * .07;
        }
        const tw = (Math.sin(p.ph * 2 + t * 1.6) + 1) / 2;
        const alpha = p.life * (0.25 + tw * 0.6);
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(${p.c[0]},${p.c[1]},${p.c[2]},${alpha.toFixed(3)})`;
        ctx.fill();
      }
      raf = requestAnimationFrame(tick);
    }

    if (reduceMotion) {
      // 减少动效：显示静态品牌帧约 1.2s，再淡出（不播放粒子/描边动画）
      document.body.classList.add('no-scroll');
      setTimeout(endIntro, 1200);
    } else {
      document.body.classList.add('no-scroll');
      raf = requestAnimationFrame(tick);

      // 进度百分比与自动结束
      const total = 4600;
      const t0 = performance.now();
      const timer = setInterval(() => {
        const p = Math.min(100, ((performance.now() - t0) / total) * 100);
        if (percent) percent.textContent = Math.round(p) + '%';
        if (p >= 100) {
          clearInterval(timer);
          setTimeout(endIntro, 140);
        }
      }, 40);

      // 点击任意处跳过（跳过按钮与场景内部不重复触发）
      intro.addEventListener('click', (e) => {
        if (e.target.closest('.intro-skip')) return;
        endIntro();
      });
      if (skipBtn) skipBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        endIntro();
      });
      // 兜底：最长 6.5 秒强制结束
      setTimeout(endIntro, 6500);
    }
  }
})();