// Writes the app's copy of the privacy notice and terms of use from the one
// source in src/legal.ts, so the two can never say different things.
//   node scripts/legal-dart.ts            (writes the file)
// test/legal-sync.test.ts fails if the app's file is out of date.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { documents } from '../src/legal.ts';

export const DART_FILE = fileURLToPath(
  new URL('../../app/lib/ui/features/account/legal_text.dart', import.meta.url),
);

const str = (s: string) => `'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('$', '\\$')}'`;

function sections(list: { title: string; body: string[] }[]): string {
  return list
    .map(
      (s) =>
        `    LegalSection(\n      ${str(s.title)},\n      [\n${s.body.map((p) => `        ${str(p)},`).join('\n')}\n      ],\n    ),`,
    )
    .join('\n');
}

export function dartSource(): string {
  const doc = (name: 'privacy' | 'terms', dartName: string) => {
    const d = documents[name];
    return `const ${dartName} = LegalDocument(
  version: ${str(d.version)},
  titleAr: ${str(d.title.ar)},
  titleEn: ${str(d.title.en)},
  ar: [
${sections(d.ar)}
  ],
  en: [
${sections(d.en)}
  ],
);`;
  };
  return `// GENERATED from server/src/legal.ts by server/scripts/legal-dart.ts.
// Do not edit by hand: change the server file and run the script.

class LegalSection {
  const LegalSection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

class LegalDocument {
  const LegalDocument({
    required this.version,
    required this.titleAr,
    required this.titleEn,
    required this.ar,
    required this.en,
  });

  final String version;
  final String titleAr;
  final String titleEn;
  final List<LegalSection> ar;
  final List<LegalSection> en;

  String title(String language) => language == 'ar' ? titleAr : titleEn;
  List<LegalSection> sections(String language) => language == 'ar' ? ar : en;
}

${doc('privacy', 'privacyNotice')}

${doc('terms', 'termsOfUse')}
`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  writeFileSync(DART_FILE, dartSource());
  console.log(`wrote ${DART_FILE}`);
}
