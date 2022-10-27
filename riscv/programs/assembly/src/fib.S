# See LICENSE for license details.

#*****************************************************************************
# fib.S
#-----------------------------------------------------------------------------
#include "riscv_test.h"
#include "test_macros.h"

/*
#define TEST_FIB (in, correctval, fib_label, code... ) \
test_ ## testnum: \
  j fib_label; \
  li x29, correctval;
  li in, correctval; 

*/

RVTEST_RV32U
RVTEST_CODE_BEGIN

li t3, 1
li a0, 0
//t5: i, 
// t6: fib; 
//t7: nfib, 
//t8: nnfib
//assume param n is a0
li t5, 0 //i
li t6, 0 //fib
li t7, 1 //nfib
loop: 
  bge t5, a0, end // if i >= n, branch to return
  add t8, t6, t7 
  mv t6, t7
  mv t7, t8
  addi t5,t5, 1 //i++
  blt t5, a0, loop

  
end:
  //check
  li t5,100
  beq t6, t5, pass


  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END



