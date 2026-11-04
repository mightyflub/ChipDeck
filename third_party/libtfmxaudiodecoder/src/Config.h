/* ChipDeck: replaces the autoconf-generated Config.h (see third_party/README.md).
 * All supported compilers have <stdint.h> and the fixed width types. */
#ifndef TFMX_CONFIG_H
#define TFMX_CONFIG_H
#define HAVE_STDINT_H 1
#define HAVE_STRING_H 1
#define HAVE_STDLIB_H 1
#define PACKAGE_VERSION "1.0.14"
#endif
