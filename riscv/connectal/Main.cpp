#include <stdio.h>
#include <stdint.h>
#include <sys/stat.h>
#include <pthread.h>
#include <semaphore.h>

#include "StartRequest.h"
#include "MemInitRequest.h"
#include "MyDutIndication.h"

#include "Platform.hpp"

sem_t resp_sem;
volatile int run = 1;
uint32_t print_int = 0;

// The seperate thread in charge of indications invokes these call-back functions
class MyDutIndication : public MyDutIndicationWrapper {
public:
    // You have to define all the functions (indication methods) defined in MyDutIndication
    virtual void returnOutput(uint32_t msg) {
        uint32_t type = msg >> 16 ;
        uint32_t data = msg & ((1<<16) - 1);
        if (type == 0) {
            if (data == 0) {
                fprintf(stderr, "PASSED\n");
            } else {
                fprintf(stderr, "FAILED: exit code = %d\n", data);
            }
            run = 0;
        } else if (type == 1) {
            fprintf(stderr, "%c", (char)data);
        } else if (type == 2) {
            print_int = uint32_t(data);
        } else if (type == 3) {
            print_int |= uint32_t(data) << 16;
            fprintf(stderr, "%d", print_int);
        }
    }

    virtual void wroteWord(uint8_t msg) { sem_post(&resp_sem); }

    // Required
    MyDutIndication(unsigned int id) : MyDutIndicationWrapper(id) { }
};

int main (int argc, const char **argv) {
    printf("Start testbench:\n");
    // Service Indication messages from HW - Register the call-back functions to a indication thread
    MyDutIndication myIndication (IfcNames_MyDutIndicationH2S);

    // Open a channel to FPGA to issue requests
    StartRequestProxy *start_req = new StartRequestProxy(IfcNames_StartRequestS2H);

    // Invoke reset_dut method of HW request ifc (Soft-reset)
    printf("Soft Resetting the Processor\n");
    start_req->reset_dut();

    printf("Start Loading the Program\n");
    MemInitRequestProxy *mem_init_req = new MemInitRequestProxy(IfcNames_MemInitRequestS2H);

    Platform *platform = new Platform(mem_init_req, &resp_sem);
    char cwd[1024];
    platform->load_elf(strcat(getcwd(cwd, sizeof(cwd)), "/program"));
    mem_init_req->done();
    printf("Finished Loading the Program\n");

    start_req->start_dut(0x200);
    printf("Start PC set\n");

    // Now the processor is running we are waiting for it to be done 
    while (run != 0) { }

    printf("Processor finished\n");
    delete start_req;
    delete mem_init_req;
    delete platform;
    return 0;
}
