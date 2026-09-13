int helper(int x){ return x*7 + 1; }
int caller(int a){ return helper(a) + helper(a+1); }
