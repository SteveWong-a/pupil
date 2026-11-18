import * as THREE from "three";
import {
  BlendFunction,
  BloomEffect,
  DepthOfFieldEffect,
  Effect,
  EffectAttribute,
  EffectComposer,
  EffectPass,
  NoiseEffect,
  RenderPass,
  ToneMappingEffect,
  ToneMappingMode,
  VignetteEffect,
} from "postprocessing";
import { N8AOPostPass } from "n8ao";

class ShutterBlurEffect extends Effect {
  constructor() {
    super(
      "ShutterBlurEffect",
      `
uniform mat4 uReproject;
uniform float uAmount;
void mainImage(const in vec4 inputColor, const in vec2 uv, const in float depth, out vec4 outputColor) {
  vec4 prev = uReproject * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
  vec2 vel = (uv - (prev.xy / max(prev.w, 1e-5)) * 0.5 - 0.5) * uAmount;
  float len = length(vel);
  vel *= len > 0.25 ? 0.0 : min(1.0, 0.035 / max(len, 1e-5));
  vec4 acc = inputColor;
  for (int i = 1; i < 10; i++) acc += texture2D(inputBuffer, uv + vel * (float(i) / 9.0 - 0.5));
  outputColor = acc / 10.0;
}`,
      {
        attributes: EffectAttribute.DEPTH | EffectAttribute.CONVOLUTION,
        uniforms: new Map<string, THREE.Uniform>([
          ["uReproject", new THREE.Uniform(new THREE.Matrix4())],
          ["uAmount", new THREE.Uniform(0)],
        ]),
      },
    );
  }
}

export interface PostLook {
  bokeh: number;
  focusRange: number;
  bloom: number;
  exposure: number;
  focusRow: number;
  motionBlur: number;
}

export type PostPipeline = ReturnType<typeof createPostPipeline>;

export function createPostPipeline(renderer: THREE.WebGLRenderer, scene: THREE.Scene, camera: THREE.PerspectiveCamera, { samples = 2 } = {}) {
  const composer = new EffectComposer(renderer, {
    frameBufferType: THREE.HalfFloatType,
    multisampling: Math.min(samples, renderer.capabilities.maxSamples),
  });
  composer.addPass(new RenderPass(scene, camera));

  const ao = new N8AOPostPass(scene, camera, 1, 1);
  ao.configuration.aoRadius = 0.45;
  ao.configuration.distanceFalloff = 1;
  ao.configuration.intensity = 2.4;
  ao.configuration.halfRes = true;
  ao.configuration.gammaCorrection = false;
  ao.setQualityMode("Low");
  composer.addPass(ao);

  const dof = new DepthOfFieldEffect(camera, {
    focusDistance: 10,
    focusRange: 3,
    bokehScale: 4,
    resolutionScale: 0.5,
  });
  const focusTarget = new THREE.Vector3();
  dof.target = focusTarget;

  const bloom = new BloomEffect({
    intensity: 0.95,
    luminanceThreshold: 1.15,
    luminanceSmoothing: 0.2,
    mipmapBlur: true,
    radius: 0.58,
  });
  const tone = new ToneMappingEffect({ mode: ToneMappingMode.AGX });
  const vignette = new VignetteEffect({ offset: 0.32, darkness: 0.62 });
  const noise = new NoiseEffect({ blendFunction: BlendFunction.OVERLAY, premultiply: false });
  noise.blendMode.opacity.value = 0.05;

  const focusPass = new EffectPass(camera, dof);
  composer.addPass(focusPass);
  const blur = new ShutterBlurEffect();
  const blurPass = new EffectPass(camera, blur);
  composer.addPass(blurPass);
  composer.addPass(new EffectPass(camera, bloom, tone, vignette, noise));

  const fx: PostLook = { bokeh: 4, focusRange: 3, bloom: 1.1, exposure: 1, focusRow: 0, motionBlur: 0 };

  const vp = new THREE.Matrix4();
  const prevVP = new THREE.Matrix4();
  const reproject = blur.uniforms.get("uReproject")!;
  const amount = blur.uniforms.get("uAmount")!;
  let hasPrev = false;

  function apply() {
    focusPass.enabled = fx.bokeh > 0.6;
    vp.multiplyMatrices(camera.projectionMatrix, camera.matrixWorldInverse);
    blurPass.enabled = fx.motionBlur > 0.01 && hasPrev;
    (reproject.value as THREE.Matrix4).copy(vp).invert().premultiply(prevVP);
    amount.value = fx.motionBlur * 0.5;
    prevVP.copy(vp);
    hasPrev = true;
    dof.bokehScale = fx.bokeh;
    dof.cocMaterial.focusRange = fx.focusRange;
    bloom.intensity = fx.bloom;
    renderer.toneMappingExposure = fx.exposure;
  }

  return { composer, focusTarget, ao, fx, apply };
}
