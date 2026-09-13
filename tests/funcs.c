int add3(int a,int b){ return a+b+3; }
int mul5(int x){ return x*5; }
int f3(int a,int b,int c){ return a*100 + b*10 + c; }
int sub_mul(int a,int b){ return a*b - b; }
int checksum(const unsigned char *p, int n){ int s=0; for(int i=0;i<n;i++) s=s*31+p[i]; return s; }
