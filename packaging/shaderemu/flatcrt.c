/* bFLT start for musl (after ShaderEmu's linux/nommu/flatcrt.c), with AT_PHDR/AT_PHNUM/AT_PHENT
   added so musl's static TLS setup and dl_iterate_phdr (used by D's runtime) find the program
   headers, which sit at the start of the loaded image. */
#include <elf.h>
int main();
__attribute__((weak)) void _init(void) {}
__attribute__((weak)) void _fini(void) {}
int __libc_start_main(int (*)(), int, char **, void (*)(void), void (*)(void), void (*)(void));
extern const Elf32_Ehdr __ehdr_start __attribute__((visibility("hidden")));

__attribute__((used)) void _flat_start_c(long *p)
{
    int argc = p[0], envc = 0, i, n = 0;
    char **argv = (char **)(p + 1), **envp = argv + argc + 1;
    while (envp[envc]) envc++;
    long v[argc + envc + 12];
    for (i = 0; i < argc; i++) v[n++] = (long)argv[i];
    v[n++] = 0;
    for (i = 0; i < envc; i++) v[n++] = (long)envp[i];
    v[n++] = 0;
    v[n++] = AT_PAGESZ; v[n++] = 4096;
    v[n++] = AT_PHDR;   v[n++] = (long)((const char *)&__ehdr_start + __ehdr_start.e_phoff);
    v[n++] = AT_PHENT;  v[n++] = __ehdr_start.e_phentsize;
    v[n++] = AT_PHNUM;  v[n++] = __ehdr_start.e_phnum;
    v[n++] = 0; v[n++] = 0;
    __libc_start_main(main, argc, (char **)v, _init, _fini, 0);
}

__asm__(".text\n.global _flat_start\n_flat_start:\n.weak __global_pointer$\n.hidden __global_pointer$\n"
    ".option push\n.option norelax\nlla gp, __global_pointer$\n.option pop\n"
    "mv a0, sp\nandi sp, sp, -16\ntail _flat_start_c\n");

__asm__(".text\n.global vfork\n.type vfork,%function\nvfork:\nli a7, 220\nli a0, 0x4111\nmv a1, sp\necall\n"
    ".hidden __syscall_ret\ntail __syscall_ret\n");
