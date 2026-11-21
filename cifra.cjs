'use strict';
// node cifra.cjs c|d entrada salida  (clave hex de 32 bytes en la variable CLAVE)
// node cifra.cjs p entrada salida    (sin clave: cifra con la llave pública resultados.pub; solo el PC puede abrirlo)
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const [modo, entrada, salida] = process.argv.slice(2);
const datos = fs.readFileSync(entrada);
const sellar = (clave, iv) => {
  const c = crypto.createCipheriv('aes-256-gcm', clave, iv);
  const cuerpo = Buffer.concat([c.update(datos), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), cuerpo]);
};
if (modo === 'p') {
  const clave = crypto.randomBytes(32);
  const publica = fs.readFileSync(path.join(__dirname, 'resultados.pub'), 'utf8');
  const envuelta = crypto.publicEncrypt({ key: publica, padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, clave);
  const largo = Buffer.alloc(2);
  largo.writeUInt16BE(envuelta.length);
  fs.writeFileSync(salida, Buffer.concat([Buffer.from('DPK1'), largo, envuelta, sellar(clave, crypto.randomBytes(12))]));
  process.exit(0);
}
const clave = Buffer.from(String(process.env.CLAVE || '').trim(), 'hex');
if (clave.length !== 32 || !['c', 'd'].includes(modo)) { console.error('uso incorrecto'); process.exit(2); }
if (modo === 'c') {
  fs.writeFileSync(salida, sellar(clave, crypto.randomBytes(12)));
} else {
  const d = crypto.createDecipheriv('aes-256-gcm', clave, datos.subarray(0, 12));
  d.setAuthTag(datos.subarray(12, 28));
  fs.writeFileSync(salida, Buffer.concat([d.update(datos.subarray(28)), d.final()]));
}
