#!/usr/bin/env python3
"""Generate independent, deterministic WireGuard vectors.

Test-only tooling: Python 3 standard library + OpenSSL 3 libcrypto, already
installed on the development host. No Python packages are required. Run with:

    python3 generate.py /path/to/libcrypto.3.dylib > handshake.json

Transcript specification: https://www.wireguard.com/protocol/
OpenSSL supplies X25519 and ChaCha20-Poly1305; hashlib supplies BLAKE2s.
These vectors establish agreement with an independent implementation of the
specification, not interoperability with a running WireGuard server.

Copyright 2026 DuckDuckGo. Licensed under the Apache License, Version 2.0.
"""

import ctypes
import hashlib
import hmac
import json
import struct
import sys


class OpenSSL:
    """Small binding to OpenSSL's public EVP API; no custom crypto primitives."""

    def __init__(self, library_path):
        library = ctypes.CDLL(library_path)
        pointer = ctypes.c_void_p
        integer = ctypes.c_int
        size = ctypes.c_size_t

        def bind(name, arguments, result=integer):
            function = getattr(library, name)
            function.argtypes = arguments
            function.restype = result
            return function

        self.new_private = bind("EVP_PKEY_new_raw_private_key_ex", [pointer, ctypes.c_char_p, ctypes.c_char_p, pointer, size], pointer)
        self.new_public = bind("EVP_PKEY_new_raw_public_key_ex", [pointer, ctypes.c_char_p, ctypes.c_char_p, pointer, size], pointer)
        self.get_public = bind("EVP_PKEY_get_raw_public_key", [pointer, pointer, ctypes.POINTER(size)])
        self.free_key = bind("EVP_PKEY_free", [pointer], None)
        self.new_key_context = bind("EVP_PKEY_CTX_new", [pointer, pointer], pointer)
        self.free_key_context = bind("EVP_PKEY_CTX_free", [pointer], None)
        self.derive_init = bind("EVP_PKEY_derive_init", [pointer])
        self.derive_peer = bind("EVP_PKEY_derive_set_peer", [pointer, pointer])
        self.derive = bind("EVP_PKEY_derive", [pointer, pointer, ctypes.POINTER(size)])
        self.chacha_poly = bind("EVP_chacha20_poly1305", [], pointer)
        self.new_cipher_context = bind("EVP_CIPHER_CTX_new", [], pointer)
        self.free_cipher_context = bind("EVP_CIPHER_CTX_free", [pointer], None)
        self.encrypt_init = bind("EVP_EncryptInit_ex", [pointer, pointer, pointer, pointer, pointer])
        self.encrypt_update = bind("EVP_EncryptUpdate", [pointer, pointer, ctypes.POINTER(integer), pointer, integer])
        self.encrypt_final = bind("EVP_EncryptFinal_ex", [pointer, pointer, ctypes.POINTER(integer)])
        self.cipher_control = bind("EVP_CIPHER_CTX_ctrl", [pointer, integer, integer, pointer])

    def public_key(self, private_key):
        key = self.new_private(None, b"X25519", None, private_key, len(private_key))
        if not key:
            raise RuntimeError("Cannot create X25519 private key")
        try:
            output = ctypes.create_string_buffer(32)
            length = ctypes.c_size_t(32)
            require(self.get_public(key, output, ctypes.byref(length)))
            return output.raw[:length.value]
        finally:
            self.free_key(key)

    def shared_secret(self, private_key, public_key):
        local = self.new_private(None, b"X25519", None, private_key, len(private_key))
        remote = self.new_public(None, b"X25519", None, public_key, len(public_key))
        if not local or not remote:
            raise RuntimeError("Cannot create X25519 keys")
        context = self.new_key_context(local, None)
        if not context:
            raise RuntimeError("Cannot create X25519 context")
        try:
            require(self.derive_init(context))
            require(self.derive_peer(context, remote))
            output = ctypes.create_string_buffer(32)
            length = ctypes.c_size_t(32)
            require(self.derive(context, output, ctypes.byref(length)))
            return output.raw[:length.value]
        finally:
            self.free_key_context(context)
            self.free_key(local)
            self.free_key(remote)

    def encrypt(self, key, counter, plaintext, associated_data=b""):
        nonce = bytes(4) + struct.pack("<Q", counter)
        return self.encrypt_nonce(key, nonce, plaintext, associated_data)

    def encrypt_nonce(self, key, nonce, plaintext, associated_data=b""):
        context = self.new_cipher_context()
        if not context:
            raise RuntimeError("Cannot create cipher context")
        try:
            require(self.encrypt_init(context, self.chacha_poly(), None, key, nonce))
            length = ctypes.c_int()
            if associated_data:
                require(self.encrypt_update(context, None, ctypes.byref(length), associated_data, len(associated_data)))
            output = ctypes.create_string_buffer(len(plaintext) + 16)
            require(self.encrypt_update(context, output, ctypes.byref(length), plaintext, len(plaintext)))
            ciphertext = output.raw[:length.value]
            tail = ctypes.create_string_buffer(16)
            require(self.encrypt_final(context, tail, ctypes.byref(length)))
            ciphertext += tail.raw[:length.value]
            tag = ctypes.create_string_buffer(16)
            # EVP_CTRL_AEAD_GET_TAG, the public OpenSSL EVP constant.
            require(self.cipher_control(context, 0x10, 16, tag))
            return ciphertext + tag.raw
        finally:
            self.free_cipher_context(context)


def require(result):
    if result != 1:
        raise RuntimeError("OpenSSL EVP operation failed")


def hash_data(data):
    return hashlib.blake2s(data).digest()


def mac(key, data):
    return hashlib.blake2s(data, key=key, digest_size=16).digest()


def kdf(key, data, count):
    temporary = hmac.digest(key, data, "blake2s")
    results = []
    previous = b""
    for index in range(1, count + 1):
        previous = hmac.digest(temporary, previous + bytes([index]), "blake2s")
        results.append(previous)
    return results


def hchacha20(key, nonce):
    """Test-only subkey derivation, checked against the XChaCha draft vector."""
    state = list(struct.unpack("<4I", b"expand 32-byte k"))
    state += list(struct.unpack("<8I", key)) + list(struct.unpack("<4I", nonce))

    def rotate(value, count):
        return ((value << count) | (value >> (32 - count))) & 0xffffffff

    def quarter(a, b, c, d):
        state[a] = (state[a] + state[b]) & 0xffffffff
        state[d] = rotate(state[d] ^ state[a], 16)
        state[c] = (state[c] + state[d]) & 0xffffffff
        state[b] = rotate(state[b] ^ state[c], 12)
        state[a] = (state[a] + state[b]) & 0xffffffff
        state[d] = rotate(state[d] ^ state[a], 8)
        state[c] = (state[c] + state[d]) & 0xffffffff
        state[b] = rotate(state[b] ^ state[c], 7)

    for _ in range(10):
        quarter(0, 4, 8, 12)
        quarter(1, 5, 9, 13)
        quarter(2, 6, 10, 14)
        quarter(3, 7, 11, 15)
        quarter(0, 5, 10, 15)
        quarter(1, 6, 11, 12)
        quarter(2, 7, 8, 13)
        quarter(3, 4, 9, 14)
    return struct.pack("<8I", *(state[0:4] + state[12:16]))


def fixture(crypto, preshared_key, rekey=False):
    local_private = bytes([0x11]) * 32
    remote_private = bytes([0x22]) * 32
    local_ephemeral = bytes([0x66 if rekey else 0x33]) * 32
    remote_ephemeral = bytes([0x77 if rekey else 0x44]) * 32
    local_public = crypto.public_key(local_private)
    remote_public = crypto.public_key(remote_private)
    local_ephemeral_public = crypto.public_key(local_ephemeral)
    remote_ephemeral_public = crypto.public_key(remote_ephemeral)
    local_index = 0x01020304 + int(rekey)
    remote_index = 0x05060708 + int(rekey)
    timestamp = bytes.fromhex("400000006000000000000002" if rekey else "400000006000000000000001")

    chaining_key = hash_data(b"Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s")
    transcript = hash_data(hash_data(chaining_key + b"WireGuard v1 zx2c4 Jason@zx2c4.com") + remote_public)
    transcript = hash_data(transcript + local_ephemeral_public)
    chaining_key, = kdf(chaining_key, local_ephemeral_public, 1)
    chaining_key, key = kdf(chaining_key, crypto.shared_secret(local_ephemeral, remote_public), 2)
    encrypted_static = crypto.encrypt(key, 0, local_public, transcript)
    transcript = hash_data(transcript + encrypted_static)
    chaining_key, key = kdf(chaining_key, crypto.shared_secret(local_private, remote_public), 2)
    encrypted_timestamp = crypto.encrypt(key, 0, timestamp, transcript)
    transcript = hash_data(transcript + encrypted_timestamp)
    initiation = struct.pack("<II", 1, local_index) + local_ephemeral_public + encrypted_static + encrypted_timestamp
    initiation += mac(hash_data(b"mac1----" + remote_public), initiation)
    initiation += bytes(16)

    transcript = hash_data(transcript + remote_ephemeral_public)
    chaining_key, = kdf(chaining_key, remote_ephemeral_public, 1)
    chaining_key, = kdf(chaining_key, crypto.shared_secret(remote_ephemeral, local_ephemeral_public), 1)
    chaining_key, = kdf(chaining_key, crypto.shared_secret(remote_ephemeral, local_public), 1)
    chaining_key, temporary, key = kdf(chaining_key, preshared_key, 3)
    transcript = hash_data(transcript + temporary)
    encrypted_empty = crypto.encrypt(key, 0, b"", transcript)
    response = struct.pack("<III", 2, remote_index, local_index) + remote_ephemeral_public + encrypted_empty
    response += mac(hash_data(b"mac1----" + local_public), response)
    response += bytes(16)
    sending_key, receiving_key = kdf(chaining_key, b"", 2)

    plaintext = bytes.fromhex("4500001400000000400100000a0000010a000002")
    padded = plaintext + bytes((-len(plaintext)) % 16)
    sent_transport = struct.pack("<IIQ", 4, remote_index, 0) + crypto.encrypt(sending_key, 0, padded)
    received_transport = struct.pack("<IIQ", 4, local_index, 0) + crypto.encrypt(receiving_key, 0, padded)
    received_transport_next = struct.pack("<IIQ", 4, local_index, 1) + crypto.encrypt(receiving_key, 1, padded)
    cookie_nonce = bytes([0x88]) * 24
    cookie = bytes([0x99]) * 16
    cookie_key = hash_data(b"cookie--" + remote_public)
    cookie_subkey = hchacha20(cookie_key, cookie_nonce[:16])
    encrypted_cookie = crypto.encrypt_nonce(cookie_subkey, bytes(4) + cookie_nonce[16:], cookie, initiation[116:132])
    cookie_reply = struct.pack("<II", 3, local_index) + cookie_nonce + encrypted_cookie
    cookie_retry = initiation[:132] + mac(cookie, initiation[:132])
    values = {
        "name": "no-psk" if preshared_key == bytes(32) else "with-psk",
        "initiator_private": local_private,
        "responder_private": remote_private,
        "initiator_public": local_public,
        "responder_public": remote_public,
        "initiator_ephemeral": local_ephemeral,
        "responder_ephemeral": remote_ephemeral,
        "initiator_index": local_index,
        "responder_index": remote_index,
        "timestamp": timestamp,
        "preshared_key": preshared_key,
        "initiation": initiation,
        "response": response,
        "sending_key": sending_key,
        "receiving_key": receiving_key,
        "plaintext": plaintext,
        "sent_transport": sent_transport,
        "received_transport": received_transport,
        "received_transport_next": received_transport_next,
        "cookie_reply": cookie_reply,
        "cookie_retry": cookie_retry,
    }
    return {name: value.hex() if isinstance(value, bytes) else value for name, value in values.items()}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 generate.py /path/to/libcrypto.3.dylib > handshake.json")
    # https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.2.1
    known_subkey = hchacha20(bytes(range(32)), bytes.fromhex("000000090000004a0000000031415927"))
    if known_subkey.hex() != "82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc":
        sys.exit("HChaCha20 draft vector failed")
    crypto = OpenSSL(sys.argv[1])
    fixtures = []
    for preshared_key in [bytes(32), bytes([0x55]) * 32]:
        initial = fixture(crypto, preshared_key)
        initial["rekey"] = fixture(crypto, preshared_key, rekey=True)
        fixtures.append(initial)
    print(json.dumps(fixtures, indent=2))
