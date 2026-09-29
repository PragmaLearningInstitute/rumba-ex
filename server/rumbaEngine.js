const COMMON_WORDS_INLINE = `
a abord about above across afin after afterwards again against ago ah ahead ai aie aient aies ailleurs ain ainsi ait all allaient allo allons almost alone along already also although always am among amongst an analyse analysed analysing analyze analyzed analyzing and another any anybody anyhow anyone anything anyway anywhere apres après are aren around as aside ask asked asking asks assez at attendu attention au aucun aucune aujourd aujourd'hui aupres auprès auquel aura auraient aurais aurait auras aurez auriez aurions aurons auront aussi autre autres autrui aux auxquelles auxquels avaient avais avait avant avec avez aviez avions avoir avons away ayant ayez ayons back backward backwards bah be beaucoup became because become becomes becoming been before beforehand begin begins behavior behaviour behind being below beneath beside besides best better between beyond bien bientot bientôt bon bonjour bonne bonnes bons both bravo bref brief but by c ca came can cannot cant caption car catalog catalogue cause causes ce ceci cela celle celle-ci celle-là celles celles-ci celles-là celui celui-ci celui-là cent center centre cependant certain certaine certaines certainly certains certes ces cet cette ceux ceux-ci ceux-là chacun chacune change changes chaque check checked checking checks cher chere cheres chers chez chiche chut chère chères ci clearly co color colour combien come comes comme comment comprehension concernant concerning consequently consider considering contain containing contains contre couic could couldn course crac currently customise customize d da dans dare daren day de debout dedans defence defense definitely dehors deja delà depuis derriere derrière des desormais despite desquelles desquels dessous dessus deux deuxieme deuxième devant devers devra devraient devrais devrait devrons devront di dialog dialogue did didn different differente differentes differents difficult difficulty différente différentes différents dire divers diverse diverses dix do does doesn doing doit doivent don donc done dont douze down downward downwards du duquel durant during dyslexia dyslexic déjà désormais e each early easier effet eh either elle elle-même elles elles-mêmes else elsewhere en encore enough enrol enroll entirely entre envers es especially est et etaient etais etait etant etc ete etre eu euh eux eux-mêmes even ever every everybody everyone everything everywhere except excepté fairly fais faisaient faisant fait faites far favorite favourite façon fera ferai feraient ferais ferait feras ferez feriez ferions ferons feront few fewer fi fiber fibre fifth first five flac floc fluency focus focused followed following follows font for force former formerly forth four from furent further furthermore fus fut g gave gens get gets getting give given gives go goes going gone good got gray great grey ha had hadn half hardly has hasn have haven having he hed hein hell hello help hem hence hep her here hereafter hereby herein heres hereupon hers herself hes hi him himself his hither ho holà honor honour hop hopefully hormis hors hou houp how howbeit however hue hui huit hum hundred hurrah i ici id ie if il ill ils im immediate importe in inasmuch inc indeed indicate indicated indicates inner inside instead into inward is isn it itd itll its itself ive j je jusqu jusque just juste k keep keeps kept kind knew know known knows l la laisser laquelle las last lately later latter latterly le learned learning learnt least lequel les lesquelles lesquels less lesson lessons lest let lets leur leurs licence license like liked likely little longtemps look looking looks lors lorsque ltd lui lui-même m ma made mainly maint mais make makes malgre malgré many may maybe mayn me mean meantime meanwhile meme memory mes mien mienne miennes miens might mightn mille mince mine minus miss modeling modelling moi moi-même moins mon more moreover most mostly moyennant mr mrs much must mustn my myself même n na name namely nd ne neanmoins near nearly necessary need needn neither neuf never nevertheless new next ni nine ninety no nobody non none nonetheless noone nor normally nos not nothing notre notwithstanding nous nous-mêmes novel now nowhere nul néanmoins o obviously of off often oh ohé ok okay old ollé olé on once one ones only ont onto onze opposite or ore organise organize other others otherwise ou ouf ought oui ouias our ours ourselves out outre outside over overall own où p paf pan par paragraph paragraphs parce parfois parle parlent parler parmi partant particular particularly pas passé past pendant per perhaps personne peu peut peuvent peux pff pfft pfut pif placed please plein plouf plus plusieurs plutot plutôt possible pouah pour pourquoi practice practise premier premiere première presumably probably proche program programme provided provides près psitt puis puisque put puts q qu quand quant quanta quarante quasi quatorze quatre quatre-vingt que quel quelle quelles quelqu quelqu'un quelqu'une quelque quelques quelquun quels qui quiconque quinze quite quoi quoique r rather reader readers reading realise realize really recent recently recognise recognize regarding regardless relatively respectively revoici revoilà rien right round s sa sacrebleu said same sans sapristi sauf saw say saying says school se second secondly see seeing seem seemed seeming seems seen sein seize self selon selves sensible sent sentence sentences sept sera serai seraient serais serait seras serez seriez serions serious seriously serons seront ses seven several shall shan she shed shell shes should shouldn si sien sienne siennes siens simple simpler since sinon six so soi soi-même soit soixante some somebody someday somehow someone something sometime sometimes somewhat somewhere sommes son sont soon sorry sous specified specify specifying speed still stop student students sub such suis suivant summarise summarize sup sur sure surtout t ta tac take taken taking tant te teacher teachers tel tell telle tellement telles tels tenant tends tes text texts than thank thanks thanx that thatll thats thatve the theater theatre their theirs them themselves then thence there thereafter thereby thered therefore therein therell theres thereupon thereve these they theyd theyll theyre theyve thing things think third thirty this thorough thoroughly those though three through throughout thru thus tic tien tienne tiennes tiens till to toc together toi toi-même ton too took top touchant toujours tous tout toute toutes toward towards traveled traveling travelled travelling treize trente tres tried tries trois trop truly try trying très tu twelve twenty twice two u un under underneath understand understanding undoing une unfortunately unless unlike unlikely until unto up upon upward upwards us use used useful uses using usually va vais value various vas vers very via vif vifs vingt vive vives viz vlan voici voilà vont vos votre vous vous-mêmes vs vu w want wants was wasn way we wed well went were weren weve what whatever whatll whats when whence whenever where whereafter whereas whereby wherein wheres whereupon wherever whether which while whilst whither who whod whoever whole wholl whom whomever whos whose why will willing with within without won wonder word words would wouldn x y yes yet you youd youll your youre yours yourself yourselves youve z zut étaient étais était étant été être ô
`;

const COMMON_WORDS = new Set(COMMON_WORDS_INLINE.trim().split(/\s+/).map(normalizeToken));

const WORD_RE = /[A-Za-zÀ-ÖØ-öø-ÿ'’\-]+/gu;
const WORD_FULL_RE = /^[A-Za-zÀ-ÖØ-öø-ÿ'’\-]+$/u;
const TOKEN_RE = /[A-Za-zÀ-ÖØ-öø-ÿ'’\-]+|\s+|[^\s]/gu;
const VOWELS = 'aeiouyàâäæéèêëîïôœùûüÿ';

function normalizeToken(token) {
  return String(token).toLowerCase().replace(/[’]/g, "'").replace(/^['’-]+|['’-]+$/g, '');
}

function tokenizeWords(text) {
  return String(text).match(WORD_RE) || [];
}

function detectLanguage(text) {
  const words = tokenizeWords(text).map(normalizeToken);
  if (words.length === 0) return 'fr';

  const frMarkers = new Set(['le', 'la', 'les', 'des', 'que', 'qui', 'dans', 'pour', 'avec', 'une', 'est', 'pas', 'vous', 'nous', 'sur']);
  const enMarkers = new Set(['the', 'and', 'that', 'with', 'for', 'you', 'your', 'this', 'from', 'have', 'are', 'was', 'were', 'they', 'their']);

  let frCount = 0;
  let enCount = 0;
  for (const word of words) {
    if (frMarkers.has(word)) frCount += 1;
    if (enMarkers.has(word)) enCount += 1;
  }

  return enCount > frCount ? 'en' : 'fr';
}

function countSyllables(word) {
  const cleaned = String(word).toLowerCase().replace(/[^a-zàâäæéèêëîïôœùûüÿ]/g, '');
  if (!cleaned) return 1;
  const groups = cleaned.match(/[aeiouyàâäæéèêëîïôœùûüÿ]+/g) || [];
  return Math.max(1, groups.length);
}

function fleschReadingEase(text, language) {
  const sentences = String(text).split(/[.!?]+/).map((sentence) => sentence.trim()).filter(Boolean);
  const words = tokenizeWords(text);

  const wordCount = Math.max(1, words.length);
  const sentenceCount = Math.max(1, sentences.length);
  const syllableCount = words.reduce((total, word) => total + countSyllables(word), 0);

  const asl = wordCount / sentenceCount;
  const asw = syllableCount / wordCount;
  const lang = language || detectLanguage(text);
  const rawScore = lang === 'fr'
    ? 207.0 - 1.015 * asl - 73.6 * asw
    : 206.835 - 1.015 * asl - 84.6 * asw;

  return {
    score: Number(rawScore.toFixed(2)),
    asl,
    asw,
  };
}

function zipfCommonRatio(text) {
  const words = tokenizeWords(text).map(normalizeToken);
  if (words.length === 0) {
    return {
      ratio: 1,
      commonWordsCount: 0,
      totalWords: 0,
    };
  }

  let commonWordsCount = 0;
  for (const word of words) {
    if (COMMON_WORDS.has(word)) commonWordsCount += 1;
  }

  return {
    ratio: commonWordsCount / words.length,
    commonWordsCount,
    totalWords: words.length,
  };
}

function isVowel(character) {
  return VOWELS.includes(String(character).toLowerCase());
}

function splitWordSyllables(word) {
  const letters = [...String(word)];
  if (letters.length <= 3) return [String(word)];

  const chunks = [];
  let current = letters[0];

  for (let index = 1; index < letters.length; index += 1) {
    const previous = letters[index - 1];
    const currentLetter = letters[index];
    const next = index + 1 < letters.length ? letters[index + 1] : '';

    let boundary = false;
    if (isVowel(previous) && !isVowel(currentLetter)) {
      if (next && isVowel(next)) boundary = true;
    } else if (!isVowel(previous) && isVowel(currentLetter)) {
      if (current.length >= 2) boundary = true;
    }

    if (boundary) {
      chunks.push(current);
      current = currentLetter;
    } else {
      current += currentLetter;
    }
  }

  chunks.push(current);
  return chunks.filter(Boolean);
}

function normalizeSeed(seed) {
  if (Number.isFinite(seed)) return Number(seed) >>> 0;
  const value = seed == null ? '42' : String(seed);
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

function mulberry32(seed) {
  let state = normalizeSeed(seed);
  return function random() {
    state += 0x6d2b79f5;
    let value = Math.imul(state ^ (state >>> 15), 1 | state);
    value ^= value + Math.imul(value ^ (value >>> 7), 61 | value);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

function gaussianRandom(rng, mean = 0, sigma = 1) {
  let u = 0;
  let v = 0;
  while (u === 0) u = rng();
  while (v === 0) v = rng();
  const standardNormal = Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
  return mean + sigma * standardNormal;
}

function brownianBlockSizes(totalSyllables, seed, bMin = 4, bMax = 11, b0 = 7, sigma = 1.3) {
  if (totalSyllables <= 0) return [];

  const rng = mulberry32(seed);
  const clamp = (value) => Math.max(bMin, Math.min(bMax, value));
  const sizes = [];
  let current = clamp(b0);
  let consumed = 0;

  while (consumed < totalSyllables) {
    const remaining = totalSyllables - consumed;
    if (remaining <= bMax) {
      sizes.push(Math.max(1, remaining));
      break;
    }

    const size = Math.min(current, remaining);
    sizes.push(size);
    consumed += size;

    const epsilon = Math.round(gaussianRandom(rng, 0, sigma));
    current = clamp(current + epsilon);
  }

  return sizes;
}

function gaussianWeight(u, sigmaLeft = 2.4, sigmaRight = 3.7) {
  const sigma = u >= 0 ? sigmaRight : sigmaLeft;
  return Math.exp(-(u * u) / (2 * sigma * sigma));
}

function escapeHtml(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function syllableEntries(text) {
  const rawTokens = String(text).match(TOKEN_RE) || [];
  const syllables = [];
  const syllableCountPerToken = new Array(rawTokens.length).fill(0);

  rawTokens.forEach((token, tokenIndex) => {
    if (!WORD_FULL_RE.test(token)) return;

    const parts = splitWordSyllables(token);
    const useParts = parts.length ? parts : [token];
    syllableCountPerToken[tokenIndex] = useParts.length;

    for (const part of useParts) {
      syllables.push({
        tokenIndex,
        text: part,
      });
    }
  });

  return {
    syllables,
    rawTokens,
    syllableCountPerToken,
  };
}

function computeBlockMap(blockSizes) {
  const blockMap = [];
  blockSizes.forEach((size, blockId) => {
    for (let index = 0; index < size; index += 1) {
      blockMap.push(blockId);
    }
  });
  return blockMap;
}

function formatTextBrownian(text, seed, params = {}) {
  const {
    bMin = 4,
    bMax = 11,
    b0 = 7,
    sigmaBlock = 1.3,
    sigmaLeft = 2.4,
    sigmaRight = 3.7,
  } = params;

  if (!String(text).trim()) {
    return {
      markdownText: '',
      htmlText: '',
    };
  }

  const {
    syllables,
    rawTokens,
    syllableCountPerToken,
  } = syllableEntries(text);

  if (syllables.length === 0) {
    return {
      markdownText: String(text),
      htmlText: `<p>${escapeHtml(text)}</p>`,
    };
  }

  const blockSizes = brownianBlockSizes(syllables.length, seed, bMin, bMax, b0, sigmaBlock);
  const blockMap = computeBlockMap(blockSizes);
  while (blockMap.length < syllables.length) {
    blockMap.push(blockSizes.length - 1);
  }

  const blockStarts = [];
  let accumulator = 0;
  for (const size of blockSizes) {
    blockStarts.push(accumulator);
    accumulator += size;
  }

  const styledMarkdown = [];
  const styledHtml = [];
  const blockMean = (bMin + bMax) / 2;

  for (let syllableIndex = 0; syllableIndex < syllables.length; syllableIndex += 1) {
    const blockId = blockMap[syllableIndex];
    const blockSize = blockSizes[blockId];
    const blockStart = blockStarts[blockId];
    const localPosition = syllableIndex - blockStart;
    const u = blockSize <= 1 ? 0 : (2 * localPosition / (blockSize - 1)) - 1;
    const weight = gaussianWeight(u, sigmaLeft, sigmaRight);

    const tauI = Math.min(0.98, 0.14 * blockSize);
    const cadence = blockSize >= blockMean ? 3 : 2;
    const cadenceHit = localPosition % cadence === 0;
    const centerWindow = Math.abs(u) <= (cadence === 3 ? 0.42 : 0.52);
    const makeBold = (weight > tauI) || (cadenceHit && centerWindow && weight > tauI * 0.92);
    const syllableText = syllables[syllableIndex].text;

    if (makeBold) {
      styledMarkdown.push(syllableText);
      styledHtml.push(`<strong>${escapeHtml(syllableText)}</strong>`);
    } else {
      styledMarkdown.push(syllableText);
      styledHtml.push(escapeHtml(syllableText));
    }
  }

  const tokenToMarkdown = new Map();
  const tokenToHtml = new Map();

  syllables.forEach((syllable, index) => {
    if (!tokenToMarkdown.has(syllable.tokenIndex)) {
      tokenToMarkdown.set(syllable.tokenIndex, []);
      tokenToHtml.set(syllable.tokenIndex, []);
    }

    tokenToMarkdown.get(syllable.tokenIndex).push(styledMarkdown[index]);
    tokenToHtml.get(syllable.tokenIndex).push(styledHtml[index]);
  });

  const markdownParts = [];
  const htmlParts = [];

  rawTokens.forEach((token, tokenIndex) => {
    if (syllableCountPerToken[tokenIndex] > 0) {
      markdownParts.push(tokenToMarkdown.get(tokenIndex).join(''));
      htmlParts.push(tokenToHtml.get(tokenIndex).join(''));
    } else {
      markdownParts.push(token);
      htmlParts.push(escapeHtml(token));
    }
  });

  return {
    markdownText: markdownParts.join(''),
    htmlText: `<p>${htmlParts.join('').replaceAll('\n', '<br>')}</p>`,
  };
}

function analyzeText(text) {
  const language = detectLanguage(text);
  const readability = fleschReadingEase(text, language);
  const zipf = zipfCommonRatio(text);

  return {
    language,
    fleschScore: readability.score,
    asl: readability.asl,
    asw: readability.asw,
    zipfCommonRatio: zipf.ratio,
    totalWords: zipf.totalWords,
    commonWordsCount: zipf.commonWordsCount,
  };
}

/**
 * Reformate un texte avec l'algorithme brownien RUMBA.RD.
 *
 * Le texte original est conservé. Le moteur détecte la langue, calcule une
 * lisibilité Flesch adaptée FR/EN, ajuste la taille de bloc initiale, puis
 * applique un balisage HTML en gras sur certaines syllabes. Le seed est
 * reproductible : même texte + même seed produit exactement le même résultat.
 *
 * @param {string} inputText - Texte brut à reformater.
 * @param {number|string} [seed=42] - Graine pseudo-aléatoire reproductible.
 * @returns {{
 *   plainText: string,
 *   markdownText: string,
 *   htmlText: string,
 *   analysis: {
 *     language: 'fr'|'en',
 *     fleschScore: number,
 *     asl: number,
 *     asw: number,
 *     zipfCommonRatio: number,
 *     totalWords: number,
 *     commonWordsCount: number
 *   }
 * }}
 */
export const gaussReformulator = (inputText, seed = 42) => {
  const plainText = String(inputText ?? '');
  const analysis = analyzeText(plainText);

  let b0 = 7;
  if (analysis.fleschScore < 74) {
    b0 = 6;
  } else if (analysis.fleschScore > 82) {
    b0 = 8;
  }

  const { markdownText, htmlText } = formatTextBrownian(plainText, seed, {
    bMin: 4,
    bMax: 11,
    b0,
    sigmaBlock: 1.3,
    sigmaLeft: 2.4,
    sigmaRight: 3.7,
  });

  return {
    plainText,
    markdownText,
    htmlText,
    analysis,
  };
};
