// dr_flac ships as a single header that compiles its implementation only where
// DR_FLAC_IMPLEMENTATION is defined. This is that one translation unit.
//
// Ogg-encapsulated FLAC is switched off: every corpus here is native FLAC, and the
// Ogg path is a large slab of code with its own seeking rules.
#define DR_FLAC_NO_OGG
#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"
