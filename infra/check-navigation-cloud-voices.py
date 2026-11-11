"""Manual provider check using bundled product text, not user recordings."""
import base64, concurrent.futures, json, os, pathlib, subprocess, urllib.request

root=pathlib.Path(__file__).resolve().parent.parent
catalog=json.loads((root/'infra/navigation-translations.json').read_text(encoding='utf-8'))
project='project-8eeef9d3-080a-4f49-95e'
account_args=['--account='+os.environ['BLIND_WAY_GCP_ACCOUNT']] if os.environ.get('BLIND_WAY_GCP_ACCOUNT') else []
token=subprocess.run(['gcloud.cmd','auth','print-access-token',*account_args],capture_output=True,text=True,check=True).stdout.strip()
headers={'Authorization':'Bearer '+token,'x-goog-user-project':project,'Content-Type':'application/json'}
locales=['ar-EG','nl-NL','en-US','fr-FR','de-DE','id-ID','it-IT','ja-JP','ko-KR','pl-PL','pt-BR','ro-RO','ru-RU','es-US','th-TH','tr-TR','uk-UA','vi-VN']
def check(locale):
    text=catalog[locale]['Walking navigation stopped.']
    body=json.dumps({'input':{'text':text},'voice':{'languageCode':'ar-XA' if locale=='ar-EG' else locale},'audioConfig':{'audioEncoding':'MP3'}}).encode()
    with urllib.request.urlopen(urllib.request.Request('https://texttospeech.googleapis.com/v1/text:synthesize',headers=headers,data=body),timeout=25) as response:data=json.load(response)
    audio=base64.b64decode(data['audioContent']);assert len(audio)>100
    return {'language':locale,'mp3Bytes':len(audio)}
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    for result in pool.map(check,locales):print(json.dumps(result),flush=True)
