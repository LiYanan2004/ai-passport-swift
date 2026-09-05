#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

static bool recording;
static size_t maximum_allocation;

void test_begin_allocation_recording(void) {
    maximum_allocation = 0;
    recording = true;
}

size_t test_end_allocation_recording(void) {
    recording = false;
    return maximum_allocation;
}

#ifdef __APPLE__
static int record_posix_memalign(void **memory, size_t alignment, size_t size) {
    if (recording && size > maximum_allocation) maximum_allocation = size;
    return posix_memalign(memory, alignment, size);
}

// Embedded Swift allocates objects through posix_memalign on both host and device.
__attribute__((used, section("__DATA,__interpose")))
static const struct {
    int (*replacement)(void **, size_t, size_t);
    int (*original)(void **, size_t, size_t);
} allocation_interpose = {record_posix_memalign, posix_memalign};
#else
int __real_posix_memalign(void **memory, size_t alignment, size_t size);

int __wrap_posix_memalign(void **memory, size_t alignment, size_t size) {
    if (recording && size > maximum_allocation) maximum_allocation = size;
    return __real_posix_memalign(memory, alignment, size);
}
#endif
