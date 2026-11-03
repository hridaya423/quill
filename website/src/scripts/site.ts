import gsap from "gsap";
import { CustomEase } from "gsap/CustomEase";
import { daylight } from "./daylight";

gsap.registerPlugin(CustomEase);
gsap.ticker.lagSmoothing(0);
const easeOut = CustomEase.create("quill-out", "0.23,1,0.32,1");
const easeMove = CustomEase.create("quill-move", "0.77,0,0.175,1");

export function start() {
  const hero = document.querySelector<HTMLElement>(".hero")!;
  const canvas = hero.querySelector<HTMLCanvasElement>(".light-canvas")!;
  const art = hero.querySelector<HTMLElement>(".hero-art")!;
  const nav = hero.querySelector<HTMLElement>(".hero-nav")!;
  const bottom = hero.querySelector<HTMLElement>(".hero-bottom")!;
  const copy = hero.querySelector<HTMLElement>(".hero-copy")!;
  const download = hero.querySelector<HTMLAnchorElement>(".download-link")!;
  const skip = hero.querySelector<HTMLButtonElement>(".skip-intro")!;
  const replay = hero.querySelector<HTMLButtonElement>(".replay")!;
  const text = [nav, copy, download];
  const trace = hero.querySelector<SVGSVGElement>(".intro-q")!;
  const path = trace.querySelector("path")!;
  const media = gsap.matchMedia();
  let seenOpening = false;
  try {
    seenOpening = sessionStorage.getItem("quill-opening-v3") === "seen";
  } catch {}
  media.add("(prefers-reduced-motion: no-preference)", () => {
    let surface: ReturnType<typeof daylight> | undefined;
    try {
      surface = daylight(canvas, hero, art);
      if (!seenOpening) {
        surface.uniforms.uMorph.value = 0;
        surface.uniforms.uPlain.value = 1;
        surface.uniforms.uReveal.value = 0;
      }
      surface.render(0);
      hero.classList.add("gl-ready");
    } catch {
      surface = undefined;
    }
    replay.hidden = !surface;
    let visible = !document.hidden;
    let inView = true;
    let pointerX = 0.5;
    let pointerY = 0.5;
    let lastFrame = 0;
    const tick = (time: number) => {
      if (!visible || !surface || !inView || time - lastFrame <= 1 / 40) return;
      surface.uniforms.uPointer.value.x +=
        (pointerX - surface.uniforms.uPointer.value.x) * 0.06;
      surface.uniforms.uPointer.value.y +=
        (pointerY - surface.uniforms.uPointer.value.y) * 0.06;
      surface.render(time);
      lastFrame = time;
    };
    gsap.ticker.add(tick);
    const viewObserver = new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting;
    });
    viewObserver.observe(hero);
    const visibility = () => {
      visible = !document.hidden;
    };
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("pageshow", visibility);
    const pointer = (event: PointerEvent) => {
      const box = hero.getBoundingClientRect();
      pointerX = (event.clientX - box.left) / box.width;
      pointerY = (event.clientY - box.top) / box.height;
    };
    const leave = () => {
      pointerX = 0.5;
      pointerY = 0.5;
    };
    if (matchMedia("(hover: hover) and (pointer: fine)").matches) {
      hero.addEventListener("pointermove", pointer);
      hero.addEventListener("pointerleave", leave);
    }
    const complete = () => {
      skip.hidden = true;
      replay.hidden = !surface;
      nav.inert = false;
      bottom.inert = false;
      nav.removeAttribute("aria-hidden");
      bottom.removeAttribute("aria-hidden");
      try {
        sessionStorage.setItem("quill-opening-v3", "seen");
      } catch {}
    };
    const opening = gsap.timeline({ paused: true, onComplete: complete });
    const configureOpening = () => {
      opening.clear();
      if (!surface) return;
      opening
        .set(surface.uniforms.uMorph, { value: 0 })
        .set(surface.uniforms.uReveal, { value: 0 })
        .set(surface.uniforms.uPlain, { value: 1 })
        .set(text, { autoAlpha: 0, y: 8 })
        .set(trace, { autoAlpha: 1 })
        .set(path, { strokeDasharray: 1, strokeDashoffset: 1 })
        .to(
          path,
          {
            strokeDashoffset: 0,
            autoRound: false,
            duration: 1.05,
            ease: "power2.inOut",
          },
          0,
        )
        .to(
          surface.uniforms.uReveal,
          { value: 1, duration: 0.3, ease: easeOut },
          0.85,
        )
        .to(trace, { autoAlpha: 0, duration: 0.25, ease: easeOut }, 1.05)
        .to(
          surface.uniforms.uMorph,
          { value: 1, duration: 1.0, ease: easeMove },
          1.15,
        )
        .to(
          surface.uniforms.uPlain,
          { value: 0, duration: 0.6, ease: easeOut },
          1.15,
        )
        .to(
          text,
          { autoAlpha: 1, y: 0, duration: 0.5, stagger: 0.07, ease: easeOut },
          2.0,
        );
    };
    configureOpening();
    const finishOpening = () => {
      opening.progress(1).pause();
      complete();
    };
    const play = () => {
      if (!surface) return;
      window.scrollTo({ top: 0, behavior: "instant" });
      skip.hidden = false;
      replay.hidden = true;
      nav.inert = true;
      bottom.inert = true;
      nav.setAttribute("aria-hidden", "true");
      bottom.setAttribute("aria-hidden", "true");
      opening.restart();
    };
    if (!seenOpening && surface) play();
    else finishOpening();
    hero.classList.remove("opening-pending");
    const contextLost = (event: Event) => {
      event.preventDefault();
      finishOpening();
      surface?.dispose();
      surface = undefined;
      replay.hidden = true;
      skip.hidden = true;
      hero.classList.remove("gl-ready");
    };
    const contextRestored = () => {
      try {
        surface = daylight(canvas, hero, art);
        surface.render(0);
        configureOpening();
        finishOpening();
        hero.classList.add("gl-ready");
      } catch {
        surface = undefined;
      }
    };
    canvas.addEventListener("webglcontextlost", contextLost);
    canvas.addEventListener("webglcontextrestored", contextRestored);
    skip.addEventListener("click", finishOpening);
    replay.addEventListener("click", play);
    const wheel = () => {
      if (opening.isActive()) finishOpening();
    };
    hero.addEventListener("wheel", wheel, { passive: true });
    const keyboard = (event: KeyboardEvent) => {
      if (event.key === "Escape" || event.key === "Tab") finishOpening();
    };
    document.addEventListener("keydown", keyboard);
    return () => {
      opening.kill();
      gsap.set(text, { clearProps: "opacity,visibility,transform" });
      gsap.set(trace, { clearProps: "opacity,visibility" });
      complete();
      gsap.ticker.remove(tick);
      surface?.dispose();
      viewObserver.disconnect();
      hero.classList.remove("gl-ready", "opening-pending");
      hero.removeEventListener("pointermove", pointer);
      hero.removeEventListener("pointerleave", leave);
      hero.removeEventListener("wheel", wheel);
      canvas.removeEventListener("webglcontextlost", contextLost);
      canvas.removeEventListener("webglcontextrestored", contextRestored);
      window.removeEventListener("pageshow", visibility);
      document.removeEventListener("visibilitychange", visibility);
      document.removeEventListener("keydown", keyboard);
      skip.removeEventListener("click", finishOpening);
      replay.removeEventListener("click", play);
      skip.hidden = true;
      replay.hidden = true;
    };
  });
  hero.classList.remove("opening-pending");
  window.addEventListener("pagehide", (event) => {
    if (!event.persisted) media.revert();
  });
}
