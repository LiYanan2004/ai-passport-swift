#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

typedef void (*stack_workload_t)(void);

static void *run_workload(void *context) {
    stack_workload_t *workload = context;
    (*workload)();
    return NULL;
}

size_t test_run_with_stack_budget(stack_workload_t workload, size_t stack_size) {
    const size_t page_size = (size_t)sysconf(_SC_PAGESIZE);
    assert(stack_size % page_size == 0);
    const size_t allocation_size = stack_size + 2 * page_size;
    uint8_t *allocation = mmap(NULL, allocation_size, PROT_NONE,
                               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    assert(allocation != MAP_FAILED);
    uint8_t *stack = allocation + page_size;
    assert(mprotect(stack, stack_size, PROT_READ | PROT_WRITE) == 0);
    memset(stack, 0xa5, stack_size);

    pthread_attr_t attributes;
    assert(pthread_attr_init(&attributes) == 0);
    assert(pthread_attr_setguardsize(&attributes, 0) == 0);
    assert(pthread_attr_setstack(&attributes, stack, stack_size) == 0);
    pthread_t thread;
    assert(pthread_create(&thread, &attributes, run_workload, &workload) == 0);
    assert(pthread_attr_destroy(&attributes) == 0);
    assert(pthread_join(thread, NULL) == 0);

    size_t untouched = 0;
    while (untouched < stack_size && stack[untouched] == 0xa5) ++untouched;
    const size_t used = stack_size - untouched;
    assert(munmap(allocation, allocation_size) == 0);
    return used;
}
