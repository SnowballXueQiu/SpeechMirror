import { textToSpeech } from '@kit.CoreSpeechKit';

export class SpeechOutput {
  private engine?: textToSpeech.TextToSpeechEngine = undefined;
  private currentRequestId: string = '';
  private sequence: number = 0;
  private stateCallback?: (speaking: boolean) => void = undefined;
  private completionCallback?: () => void = undefined;

  private async createEngine(): Promise<textToSpeech.TextToSpeechEngine> {
    let language = 'zh-CN';
    let person = 0;
    try {
      const voices = await textToSpeech.listVoices({
        requestId: 'speechmirror_voice_' + String(Date.now()),
        online: 0
      });
      for (let index = 0; index < voices.length; index += 1) {
        if (voices[index].language === 'zh-CN' || voices[index].language.startsWith('zh')) {
          language = voices[index].language;
          person = voices[index].person;
          break;
        }
      }
    } catch (reason) {
      console.warn('SpeechMirror TTS voice query failed: ' + String(reason));
    }

    const engine = await textToSpeech.createEngine({ language, person, online: 0 });
    engine.setListener({
      onStart: (requestId: string) => {
        if (requestId === this.currentRequestId) this.stateCallback?.(true);
      },
      onComplete: (requestId: string, response: textToSpeech.CompleteResponse) => {
        if (requestId === this.currentRequestId && response.type === 1) this.finish(requestId);
      },
      onStop: (requestId: string) => {
        if (requestId === this.currentRequestId) this.finish(requestId);
      },
      onError: (requestId: string, errorCode: number, errorMessage: string) => {
        console.warn('SpeechMirror TTS failed: ' + String(errorCode) + ' ' + errorMessage);
        if (requestId === this.currentRequestId) this.finish(requestId);
      }
    });
    return engine;
  }

  private finish(requestId: string): void {
    if (requestId !== this.currentRequestId) return;
    this.currentRequestId = '';
    this.stateCallback?.(false);
    const completion = this.completionCallback;
    this.stateCallback = undefined;
    this.completionCallback = undefined;
    completion?.();
  }

  async speak(
    text: string,
    onState: (speaking: boolean) => void,
    onComplete: () => void
  ): Promise<boolean> {
    if (text.trim().length === 0) {
      return false;
    }
    try {
      if (this.engine === undefined) this.engine = await this.createEngine();
      if (this.engine.isBusy()) this.engine.stop();
      this.sequence += 1;
      this.currentRequestId = 'speechmirror_' + String(Date.now()) + '_' + String(this.sequence);
      this.stateCallback = onState;
      this.completionCallback = onComplete;
      this.engine.speak(text.trim(), { requestId: this.currentRequestId });
      return true;
    } catch (reason) {
      console.warn('SpeechMirror TTS unavailable: ' + String(reason));
      this.currentRequestId = '';
      this.stateCallback = undefined;
      this.completionCallback = undefined;
      onState(false);
      return false;
    }
  }

  stop(): void {
    if (this.engine === undefined) return;
    try {
      if (this.engine.isBusy()) this.engine.stop();
    } catch (_) {
    }
  }

  shutdown(): void {
    if (this.engine === undefined) return;
    try {
      this.engine.shutdown();
    } catch (_) {
    }
    this.engine = undefined;
    this.currentRequestId = '';
    this.stateCallback = undefined;
    this.completionCallback = undefined;
  }
}
