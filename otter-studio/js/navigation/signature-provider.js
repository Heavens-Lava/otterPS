// otter-studio/js/navigation/signature-provider.js
// Backwards-compatible facade over the unified OtterLanguageService and metadata

import { getBuiltinSignatures } from '../language/otter-metadata.js';
import { otterLanguageService } from '../language/otter-language-service.js';

export const SIGNATURE_TABLE = getBuiltinSignatures().map(entry => ({
  name: entry.name,
  prefix: entry.prefix,
  label: entry.syntax,
  parameters: entry.parameters,
  doc: entry.doc,
  splitParam: entry.splitParam,
  customActive: entry.customActive
}));

export function getSignatureHelp(lineUntilCursor, symbols = []) {
  return otterLanguageService.getSignatureHelp(lineUntilCursor, symbols);
}
