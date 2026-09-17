// otter-studio/js/navigation/hover-provider.js
// Backwards-compatible facade over the unified OtterLanguageService and metadata

import { OTTER_LANGUAGE_METADATA } from '../language/otter-metadata.js';
import { otterLanguageService } from '../language/otter-language-service.js';

export const OTTER_DOCS = {};
for (const entry of OTTER_LANGUAGE_METADATA) {
  OTTER_DOCS[entry.name.toLowerCase()] = {
    signature: entry.syntax,
    description: entry.doc,
    example: entry.example || null
  };
}

export function getWordAtOffset(text, offset) {
  return otterLanguageService.getWordAtOffset(text, offset);
}

export function getHoverInfo(word, filePath, symbols = [], line = 1) {
  return otterLanguageService.getHoverInfo(word, filePath, symbols, line);
}
