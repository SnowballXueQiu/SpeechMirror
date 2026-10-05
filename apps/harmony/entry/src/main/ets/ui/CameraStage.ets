import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';

@Component
export struct CameraStage {
  @State private ready: boolean = false;
  @State private unavailable: boolean = false;
  private surfaceController: XComponentController = new XComponentController();
  private cameraInput?: camera.CameraInput = undefined;
  private previewOutput?: camera.PreviewOutput = undefined;
  private session?: camera.Session = undefined;
  private opening: boolean = false;

  aboutToDisappear(): void {
    this.releaseCamera();
  }

  private async openCamera(): Promise<void> {
    if (this.opening || this.ready) return;
    this.opening = true;
    this.unavailable = false;
    try {
      const permissionManager = abilityAccessCtrl.createAtManager();
      const permissions: Permissions[] = ['ohos.permission.CAMERA'];
      const permissionResult = await permissionManager.requestPermissionsFromUser(getContext(this), permissions);
      if (permissionResult.authResults.length === 0 || permissionResult.authResults[0] !== 0) {
        throw new Error('camera permission denied');
      }

      const manager = camera.getCameraManager(getContext(this));
      const devices = manager.getSupportedCameras();
      if (devices.length === 0) throw new Error('camera unavailable');
      let selected = devices[0];
      for (const device of devices) {
        if (device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT) {
          selected = device;
          break;
        }
      }
      const modes = manager.getSupportedSceneModes(selected);
      const mode = modes.includes(camera.SceneMode.NORMAL_VIDEO) ?
        camera.SceneMode.NORMAL_VIDEO : camera.SceneMode.NORMAL_PHOTO;
      const capability = manager.getSupportedOutputCapability(selected, mode);
      if (capability.previewProfiles.length === 0) throw new Error('preview unavailable');
      let profile = capability.previewProfiles[0];
      let bestScore = Number.MAX_VALUE;
      for (const candidate of capability.previewProfiles) {
        const candidatePixels = candidate.size.width * candidate.size.height;
        if (candidatePixels < 300000 || candidatePixels > 2073600) continue;
        const longSide = Math.max(candidate.size.width, candidate.size.height);
        const shortSide = Math.min(candidate.size.width, candidate.size.height);
        const ratioScore = Math.abs(longSide / shortSide - 16 / 9);
        const resolutionScore = (2073600 - candidatePixels) / 2073600 * 0.03;
        const score = ratioScore + resolutionScore;
        if (score < bestScore) {
          bestScore = score;
          profile = candidate;
        }
      }

      const surfaceRect = this.surfaceController.getXComponentSurfaceRect();
      const portraitRatio = Math.min(profile.size.width, profile.size.height) /
        Math.max(profile.size.width, profile.size.height);
      const componentRatio = surfaceRect.surfaceWidth / surfaceRect.surfaceHeight;
      if (portraitRatio > componentRatio) {
        const coverWidth = surfaceRect.surfaceHeight * portraitRatio;
        this.surfaceController.setXComponentSurfaceRect({
          offsetX: (surfaceRect.surfaceWidth - coverWidth) / 2,
          offsetY: 0,
          surfaceWidth: coverWidth,
          surfaceHeight: surfaceRect.surfaceHeight
        });
      } else {
        const coverHeight = surfaceRect.surfaceWidth / portraitRatio;
        this.surfaceController.setXComponentSurfaceRect({
          offsetX: 0,
          offsetY: (surfaceRect.surfaceHeight - coverHeight) / 2,
          surfaceWidth: surfaceRect.surfaceWidth,
          surfaceHeight: coverHeight
        });
      }
      const surfaceId = this.surfaceController.getXComponentSurfaceId();

      const input = manager.createCameraInput(selected);
      await input.open();
      const output = manager.createPreviewOutput(profile, surfaceId);
      const session = manager.createSession(mode);
      session.beginConfig();
      session.addInput(input);
      session.addOutput(output);
      await session.commitConfig();
      await session.start();
      this.cameraInput = input;
      this.previewOutput = output;
      this.session = session;
      this.ready = true;
    } catch (_) {
      this.unavailable = true;
      await this.releaseCamera();
    } finally {
      this.opening = false;
    }
  }

  private async releaseCamera(): Promise<void> {
    const session = this.session;
    const output = this.previewOutput;
    const input = this.cameraInput;
    this.session = undefined;
    this.previewOutput = undefined;
    this.cameraInput = undefined;
    this.ready = false;
    try {
      await session?.stop();
      await session?.release();
      await output?.release();
      await input?.close();
    } catch (_) {
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#1A211D', 0.0], ['#101411', 0.48], ['#080A09', 1.0]]
        })
      XComponent({
        id: 'speechmirror-camera',
        type: XComponentType.SURFACE,
        controller: this.surfaceController
      })
        .width('100%')
        .height('100%')
        .opacity(this.ready ? 1 : 0)
        // The emulator delivers a letterboxed portrait preview. Scale the
        // complete surface uniformly so the live image behaves like cover.
        .scale({ x: -1.8, y: 1.8 })
        .onLoad(() => this.openCamera())
        .onDestroy(() => this.releaseCamera())
      if (this.unavailable) {
        Column({ space: 12 }) {
          Text('▱').fontSize(44).fontColor('#66FFFFFF').rotate({ angle: -12 })
          Text('未检测到摄像头').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#88FFFFFF')
        }.alignItems(HorizontalAlign.Center)
      }
    }
      .width('100%')
      .height('100%')
      .backgroundColor('#0D100E')
      .expandSafeArea(
        [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        [SafeAreaEdge.TOP]
      )
  }
}
