#include <stdlib.h>
#include <semaphore.h>

class MemInitRequestProxy;

class Platform {
public:
    Platform(MemInitRequestProxy* ptr, sem_t* sem);
    virtual ~Platform() { delete[] buffer; }
    bool load_elf(const char* elf_filename);
    virtual void write_chunk(uint64_t taddr, size_t len, const void* src);
private:
    MemInitRequestProxy* mem_init_req_proxy;
    sem_t* resp_sem;
    char* buffer;
    template <typename Elf_Ehdr, typename Elf_Phdr>
        bool load_elf_specific(char* buf, size_t elf_sz);
};

