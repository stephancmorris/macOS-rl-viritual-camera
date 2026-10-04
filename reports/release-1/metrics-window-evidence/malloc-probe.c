#include <malloc/malloc.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <execinfo.h>
#include <stdio.h>

// Launch-only malloc-family interposer. Counts actual allocator requests, without
// stack tracing or any app/file mutation. Stats are read outside the timed loop.
static malloc_zone_t *zone;
static _Atomic int enabled;
static _Atomic uint64_t requests, requested_bytes;
static void *sampled_stacks[64][32];
static size_t sampled_sizes[64];
static int sampled_depths[64], sample_count, wants_stacks;
static _Thread_local int inside_stack;
__attribute__((constructor)) static void prepare(void) { zone = malloc_default_zone(); }
static void record(size_t size) {
    if (atomic_load_explicit(&enabled, memory_order_relaxed)) {
        uint64_t request = atomic_fetch_add_explicit(&requests, 1, memory_order_relaxed);
        atomic_fetch_add_explicit(&requested_bytes, size, memory_order_relaxed);
        if (wants_stacks && !inside_stack && request % 1024 == 0 && sample_count < 64) {
            inside_stack = 1;
            sampled_sizes[sample_count] = size;
            sampled_depths[sample_count] = backtrace(sampled_stacks[sample_count], 32);
            sample_count += 1;
            inside_stack = 0;
        }
    }
}
void *probe_malloc(size_t size) { void *p = malloc_zone_malloc(zone ? zone : malloc_default_zone(), size); record(size); return p; }
void *probe_calloc(size_t count, size_t size) {
    void *p = malloc_zone_calloc(zone ? zone : malloc_default_zone(), count, size); record(count * size); return p;
}
void *probe_realloc(void *p, size_t size) {
    malloc_zone_t *owner = p ? malloc_zone_from_ptr(p) : (zone ? zone : malloc_default_zone());
    void *result = malloc_zone_realloc(owner, p, size); record(size); return result;
}
void probe_allocation_begin(void) {
    atomic_store(&enabled, 0); atomic_store(&requests, 0); atomic_store(&requested_bytes, 0);
    sample_count = 0; wants_stacks = getenv("ALFIE_ALLOCATION_STACKS") != NULL;
    atomic_store(&enabled, 1);
}
void probe_allocation_dump(void) {
    atomic_store(&enabled, 0);
    for (int i = 0; i < sample_count; i++) {
        fprintf(stderr, "ALLOCATION_STACK %d requested_bytes=%zu\n", i, sampled_sizes[i]);
        backtrace_symbols_fd(sampled_stacks[i], sampled_depths[i], 2);
    }
}
uint64_t probe_allocation_end(int index) {
    atomic_store(&enabled, 0);
    return atomic_load(index == 0 ? &requests : &requested_bytes);
}
#define INTERPOSE(replacement, original) \
  __attribute__((used)) static struct { const void *new; const void *old; } interpose_##original \
  __attribute__((section("__DATA,__interpose"))) = { (const void *)(replacement), (const void *)(original) };
INTERPOSE(probe_malloc, malloc)
INTERPOSE(probe_calloc, calloc)
INTERPOSE(probe_realloc, realloc)
