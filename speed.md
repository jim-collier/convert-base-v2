<!-- markdownlint-disable MD007 -- Unordered list indentation -->
<!-- markdownlint-disable MD010 -- No hard tabs -->
<!-- markdownlint-disable MD055 -- Table pipe style [Expected: leading_and_trailing; Actual: leading_only; Missing trailing pipe] -->
<!-- markdownlint-disable MD041 -- First line in a file should be a top-level heading -->
<!-- TOC ignore:true -->
# Speed

Back to the [README](README.md).

`convert-base-v2` is fast enough to sit in a pipe next to the coreutils tools without being the bottleneck.

There are two jobs here with two different cost curves, so they are measured separately: streaming a file through a codec, and converting one very large number between two arbitrary bases.

<!-- TOC ignore:true -->
## Table of contents

<!-- TOC -->

- [Streaming binary and text](#streaming-binary-and-text)
	- [Base 64](#base-64)
	- [Base 32](#base-32)
	- [Hex](#hex)
- [Large numbers](#large-numbers)

<!-- /TOC -->

## Streaming binary and text

Binary and text stream encoding is the part that benchmarks cleanly, so here is measured throughput against the standard tools, one table per format. It decodes faster than the standard tools, and encodes in the same ballpark.

### Base 64

| Program            | text -> binary | binary -> text
| :----------------- | -------------: | -------------:
| `convert-base-v2`  |        **744** |            755
| coreutils `base64` |            323 |          1,056
| coreutils `basenc` |            323 |          1,048
| openssl `base64`   |            276 |      **1,221**

### Base 32

| Program            | text -> binary | binary -> text
| :----------------- | -------------: | -------------:
| `convert-base-v2`  |        **596** |            716
| coreutils `base32` |            400 |        **855**
| coreutils `basenc` |            376 |            851

### Hex

| Program           | text -> binary | binary -> text
| :---------------- | -------------: | -------------:
| `convert-base-v2` |        **521** |        **850**
| `xxd`             |             57 |            102

Numbers are MiB/s. Mean of 10 runs, one process each, all I/O in a tmpfs (RAM) so disk speed doesn't enter into it. Every program gets identical input: the same 256 MiB blob of random bytes to encode, and each format's own canonical text to decode. Each tool is single-threaded. Reproducible with `utility/bench-encoders.bash` (it auto-skips tools you don't have). Test bench: AMD Ryzen 9 3950X (16 cores / 32 threads, Zen 2), 128 GiB DDR4-3600.

Memory stays flat no matter how big the file is, for every base that can encode raw bytes, ASCII or not. A 48 MB file encoded to `64emoji` or to base 65536 stays under 20 MB.

Base 64 is the usual default for binary as UTF-8 text, and the tightest of the power-of-two bases. Base 85 and base 91 are a little tighter, but use punctuation that often needs escaping.

- Modern operating systems use UTF-8. Best power-of-two base for it: base 64.

- Some APIs use UTF-16 internally. Best base for it: base 32768.

- Others use UTF-32. Best base for it: base 65536.

- For binary tucked into a Twitter/X post, qntm's base 2048 is the reported optimum.

## Large numbers

Converting between two arbitrary bases isn't a bit operation. Base 10 to base 36 has no shortcut through binary, so the value has to be built up and taken back apart with real arithmetic. The textbook way to do that costs one pass over the whole number per digit, in both directions, which is quadratic. At a few thousand digits nobody notices. At a million digits it is minutes.

This uses the published subquadratic method instead.

- The core is divide and conquer radix conversion. A long digit run is cut in half, each half is converted on its own, and the two are rejoined with a single wide multiply on the way in, or separated by a single wide divide on the way out. The powers of the radix at each split width are built once by repeated squaring and reused for the whole recursion. This is Schonhage's algorithm, written up as `FastIntegerInput` and `FastIntegerOutput` in Brent and Zimmermann, [Modern Computer Arithmetic](https://members.loria.fr/PZimmermann/mca/pub226.html) (Cambridge University Press, 2010), section 1.7. It costs `O(M(n) log n)`, where `M(n)` is the cost of one multiply, against `O(n^2)` for the schoolbook loop. Go's own `math/big` converts to and from decimal the same way.

- Splitting the number only pays if the multiply that rejoins the halves also beats `O(n^2)`. Karatsuba multiplication gets three half-size products to do the work of four, for `O(n^1.585)`. It's from Karatsuba and Ofman, "Multiplication of Multidigit Numbers on Automata" (Doklady Akademii Nauk SSSR 145, 1962). It comes from `math/big`, and it is where the recursion spends most of its time.

- The output leg splits by dividing rather than multiplying, so it needs division to be subquadratic for exactly the same reason. That's Burnikel-Ziegler recursive division, from ["Fast Recursive Division"](https://pure.mpg.de/rest/items/item_1819444/component/file_2599480/content) (Max Planck Institute for Informatics, MPI-I-98-1-022, 1998). Also from `math/big`.

- Below the recursion cutoff, digits aren't handled one at a time. As many as fit in a 64-bit machine word are packed with ordinary integer arithmetic, and only then does one bignum operation handle the whole group: 19 digits at a time for base 10, 12 for base 36, 5 for base 2048. That is the classical `b^k` radix trick from Knuth, *The Art of Computer Programming*, volume 2, section 4.4, and it buys a constant factor of `k`. The leaf loops themselves are Horner's rule going in and repeated division coming out.

- Between two power-of-two bases, and for the byte codecs, there's no arithmetic at all. A conversion is only a regrouping of bits. That path is `O(n)`, streams in constant memory, and never builds a bignum. It is the path the throughput tables above measure.

Measured base 10 to base 36, against a straight schoolbook implementation on the same hardware using the same `math/big`:

| Input digits | Schoolbook | `convert-base-v2` | Faster by
| -----------: | ---------: | ----------------: | --------:
|        1,000 |    0.16 ms |           0.04 ms |        4x
|        4,000 |    1.99 ms |           0.20 ms |       10x
|       16,000 |      29 ms |            1.0 ms |       28x
|       64,000 |     443 ms |            6.4 ms |       69x
|      256,000 |      7.0 s |             47 ms |      150x
|    1,000,000 |      107 s |            0.34 s |      310x

Four million digits convert in about 2.9 seconds. Same bench as the tables above, with both implementations in one process so the arithmetic library and the machine are held constant.

The gap widens with size because the two are on different curves, not because one is tuned better. Fit an exponent to each column and the schoolbook one measures 2.00, while this one runs at 1.15 for short values and 1.53 at the top of the table.

Short numbers pay nothing for any of it. Below the cutoff the recursion never starts, and a number of ordinary length converts in a few microseconds.
