import { afterEach, describe, expect, it, vi } from 'vitest';
import { answerQuestion, emergencyCommand, sarvamSpeech, speechLanguage, transcribeQuestion } from '../src/voice.js';
vi.mock('../src/config.js', async (original) => ({config: {
  ...(await original<typeof import('../src/config.js')>()).config, SARVAM_API_KEY:'test',
}}));

afterEach(() => vi.restoreAllMocks());
describe('Sarvam voice contract', () => {
  it('never invents surroundings when the camera image is missing', async () => {
    const fetcher=vi.spyOn(globalThis,'fetch');
    expect(await answerQuestion('What is in front of me?',undefined,'en-IN')).toContain('Camera image unavailable');
    expect(await answerQuestion('मेरे सामने क्या है?',undefined,'hi-IN')).toContain('उपलब्ध नहीं');
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('detects the language independently on each utterance', async () => {
    const fetcher = vi.spyOn(globalThis, 'fetch')
      .mockResolvedValueOnce(Response.json({transcript:'मेरे सामने क्या है?',language_code:'hi-IN'}))
      .mockResolvedValueOnce(Response.json({transcript:'என்ன இருக்கிறது?',language_code:'ta-IN'}));
    expect((await transcribeQuestion(new Uint8Array(44))).detectedLanguage).toBe('hi-IN');
    expect((await transcribeQuestion(new Uint8Array(44))).detectedLanguage).toBe('ta-IN');
    for (const [,options] of fetcher.mock.calls) {
      const form = options!.body as FormData;
      expect(form.get('language_code')).toBe('unknown');
      expect(form.get('mode')).toBe('transcribe');
    }
  });
  it('retains Indic vowel marks in SOS commands and ignores incidental mentions', () => {
    for (const command of ['Help!', 'SOS.', 'बचाओ', 'உதவி']) expect(emergencyCommand(command)).toBe(true);
    for (const question of ['Can you help read this label?', 'What does SOS mean?']) expect(emergencyCommand(question)).toBe(false);
  });
  it('maps all supported names and explicitly falls back for unsupported speech', () => {
    expect(speechLanguage('Tamil')).toBe('ta-IN');
    expect(speechLanguage('te-IN')).toBe('te-IN');
    expect(speechLanguage('ur-IN')).toBe('en-IN');
  });
  it('rejects empty recognition and upstream failures', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(Response.json({transcript:' '}))
      .mockResolvedValueOnce(new Response('',{status:429}));
    await expect(transcribeQuestion(new Uint8Array(44))).rejects.toMatchObject({status:422});
    await expect(sarvamSpeech('Hello','en-IN')).rejects.toMatchObject({status:502});
  });
  it('requests streaming MP3 in the detected response language', async () => {
    const fetcher=vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(new Uint8Array([1])));
    await sarvamSpeech('வணக்கம்','ta-IN');
    expect(JSON.parse(fetcher.mock.calls[0][1]!.body as string)).toMatchObject({language_code:'ta-IN',output_audio_codec:'mp3'});
  });
});
