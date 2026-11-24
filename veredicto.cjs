'use strict';
// Veredicto de una pasada calculado en GitHub (CI-V1), para que el PC no baje ni descifre las pasadas enteras.
//  node veredicto.cjs m <carpeta de resultados> <salida>   en cada máquina, tras las pruebas: guarda tanda.txt, resumen.json
//      y e2e.log, comprimidos y cifrados con veredicto.pub. La máquina no lleva ninguna clave.
//  node veredicto.cjs j <carpeta>   en el último trabajo, con la clave CLAVE: abre el paquete (sueltos.txt de la rama probada),
//      el resumen base (base-pc.enc) y lo de cada máquina (<carpeta>/s/s<i>/s.enc), pasa puerta.py, la misma del PC,
//      y deja <carpeta>/veredicto.enc cifrado con resultados.pub: solo el PC puede leerlo (node lanzar.cjs --veredicto).
//      Deja además <carpeta>/veredicto-claro.txt sin cifrar (CI-D2), para leerlo sin llaves desde la nube: solo los nombres
//      de las pruebas con fallo nuevo, una por línea, y al final SÍ o NO. Sin mensajes de error, rutas ni código: el repositorio
//      de las pasadas es público.
// La llave privada de veredicto.pub no se guarda en ningún sitio: sale de la clave CLAVE, que ya es un secreto del repositorio.
const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const sellar = (clave, datos) => {
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', clave, iv);
  const cuerpo = Buffer.concat([c.update(datos), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), cuerpo]);
};
const abrir = (clave, datos) => {
  const d = crypto.createDecipheriv('aes-256-gcm', clave, datos.subarray(0, 12));
  d.setAuthTag(datos.subarray(12, 28));
  return Buffer.concat([d.update(datos.subarray(28)), d.final()]);
};
const derivar = (secreto, info) => Buffer.from(crypto.hkdfSync('sha256', secreto, Buffer.alloc(0), info, 32));
// X25519 con la llave privada derivada de la clave: 32 bytes de HKDF dentro de una envoltura PKCS8 fija.
const privada = (clave) => crypto.createPrivateKey({
  key: Buffer.concat([Buffer.from('302e020100300506032b656e04220420', 'hex'), derivar(clave, 'duendi-veredicto')]), format: 'der', type: 'pkcs8' });
const publica = (clave) => crypto.createPublicKey(privada(clave)).export({ type: 'spki', format: 'pem' });

function cifrarX(datos, pub) {
  const efimera = crypto.generateKeyPairSync('x25519');
  const comun = crypto.diffieHellman({ privateKey: efimera.privateKey, publicKey: pub });
  const spki = efimera.publicKey.export({ type: 'spki', format: 'der' });
  return Buffer.concat([Buffer.from('DVX1'), spki, sellar(derivar(comun, 'duendi-s'), datos)]);
}
function descifrarX(datos, priv) {
  if (datos.subarray(0, 4).toString() !== 'DVX1') throw Error('formato');
  const pub = crypto.createPublicKey({ key: datos.subarray(4, 48), format: 'der', type: 'spki' });
  return abrir(derivar(crypto.diffieHellman({ privateKey: priv, publicKey: pub }), 'duendi-s'), datos.subarray(48));
}
// Igual que cifra.cjs p: solo la llave privada del PC lo abre.
function cifrarPC(datos) {
  const clave = crypto.randomBytes(32);
  const envuelta = crypto.publicEncrypt({ key: fs.readFileSync(path.join(__dirname, 'resultados.pub'), 'utf8'),
    padding: crypto.constants.RSA_PKCS1_OAEP_PADDING, oaepHash: 'sha256' }, clave);
  const largo = Buffer.alloc(2);
  largo.writeUInt16BE(envuelta.length);
  return Buffer.concat([Buffer.from('DPK1'), largo, envuelta, sellar(clave, datos)]);
}

function maquina(o, salida) {
  const leer = (f) => { try { return fs.readFileSync(path.join(o, f), 'utf8'); } catch { return null; } };
  const datos = zlib.gzipSync(JSON.stringify({ tanda: leer('tanda.txt'), resumen: leer('resumen.json'), e2e: leer('e2e.log') }));
  fs.writeFileSync(salida, cifrarX(datos, crypto.createPublicKey(fs.readFileSync(path.join(__dirname, 'veredicto.pub'), 'utf8'))));
}

// De la salida de puerta.py solo pasan los nombres de las pruebas ("archivo > nombre" o "app/archivo:línea") y SÍ o NO.
// Un nombre de prueba nunca lleva saltos de línea ni caracteres de control; se corta a 160 como hace puerta.py.
function claro(salida) {
  const lineas = String(salida || '').replace(/\r/g, '').trim().split('\n');
  const si = lineas[lineas.length - 1] === 'SÍ';
  const nombres = new Set();
  for (const l of lineas) {
    const m = /^[^:]*: fallo nuevo: (.+)$/.exec(l);
    if (m) nombres.add(m[1].replace(/[\x00-\x1f\x7f]/g, '').slice(0, 160));
  }
  return [...(si ? [] : nombres), si ? 'SÍ' : 'NO'].join('\n') + '\n';
}

function juntar(w) {
  const run = process.env.GITHUB_RUN_ID;
  const clave = Buffer.from(String(process.env.CLAVE || '').trim(), 'hex');
  let texto, enClaro = 'NO\n';
  try {
    if (clave.length !== 32 || !/^\d+$/.test(run || '')) throw Error('falta la clave o el número de pasada');
    const tar = (...a) => execFileSync('tar', a, { cwd: w, stdio: 'ignore' });
    fs.writeFileSync(path.join(w, 'p.tar'), abrir(clave, fs.readFileSync(path.join(w, 'p', 'p.enc'))));
    tar('-xf', 'p.tar', 'src.tgz', 'ci/rama.txt');
    fs.rmSync(path.join(w, 'p.tar'));
    let sueltos = path.join(w, 'pc', 'fabrica', 'sueltos.txt'), nota = '';
    try { tar('-xzf', 'src.tgz', 'pc/fabrica/sueltos.txt'); } catch {
      sueltos = path.join(w, 'vacio.txt'); fs.writeFileSync(sueltos, ''); nota = 'La rama no trae pc/fabrica/sueltos.txt: sin fallos conocidos aparte de la base.\n';
    }
    fs.rmSync(path.join(w, 'src.tgz'));
    fs.writeFileSync(path.join(w, 'base.json'), abrir(clave, fs.readFileSync(path.join(__dirname, 'base-pc.enc'))));
    const priv = privada(clave), ci = path.join(w, 'ci-pc'), dir = path.join(ci, `run${run}`);
    fs.mkdirSync(dir, { recursive: true });
    const s = path.join(w, 's');
    let n = 0;
    for (const d of fs.existsSync(s) ? fs.readdirSync(s) : []) {
      const m = /^s(\d+)$/.exec(d);
      if (!m) continue;
      const j = JSON.parse(zlib.gunzipSync(descifrarX(fs.readFileSync(path.join(s, d, 's.enc')), priv)).toString('utf8'));
      const t = path.join(dir, `t${m[1]}`);
      fs.mkdirSync(t);
      for (const [k, f] of [['tanda', 'tanda.txt'], ['resumen', 'resumen.json'], ['e2e', 'e2e.log']]) if (typeof j[k] === 'string') fs.writeFileSync(path.join(t, f), j[k]);
      n++;
    }
    let salida;
    try {
      salida = execFileSync('python3', [path.join(__dirname, 'puerta.py'), run, path.join(w, 'base.json')], {
        encoding: 'utf8', env: { PATH: process.env.PATH, PYTHONUTF8: '1', DUENDI_CI: ci, DUENDI_SUELTOS: sueltos } });
    } catch (e) { salida = e.stdout || ''; if (!/^(SÍ|NO)/m.test(salida)) throw Error(`puerta.py: ${String(e.stderr || e.message).slice(-300)}`); }
    const rama = fs.readFileSync(path.join(w, 'ci', 'rama.txt'), 'utf8').trim();
    texto = `Pasada ${run}. Rama probada: ${rama}. ${n} máquinas con resumen.\n${nota}${salida.trim()}\n`;
    enClaro = claro(salida);
  } catch (e) {
    texto = `NO (no se pudo calcular el veredicto en la nube: ${e.message})\n`;
  }
  fs.writeFileSync(path.join(w, 'veredicto.enc'), cifrarPC(Buffer.from(texto)));
  fs.writeFileSync(path.join(w, 'veredicto-claro.txt'), enClaro);
}

if (require.main === module) {
  const [modo, a, b] = process.argv.slice(2);
  if (modo === 'm') maquina(a, b);
  else if (modo === 'j') juntar(a);
  else { console.error('uso: node veredicto.cjs m <carpeta> <salida> | j <carpeta>'); process.exitCode = 2; }
}
module.exports = { publica, claro };
