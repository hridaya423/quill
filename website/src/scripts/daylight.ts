import { Renderer, Program, Mesh, Triangle, Texture, Vec2, Vec4 } from "ogl";
import brand from "../data/brand.json";

const vertex = `
attribute vec2 position;
attribute vec2 uv;
varying vec2 vUv;
void main(){vUv=uv;gl_Position=vec4(position,0.0,1.0);}
`;

const fragment = `
precision highp float;
varying vec2 vUv;
uniform vec2 uResolution;
uniform vec2 uPointer;
uniform vec4 uRect;
uniform vec4 uQRect;
uniform sampler2D uQ;
uniform sampler2D uLetters;
uniform float uTime;
uniform float uMorph;
uniform float uReveal;
uniform float uPlain;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);}
vec3 field(vec2 p){
  float t=uTime*.12;
  float n=noise(p*3.1+vec2(t*.07,-t*.05));
  float diagonal=p.y+p.x*.43;
  float fold=diagonal-.66+sin(p.x*3.7+t)*.065+sin(p.y*4.0-t*.3)*.018;
  float light=exp(-pow(fold/.075,2.0))*.17;
  float shade=exp(-pow((fold-.11)/.16,2.0))*.075;
  float tone=clamp(p.x*.68+p.y*.35+n*.10-.12,0.0,1.0);
  vec3 col=mix(vec3(.972,.984,.996),vec3(.486,.721,.910),smoothstep(.10,.65,tone));
  col=mix(col,vec3(-.02,.26,.62),smoothstep(.45,.95,tone));
  col+=light;
  col-=shade*vec3(1.0,.45,.12);
  col+=vec3(-.012,.012,.028)*sin(p.x*2.4+p.y*2.1+t*.1);
  return col;
}
float mask(sampler2D tex,vec2 p,vec4 rect){
  vec2 uv=(p-rect.xy)/rect.zw;
  return texture2D(tex,uv).a*step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
}
float letters(vec2 p){return max(mask(uQ,p,uQRect)*uReveal,mask(uLetters,p,uRect)*smoothstep(.08,.8,uMorph));}
void main(){
  vec2 uv=vec2(vUv.x,1.0-vUv.y);
  vec2 distance=uv-uPointer;
  vec2 shift=distance*exp(-dot(distance,distance)*9.0)*.025;
  vec2 p=uv+shift;
  float m=letters(uv);
  vec2 pixel=vec2(1.5)/uResolution;
  float x=letters(uv+vec2(pixel.x,0.0))-letters(uv-vec2(pixel.x,0.0));
  float y=letters(uv+vec2(0.0,pixel.y))-letters(uv-vec2(0.0,pixel.y));
  float edge=length(vec2(x,y));
  vec2 normal=vec2(x,y)/(edge+.0001);
  vec3 col=field(p);
  vec3 glass=field(p+normal*.008+vec2(.022,-.018));
  glass=mix(glass,vec3(.15,.48,.70),.28);
  glass*=vec3(.89,.97,1.005);
  col=mix(col,glass,m*.9);
  float shine=max(dot(normal,normalize(vec2(1.0,1.0))),0.0);
  float dark=max(dot(normal,normalize(vec2(-1.0,-1.0))),0.0);
  col+=edge*shine*.20;
  col-=edge*dark*vec3(.22,.15,.05);
  float grain=(hash(gl_FragCoord.xy)-.5)*.027;
  float fine=(hash(gl_FragCoord.xy*.47+27.0)-.5)*.008;
  col+=grain+fine;
  col=mix(col,vec3(.223529,.407843,.6),m*uPlain);
  gl_FragColor=vec4(clamp(col,0.0,1.0),1.0);
}
`;

export function daylight(
  canvas: HTMLCanvasElement,
  hero: HTMLElement,
  mark: HTMLElement,
) {
  const renderer = new Renderer({
    canvas,
    alpha: false,
    antialias: false,
    dpr: Math.min(devicePixelRatio, 1.6),
    powerPreference: "low-power",
  });
  const gl = renderer.gl;
  const texture = (path: string) => {
    const surface = document.createElement("canvas");
    surface.width = 2048;
    surface.height = 1080;
    const ctx = surface.getContext("2d")!;
    ctx.scale(surface.width / 2157.9, surface.height / 1137.2);
    ctx.translate(442.9, 561);
    ctx.fillStyle = "#fff";
    ctx.fill(new Path2D(path), "evenodd");
    return new Texture(gl, {
      image: new Uint8Array(
        ctx.getImageData(0, 0, surface.width, surface.height).data,
      ),
      width: surface.width,
      height: surface.height,
      flipY: false,
      generateMipmaps: false,
      minFilter: gl.LINEAR,
      magFilter: gl.LINEAR,
    });
  };
  const q = texture(brand.q);
  const letters = texture(brand.uill);
  const uniforms = {
    uResolution: { value: new Vec2() },
    uPointer: { value: new Vec2(0.5, 0.5) },
    uRect: { value: new Vec4() },
    uQRect: { value: new Vec4() },
    uQ: { value: q },
    uLetters: { value: letters },
    uTime: { value: 0 },
    uMorph: { value: 1 },
    uReveal: { value: 1 },
    uPlain: { value: 0 },
  };
  const geometry = new Triangle(gl);
  const program = new Program(gl, {
    vertex,
    fragment,
    uniforms,
    depthTest: false,
    depthWrite: false,
  });
  if (!gl.getProgramParameter(program.program, gl.LINK_STATUS)) {
    geometry.remove();
    program.remove();
    gl.deleteTexture(q.texture);
    gl.deleteTexture(letters.texture);
    throw new Error("Daylight shader could not link");
  }
  const mesh = new Mesh(gl, { geometry, program });
  let final = [0, 0, 1, 1];
  let initial = [0, 0, 1, 1];
  const place = () => {
    const progress = uniforms.uMorph.value;
    uniforms.uRect.value.set(final[0], final[1], final[2], final[3]);
    uniforms.uQRect.value.set(
      ...(initial.map((v, i) => v + (final[i] - v) * progress) as [
        number,
        number,
        number,
        number,
      ]),
    );
  };
  const resize = () => {
    const box = hero.getBoundingClientRect();
    const art = mark.getBoundingClientRect();
    renderer.dpr = Math.min(devicePixelRatio, 1.6);
    renderer.setSize(box.width, box.height);
    uniforms.uResolution.value.set(gl.canvas.width, gl.canvas.height);
    final = [
      (art.left - box.left) / box.width,
      (art.top - box.top) / box.height,
      art.width / box.width,
      art.height / box.height,
    ];
    const height =
      (Math.min(320, Math.max(180, box.height * 0.32)) * 1137.2) / 965.6282;
    const width = (height * 2157.9) / 1137.2;
    initial = [
      (0.5 * box.width - (height * (442.9 + 8.30735)) / 1137.2) / box.width,
      (box.height * 0.5 - (height * (561 + 69.3859)) / 1137.2) / box.height,
      width / box.width,
      height / box.height,
    ];
    place();
  };
  resize();
  const observer = new ResizeObserver(resize);
  observer.observe(hero);
  return {
    uniforms,
    render(time: number) {
      uniforms.uTime.value = time;
      place();
      renderer.render({ scene: mesh });
    },
    dispose() {
      observer.disconnect();
      geometry.remove();
      program.remove();
      gl.deleteTexture(q.texture);
      gl.deleteTexture(letters.texture);
    },
  };
}
