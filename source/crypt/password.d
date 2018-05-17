module crypt.password;

import std.ascii;
import std.random;
import std.exception;

import deimos.openssl.evp;
import deimos.openssl.sha;
import deimos.openssl.crypto;

/// Generates a random human readable string of n characters (combination of a-zA-Z0-9)
string randomAlphaNumericCombination(size_t n)()
{
	const possibles = letters ~ digits;
	char[n] pass;
	for (size_t i = 0; i < n; i++)
		pass[i] = possibles[uniform(0, $)];
	return pass.idup;
}

alias randomPassword = randomAlphaNumericCombination!12;
alias generateToken = randomAlphaNumericCombination!20;

/// Generates a uniform salt with n bytes.
ubyte[n] generateSalt(int n = 64)()
{
	ubyte[n] salt;
	for (int i = 0; i < n; i++)
		salt[i] = uniform(ubyte.min, ubyte.max);
	return salt;
}

/// Uses openssl PKCS5_PBKDF2_HMAC for salted hashing.
ubyte[outputBytes] PBKDF2_HMAC_SHA_512_string(uint outputBytes, int iterations)(in const(char)[] pass, in ubyte[] salt)
{
	ubyte[outputBytes] digest;
	PKCS5_PBKDF2_HMAC(pass.ptr, cast(int) pass.length, salt.ptr, cast(int) salt.length, iterations, EVP_sha512(), outputBytes, digest.ptr);
	return digest;
}

/// Generates the PBKDF2 HMAC SHA-512 hash with 64 output bytes and 65536 iterations (default password hashing here)
alias hashPassword = PBKDF2_HMAC_SHA_512_string!(64, 65536);