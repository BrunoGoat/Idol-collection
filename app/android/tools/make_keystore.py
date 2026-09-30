"""Genera la clave de firma del APK a partir de una frase secreta.

La misma frase produce siempre exactamente la misma clave y el mismo
certificado, así cada APK que compila GitHub Actions se instala encima del
anterior sin guardar ningún archivo de clave en el repo. La frase vive solo en
el secret ANDROID_SIGNING_SEED.

Uso: SIGNING_SEED="..." python3 make_keystore.py <salida.p12> <key.properties>
"""

import datetime
import hashlib
import math
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID
from sympy import nextprime

E = 65537


def stream(seed: bytes, label: bytes, nbytes: int) -> int:
    """Bytes pseudoaleatorios deterministas (SHA-512 en modo contador)."""
    out = b""
    counter = 0
    while len(out) < nbytes:
        out += hashlib.sha512(b"idolos-apk|" + label + b"|" + counter.to_bytes(4, "big") + b"|" + seed).digest()
        counter += 1
    return int.from_bytes(out[:nbytes], "big")


def prime(seed: bytes, label: bytes, bits: int) -> int:
    candidate = stream(seed, label, bits // 8)
    candidate |= (1 << (bits - 1)) | (1 << (bits - 2))  # tamaño exacto del módulo
    p = nextprime(candidate)
    while math.gcd(p - 1, E) != 1:
        p = nextprime(p)
    return p


def build(seed: bytes):
    p = prime(seed, b"p", 1536)
    q = prime(seed, b"q", 1536)
    n = p * q
    d = pow(E, -1, (p - 1) * (q - 1))
    key = rsa.RSAPrivateNumbers(
        p=p, q=q, d=d,
        dmp1=d % (p - 1), dmq1=d % (q - 1), iqmp=pow(q, -1, p),
        public_numbers=rsa.RSAPublicNumbers(E, n),
    ).private_key()
    name = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "Salon de Idolos"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "BrunoGoat"),
    ])
    # Todo fijo (fechas, serie) y firma RSA PKCS#1 v1.5, que es determinista:
    # el certificado sale idéntico byte a byte en cada compilación.
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(stream(seed, b"serial", 16) >> 1)
        .not_valid_before(datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
        .not_valid_after(datetime.datetime(2125, 12, 31, tzinfo=datetime.timezone.utc))
        .sign(key, hashes.SHA256())
    )
    return key, cert


def main():
    seed = os.environ.get("SIGNING_SEED", "").encode()
    if len(seed) < 16:
        sys.exit("SIGNING_SEED tiene que tener al menos 16 caracteres.")
    out_keystore, out_props = sys.argv[1], sys.argv[2]
    key, cert = build(seed)
    password = hashlib.sha256(b"idolos-store|" + seed).hexdigest()[:32]
    with open(out_keystore, "wb") as f:
        f.write(pkcs12.serialize_key_and_certificates(
            b"idol", key, cert, None, serialization.BestAvailableEncryption(password.encode())))
    with open(out_props, "w") as f:
        f.write(f"storeFile={os.path.basename(out_keystore)}\nstoreType=pkcs12\n"
                f"storePassword={password}\nkeyAlias=idol\nkeyPassword={password}\n")
    fingerprint = hashlib.sha256(cert.public_bytes(serialization.Encoding.DER)).hexdigest()
    print(f"Huella SHA-256 del certificado: {fingerprint}")


if __name__ == "__main__":
    main()
