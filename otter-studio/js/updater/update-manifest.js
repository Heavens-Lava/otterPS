/**
 * Otter Studio Release & Update Manifest Specification
 * Defines the schema, SemVer comparison, and cryptographic verification for Stable and Preview feeds.
 */

import crypto from 'node:crypto';

export class UpdateManifestValidator {
  /**
   * Validates the schema of an update feed manifest
   * @param {any} manifest
   * @returns {{ valid: boolean, errors: string[] }}
   */
  static validate(manifest) {
    const errors = [];
    if (!manifest || typeof manifest !== 'object') {
      return { valid: false, errors: ['Manifest must be a non-null object.'] };
    }

    if (!['stable', 'preview'].includes(manifest.channel)) {
      errors.push('Manifest channel must be "stable" or "preview".');
    }

    if (!manifest.version || typeof manifest.version !== 'string') {
      errors.push('Manifest must contain a valid SemVer version string.');
    }

    if (!manifest.releaseDate || isNaN(Date.parse(manifest.releaseDate))) {
      errors.push('Manifest must contain a valid ISO releaseDate.');
    }

    if (!manifest.artifactUrl || typeof manifest.artifactUrl !== 'string') {
      errors.push('Manifest must contain an artifactUrl string.');
    }

    if (!manifest.sha256 || typeof manifest.sha256 !== 'string' || manifest.sha256.length !== 64) {
      errors.push('Manifest must contain a 64-character SHA-256 checksum string.');
    }

    return {
      valid: errors.length === 0,
      errors
    };
  }

  /**
   * Compares two SemVer versions (v1 > v2 => 1, v1 < v2 => -1, v1 == v2 => 0)
   */
  static compareVersions(v1, v2) {
    const parse = (v) => {
      const cleaned = (v || '').replace(/^[vV]/, '').split('-')[0];
      return cleaned.split('.').map(num => parseInt(num, 10) || 0);
    };

    const p1 = parse(v1);
    const p2 = parse(v2);

    for (let i = 0; i < Math.max(p1.length, p2.length); i++) {
      const num1 = p1[i] || 0;
      const num2 = p2[i] || 0;
      if (num1 > num2) return 1;
      if (num1 < num2) return -1;
    }
    return 0;
  }

  /**
   * Verifies SHA-256 hash of an artifact buffer against manifest checksum
   */
  static verifyChecksum(buffer, expectedSha256) {
    if (!buffer || !expectedSha256) return false;
    const hash = crypto.createHash('sha256').update(buffer).digest('hex').toLowerCase();
    return hash === expectedSha256.toLowerCase();
  }

  /**
   * Verifies RSA/Ed25519 signature of artifact against publisher public key
   */
  static verifySignature(buffer, signatureHex, publicKeyPem) {
    if (!buffer || !signatureHex || !publicKeyPem) return false;
    try {
      const verifier = crypto.createVerify('SHA256');
      verifier.update(buffer);
      return verifier.verify(publicKeyPem, Buffer.from(signatureHex, 'hex'));
    } catch {
      return false;
    }
  }
}
