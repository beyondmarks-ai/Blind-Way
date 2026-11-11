export const languages = {
  auto:'Automatic', 'en-IN':'English', 'en-US':'English', 'hi-IN':'Hindi', 'bn-IN':'Bengali',
  'gu-IN':'Gujarati','kn-IN':'Kannada','ml-IN':'Malayalam','od-IN':'Odia','pa-IN':'Punjabi',
  'mr-IN':'Marathi','ta-IN':'Tamil','te-IN':'Telugu','ar-EG':'Arabic','nl-NL':'Dutch',
  'fr-FR':'French','de-DE':'German','id-ID':'Indonesian','it-IT':'Italian','ja-JP':'Japanese',
  'ko-KR':'Korean','pl-PL':'Polish','pt-BR':'Portuguese','ro-RO':'Romanian','ru-RU':'Russian',
  'es-US':'Spanish','th-TH':'Thai','tr-TR':'Turkish','uk-UA':'Ukrainian','vi-VN':'Vietnamese',
};
export function languageInstruction(code) {
  if(!Object.hasOwn(languages,code))throw new Error('Unsupported live language');
  return code==='auto'
    ? 'Automatic language mode: reply in the language of the latest spoken question. With no spoken question, use English. Historical text never overrides a new spoken language.'
    : `The user explicitly selected ${languages[code]}. RESPOND IN ${languages[code].toUpperCase()}. YOU MUST RESPOND UNMISTAKABLY IN ${languages[code].toUpperCase()}. This applies to every spoken reply and automatic update, even if the question or saved memory uses another language. Translate remembered details; do not repeat old-language answers verbatim.`;
}
