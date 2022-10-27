#include "util.h"

int fibloop( int n ) {
  int fib = 0;
  int nfib = 1;
  int nnfib;
  for (int i = 0; i < n; i++) {
    nnfib = fib + nfib; 
    fib = nfib;
    nfib = nnfib;
  }
  return fib;
}


int fib( int n ) {
  //base case
  if (n<2) {
    return n;
  }
  else {
  //recursive case
    return fib(n-2) + fib(n-1);
  }
}



int main( int argc, char* argv[] )
{
  for (int i=0; i<10; i=i+1) {
    int res = fibloop (i); 
    printInt(res);
  }
}
